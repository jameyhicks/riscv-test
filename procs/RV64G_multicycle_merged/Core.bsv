import ClientServer::*;
import Connectable::*;
import DefaultValue::*;
import FIFO::*;
import GetPut::*;
import Vector::*;

import Abstraction::*;
import RegUtil::*;
import RVRFile::*;
import RVCsrFile::*;
import RVExec::*;
import RVFpu::*;
import RVMulDiv::*;
import RVTypes::*;
import VerificationPacket::*;

import RVAlu::*;
import RVControl::*;
import RVDecode::*;
import RVMemory::*;

// This interface is the combination of FrontEnd and BackEnd
interface Core;
    method Action start(Addr startPc);
    method Action stop;

    method Action configure(Data miobase);
    method ActionValue#(VerificationPacket) getVerificationPacket;
    method ActionValue#(VMInfo) updateVMInfoI;
    method ActionValue#(VMInfo) updateVMInfoD;

    interface Client#(RVIMMUReq, RVIMMUResp) ivat;
    interface Client#(RVIMemReq, RVIMemResp) ifetch;
    interface Client#(RVDMMUReq, RVDMMUResp) dvat;
    interface Client#(RVDMemReq, RVDMemResp) dmem;
    interface Client#(FenceReq, FenceResp) fence;
    interface Client#(Data, Data) htif;
endinterface

instance Connectable#(Core, MemorySystem);
    module mkConnection#(Core core, MemorySystem mem)(Empty);
        mkConnection(core.ivat, mem.ivat);
        mkConnection(core.ifetch, mem.ifetch);
        mkConnection(core.dvat, mem.dvat);
        mkConnection(core.dmem, mem.dmem);
        mkConnection(core.fence, mem.fence);
        mkConnection(toGet(core.updateVMInfoI), toPut(mem.updateVMInfoI));
        mkConnection(toGet(core.updateVMInfoD), toPut(mem.updateVMInfoD));
    endmodule
endinstance

typedef enum {
    Wait,
    IMMU,
    IF,
    Dec,
    RegRead,
    Execute,
    Mem,
    WB,
    Trap,
    Trap2
} ProcState deriving (Bits, Eq, FShow);

(* synthesize *)
module mkMulticycleCore(Core);
    let verbose = False;
    File fout = stdout;

    ArchRFile rf <- mkArchRFile;
    RVCsrFile csrf <- mkRVCsrFile;
    MulDivExec mulDiv <- mkBoothRoughMulDivExec;
    FpuExec fpu <- mkFpuExecPipeline;

    Reg#(Bool) htifStall <- mkReg(False);
    Reg#(Bool) running <- mkReg(False);
    Reg#(ProcState) state <- mkReg(Wait);

    Reg#(Addr) pc <- mkReg(0);
    Reg#(Maybe#(ExceptionCause)) exception <- mkReg(tagged Invalid);
    Reg#(Instruction) inst <- mkReg(0);
    Reg#(RVDecodedInst) dInst <- mkReg(unpack(0));
    Reg#(FrontEndCsrs) csrState <- mkReadOnlyReg( FrontEndCsrs { vmI: csrf.vmI, state: csrf.csrState } );

    FIFO#(RVIMMUReq)    immuReq <- mkFIFO1;
    FIFO#(RVIMMUResp)   immuResp <- mkFIFO1;

    FIFO#(RVIMemReq)    imemReq <- mkFIFO1;
    FIFO#(RVIMemResp)   imemResp <- mkFIFO1;

    Reg#(Data) rVal1 <- mkReg(0);
    Reg#(Data) rVal2 <- mkReg(0);
    Reg#(Data) rVal3 <- mkReg(0);
    Reg#(Data) data <- mkReg(0);
    Reg#(Data) addr <- mkReg(0);
    Reg#(Data) nextPc <- mkReg(0);

    FIFO#(RVDMMUReq)    dmmuReq <- mkFIFO1;
    FIFO#(RVDMMUResp)   dmmuResp <- mkFIFO1;

    FIFO#(RVDMemReq)    dmemReq <- mkFIFO1;
    FIFO#(RVDMemResp)   dmemResp <- mkFIFO1;

    FIFO#(Data)         toHost <- mkFIFO1;
    FIFO#(Data)         fromHost <- mkFIFO1;

    FIFO#(VerificationPacket) verificationPackets <- mkFIFO1;

    rule doInstMMU(running && state == IMMU);
        // request address translation from MMU
        immuReq.enq(pc);
        // reset states
        inst <= unpack(0);
        dInst <= unpack(0);
        exception <= tagged Invalid;
        // go to InstFetch stage
        state <= IF;
    endrule

    rule doInstFetch(state == IF);
        // I wanted notation like this:
        // let {addr: .phyPc, exception: .exMMU} = mmuResp.first;

        let phyPc = immuResp.first.addr;
        let exMMU = immuResp.first.exception;
        immuResp.deq;

        if (!isValid(exMMU)) begin
            // no translation exception
            imemReq.enq(phyPc);
            // go to decode stage
            state <= Dec;
        end else begin
            // translation exception (instruction access fault)
            exception <= exMMU;
            // send instruction to backend
            state <= Trap;
        end
    endrule

    rule doDecode(state == Dec);
        let fInst = imemResp.first;
        imemResp.deq;

        let decInst = decodeInst(fInst);

        if (decInst matches tagged Valid .validDInst) begin
            // Legal instruction
            dInst <= validDInst;
        end else begin
            // Illegal instruction
            exception <= tagged Valid IllegalInst;
        end

        inst <= fInst;
        state <= isValid(decInst) ? RegRead : Trap;
    endrule

    rule doRegRead(!htifStall && state == RegRead);
        rVal1 <= rf.rd1(toFullRegIndex(dInst.rs1, getInstFields(inst).rs1));
        rVal2 <= rf.rd2(toFullRegIndex(dInst.rs2, getInstFields(inst).rs2));
        rVal3 <= rf.rd3(toFullRegIndex(dInst.rs3, getInstFields(inst).rs3));
        state <= Execute;
    endrule

    rule doExecute(state == Execute);
        let dataEx = 0;
        let addrEx = 0;
        let nextPcEx = pc + 4;

        Maybe#(Data) imm = getImmediate(dInst.imm, dInst.inst);
        case (dInst.execFunc) matches
            tagged Alu    .aluInst:
                begin
                    dataEx = execAluInst(aluInst, rVal1, rVal2, imm, pc);
                end
            tagged Br     .brFunc:
                begin
                    // data for jal
                    dataEx = pc + 4;
                    nextPcEx = execControl(brFunc, rVal1, rVal2, imm, pc);
                end
            tagged Mem    .memInst:
                begin
                    // data for store and AMO
                    dataEx = rVal2;
                    addrEx = addrCalc(rVal1, imm);
                    dmmuReq.enq(RVDMMUReq {addr: addrEx, size: memInst.size, op: (memInst.op matches tagged Mem .memOp ? memOp : St)});
                end
            tagged MulDiv .mulDivInst: mulDiv.exec(mulDivInst, rVal1, rVal2);
            tagged Fence  .fenceInst:  noAction;
            // TODO: Handle dynamic rounding mode
            tagged Fpu    .fpuInst:    fpu.exec(fpuInst, getInstFields(inst).rm, rVal1, rVal2, rVal3);
            tagged System .systemInst:
                begin
                    // data for CSR instructions
                    dataEx = fromMaybe(rVal1, imm);
                end
        endcase

        data <= dataEx;
        addr <= addrEx;
        nextPc <= nextPcEx;

        state <= dInst.execFunc matches tagged Mem .* ? Mem : WB;
    endrule

    rule doMem(state == Mem);
        let pAddr = dmmuResp.first.addr;
        let exMMU = dmmuResp.first.exception;
        dmmuResp.deq;

        // TODO: make this type safe! get rid of .Mem accesses to tagged union
        if (!isValid(exMMU)) begin
            dmemReq.enq( RVDMemReq {
                    op: dInst.execFunc.Mem.op,
                    byteEn: toByteEn(dInst.execFunc.Mem.size),
                    addr: pAddr,
                    data: data,
                    unsignedLd: isUnsigned(dInst.execFunc.Mem.size) } );
            state <= WB;
        end else begin
            exception <= exMMU;
            state <= Trap;
        end
    endrule

    rule doWB(state == WB);
        let dataWb = data;
        let addrWb = addr;
        let nextPcWb = nextPc;
        let fflagsWb = 0;
        let exceptionWB = exception;

        case(dInst.execFunc) matches
            tagged MulDiv .*: begin
                    dataWb = mulDiv.result_data();
                    mulDiv.result_deq;
                end
            tagged Fpu .*: begin
                    let fpuResult = toFullResult(fpu.result_data);
                    dataWb = fpuResult.data;
                    fflagsWb = fpuResult.fflags;
                    fpu.result_deq;
                end
            tagged Mem .memInst:
                begin
                    if (getsResponse(memInst.op)) begin
                        dataWb = dmemResp.first;
                        dmemResp.deq;
                    end
                end
        endcase

        // TODO: add comment
        Bool extensionDirty = False;
        Bool fpuDirty = (dInst.dst == tagged Valid Fpu);
        let {maybeTrap, maybeData, maybeNextPc} <- csrf.wr(
                // performing system instructions
                dInst.execFunc matches tagged System .sysInst ? tagged Valid sysInst : tagged Invalid,
                getInstFields(inst).csr,
                dataWb,  // either rf[rs1] or zimm, computed in basicExec
                // handling exceptions
                exceptionWB,    // exception cause
                pc,             // for writing to mepc/sepc
                dInst.execFunc matches tagged Br .* ? True : False, // check inst allignment if Br Func
                dInst.execFunc matches tagged Br .* ? nextPcWb : addrWb, // either data address or next PC, used to detect misaligned instruction addresses
                // indirect writes
                fflagsWb,
                fpuDirty,
                extensionDirty);

        // send verification packet
        verificationPackets.enq( VerificationPacket {
                skippedPackets: 0,
                pc: pc,
                nextPc: fromMaybe(nextPcWb, maybeNextPc),
                data: fromMaybe(dataWb, maybeData),
                addr: addr,
                instruction: inst,
                dst: {pack(dInst.dst), getInstFields(inst).rd},
                trap: isValid(maybeTrap),
                trapType: (case (fromMaybe(unpack(0), maybeTrap)) matches
                        tagged Exception .x: (zeroExtend(pack(x)));
                        tagged Interrupt .x: (zeroExtend(pack(x)) | 8'h80);
                    endcase) });

        if (maybeNextPc matches tagged Valid .replayPc) begin
            // This instruction didn't retire

            // redirect happens in Trap2
            nextPc <= replayPc;
            state <= Trap2;
        end else begin
            // This instruction retired
            // write to the register file
            rf.wr(toFullRegIndex(dInst.dst, getInstFields(inst).rd), fromMaybe(dataWb, maybeData));
            // always redirect
            pc <= nextPc;
            state <= IMMU;
        end
    endrule

    rule doTrap(state == Trap);
        // TODO: move this to WB
        let {maybeTrap, maybeData, maybeNextPc} <- csrf.wr(
                tagged Invalid,
                getInstFields(inst).csr,
                0, // data
                exception, // exception cause
                pc, // pc
                False, 
                addr, // vaddr
                0,
                False,
                False);

        // send verification packet
        verificationPackets.enq( VerificationPacket {
                skippedPackets: 0,
                pc: pc,
                nextPc: fromMaybe(?, maybeNextPc),
                data: fromMaybe(data, maybeData),
                addr: addr,
                instruction: inst,
                dst: {pack(dInst.dst), getInstFields(inst).rd},
                trap: isValid(maybeTrap),
                trapType: (case (fromMaybe(unpack(0), maybeTrap)) matches
                        tagged Exception .x: (zeroExtend(pack(x)));
                        tagged Interrupt .x: (zeroExtend(pack(x)) | 8'h80);
                    endcase) });

        // redirection will happpen in trap2
        // by construction maybeNextPc is always valid
        nextPc <= fromMaybe(nextPc, maybeNextPc);
        state <= Trap2;
    endrule

    // There is a second trap state to ensure that the frontEndCsrs reflect the updated state of the processor
    rule doTrap2(state == Trap2);
        pc <= nextPc;
        state <= IMMU;
    endrule

    rule htifToHost;
        let msg <- csrf.csrfToHost;
        if (truncateLSB(msg) != 16'h0100) begin
            htifStall <= True;
        end
        toHost.enq(msg);
    endrule

    rule htifFromHost;
        htifStall <= False;
        let msg = fromHost.first;
        fromHost.deq;
        csrf.hostToCsrf(msg);
    endrule

    interface Client ivat = toGPClient(immuReq, immuResp);
    interface Client ifetch = toGPClient(imemReq, imemResp);

    method Action start(Addr startPc);
        running <= True;
        pc <= startPc;
        state <= IMMU;
        csrState <= defaultValue;
        if (verbose) $fdisplay(fout, "[frontend] starting from pc = 0x%08x", startPc);
    endmethod
    method Action stop;
        running <= False;
        state <= Wait;
    endmethod

    interface Client dvat = toGPClient(dmmuReq, dmmuResp);
    interface Client dmem = toGPClient(dmemReq, dmemResp);
    interface Client htif = toGPClient(toHost, fromHost);

    method Action configure(Data miobase);
        csrf.configure(miobase);
    endmethod
    method ActionValue#(VerificationPacket) getVerificationPacket;
        let verificationPacket = verificationPackets.first;
        verificationPackets.deq;
        return verificationPacket;
    endmethod

    method ActionValue#(VMInfo) updateVMInfoI;
        return csrf.vmI;
    endmethod
    method ActionValue#(VMInfo) updateVMInfoD;
        return csrf.vmD;
    endmethod
endmodule
