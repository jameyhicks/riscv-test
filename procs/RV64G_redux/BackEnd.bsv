// `include "PerfMonitor.defines"
import PerfMonitor::*;
import ModuleContext::*;

import ClientServer::*;
import DefaultValue::*;
import FIFO::*;
import Vector::*;

import Abstraction::*;
import RVRFile::*;
import RVCsrFile::*;
import RVExec::*;
import RVFpu::*;
import RVMulDiv::*;
import RVTypes::*;
import VerificationPacket::*;

typedef enum {
    Wait,
    RegRead,
    Execute,
    Mem,
    WB,
    Trap,
    Trap2
} BEState deriving (Bits, Eq, FShow);

// (* synthesize *)
// module `mkPerfModule("BackEnd", mkMulticycleBackEnd, BackEnd#(void));
(* synthesize *)
module [Module] mkMulticycleBackEndV(Tuple2#(PerfMonitor, BackEnd#(void)));
    (* hide *)
    let _m <- toSynthBoundary("BackEnd", mkMulticycleBackEnd0);
    return _m;
endmodule
module [m] mkMulticycleBackEnd(BackEnd#(void)) provisos (HasPerfCounters#(m));
    (* hide *)
    let _m <- fromSynthBoundary("BackEnd", mkMulticycleBackEndV);
    return _m;
endmodule
module [m] mkMulticycleBackEnd0(BackEnd#(void)) provisos (HasPerfCounters#(m));
    let verbose = False;
    File fout = stdout;

    Reg#(Bool) htifStall <- mkReg(False);

    Reg#(Addr) pc <- mkReg(0);
    Reg#(Instruction) inst <- mkReg(0);
    /// XXX: Reg#(InstructionFields) instFields <- mkReg(unpack(0));
    Reg#(Maybe#(ExceptionCause)) exception <- mkReg(tagged Invalid);
    Reg#(RVDecodedInst) dInst <- mkReg(unpack(0));
    Reg#(BEState) state <- mkReg(Wait);
    Reg#(Data) rVal1 <- mkReg(0);
    Reg#(Data) rVal2 <- mkReg(0);
    Reg#(Data) rVal3 <- mkReg(0);
    Reg#(FullResult) result <- mkReg(unpack(0));

    ArchRFile rf <- mkArchRFile;
    RVCsrFile csrf <- mkRVCsrFile;
    MulDivExec mulDiv <- mkBoothRoughMulDivExec;
    FpuExec fpu <- mkFpuExecPipeline;

    FIFO#(FrontEndToBackEnd#(void)) toBackEnd <- mkFIFO;
    FIFO#(Redirect#(void)) redirect <- mkFIFO;

    FIFO#(RVDMMUReq)    mmuReq <- mkFIFO;
    FIFO#(RVDMMUResp)   mmuResp <- mkFIFO;

    FIFO#(RVDMemReq)    memReq <- mkFIFO;
    FIFO#(RVDMemResp)   memResp <- mkFIFO;

    FIFO#(Data)         toHost <- mkFIFO;
    FIFO#(Data)         fromHost <- mkFIFO;

    FIFO#(VerificationPacket) verificationPackets <- mkFIFO;

    // performance counters
    PerfCounter loadCounter <- mkPerfCounter("loads");
    PerfCounter storeCounter <- mkPerfCounter("stores");
    PerfCounter dataFaultCounter <- mkPerfCounter("data-faults");

    rule doRegRead(!htifStall && state == RegRead);
        rVal1 <= rf.rd1(fromMaybe(Gpr, dInst.rs1), getInstFields(inst).rs1);
        rVal2 <= rf.rd2(fromMaybe(Gpr, dInst.rs2), getInstFields(inst).rs2);
        rVal3 <= rf.rd3(fromMaybe(Gpr, dInst.rs3), getInstFields(inst).rs3);
        state <= Execute;
    endrule

    rule doExecute(state == Execute);
        let resultEx = toFullResult(basicExec(dInst, rVal1, rVal2, pc, '1 /* ppc */ ));
        // special cases beyond integer ALU:
        case (dInst.execFunc) matches
            tagged MulDiv .mulDivInst: mulDiv.exec(mulDivInst, rVal1, rVal2);
            tagged Fpu    .fpuInst:    fpu.exec(fpuInst, getInstFields(inst).rm, rVal1, rVal2, rVal3);
            tagged Mem    .memInst:    mmuReq.enq(RVDMMUReq {addr: resultEx.vaddr, size: memInst.size, op: (memInst.op matches tagged Mem .memOp ? memOp : St)});
        endcase
        result <= resultEx;
        state <= dInst.execFunc matches tagged Mem .* ? Mem : WB;
    endrule

    rule doMem(state == Mem);
        let pAddr = mmuResp.first.addr;
        let exMMU = mmuResp.first.exception;
        mmuResp.deq;

        // TODO: make this type safe! get rid of .Mem accesses to tagged union
        if (!isValid(exMMU)) begin
            memReq.enq( RVDMemReq {
                    op: dInst.execFunc.Mem.op,
                    byteEn: toByteEn(dInst.execFunc.Mem.size),
                    addr: pAddr,
                    data: result.data,
                    unsignedLd: isUnsigned(dInst.execFunc.Mem.size) } );
            if (dInst.execFunc.Mem.op == tagged Mem Ld) begin
                loadCounter.increment(1);
            end else begin
                storeCounter.increment(1);
            end
            state <= WB;
        end else begin
            exception <= exMMU;
            dataFaultCounter.increment(1);
            state <= Trap;
        end
    endrule

    rule doWB(state == WB);
        let resultWB = result;
        let exceptionWB = exception;
        let nextPc = result.controlFlow.nextPc;
        case(dInst.execFunc) matches
            tagged MulDiv .*: begin
                    resultWB.data = mulDiv.result_data();
                    mulDiv.result_deq;
                end
            tagged Fpu .*: begin
                    let fpuResult = toFullResult(fpu.result_data);
                    resultWB.data = fpuResult.data;
                    resultWB.fflags = fpuResult.fflags;
                    fpu.result_deq;
                end
            tagged Mem .memInst:
                begin
                    if (getsResponse(memInst.op)) begin
                        resultWB.data = memResp.first;
                        memResp.deq;
                    end
                end
        endcase

        // Check for misaligned PCs
        if (!isValid(exceptionWB) && ((truncate(nextPc) & 2'b11) != 0)) begin
            exceptionWB = tagged Valid InstAddrMisaligned;
        end

        // TODO: add comment
        Bool extensionDirty = False;
        Bool fpuDirty = (dInst.dst == tagged Valid Fpu);
        let {maybeTrap, maybeData, maybeNextPc} <- csrf.wr(
                // performing system instructions
                dInst.execFunc matches tagged System .sysInst ? tagged Valid sysInst : tagged Invalid,
                getInstFields(inst).csr,
                resultWB.data,  // either rf[rs1] or zimm, computed in basicExec
                // handling exceptions
                exceptionWB,    // exception cause
                pc,             // for writing to mepc/sepc
                dInst.execFunc matches tagged Br .* ? True : False, // check inst allignment if Br Func
                resultWB.vaddr, // either data address or next PC, used to detect misaligned instruction addresses
                // indirect writes
                resultWB.fflags,
                fpuDirty,
                extensionDirty);

        // send verification packet
        verificationPackets.enq( VerificationPacket {
                skippedPackets: 0,
                pc: pc,
                nextPc: fromMaybe(resultWB.controlFlow.nextPc, maybeNextPc),
                data: fromMaybe(resultWB.data, maybeData),
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
            // redirect.enq( Redirect {
            //         pc: replayPc,
            //         epoch: ?,
            //         frontEndCsrs: FrontEndCsrs { vmI: csrf.vmI, state: csrf.csrState } } );

            pc <= replayPc;
            state <= Trap2;
        end else begin
            // This instruction retired
            if (dInst.dst matches tagged Valid .dstRegType) begin
                // Use data from CSR if available
                rf.wr(dstRegType, getInstFields(inst).rd, fromMaybe(resultWB.data, maybeData));
            end
            // always redirect
            redirect.enq( Redirect {
                    pc: nextPc,
                    epoch: ?,
                    frontEndCsrs: FrontEndCsrs { vmI: csrf.vmI, state: csrf.csrState } } );
            state <= Wait;
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
                result.vaddr, // vaddr
                0,
                False,
                False);

        // send verification packet
        verificationPackets.enq( VerificationPacket {
                skippedPackets: 0,
                pc: pc,
                nextPc: fromMaybe(?, maybeNextPc),
                data: fromMaybe(result.data, maybeData),
                instruction: inst,
                dst: {pack(dInst.dst), getInstFields(inst).rd},
                trap: isValid(maybeTrap),
                trapType: (case (fromMaybe(unpack(0), maybeTrap)) matches
                        tagged Exception .x: (zeroExtend(pack(x)));
                        tagged Interrupt .x: (zeroExtend(pack(x)) | 8'h80);
                    endcase) });

        // redirection will happpen in trap2
        // by construction maybeNextPc is always valid
        pc <= fromMaybe(?, maybeNextPc);
        state <= Trap2;
    endrule

    // There is a second trap state to ensure that the frontEndCsrs reflect the updated state of the processor
    rule doTrap2(state == Trap2);
        redirect.enq( Redirect {
            pc: pc,
            epoch: ?,
            frontEndCsrs: FrontEndCsrs { vmI: csrf.vmI, state: csrf.csrState }
        } );

        state <= Wait;
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

    method Action instFromFrontEnd(FrontEndToBackEnd#(void) x) if (state == Wait);
        if (verbose) $fdisplay(fout, "[backend] receiving instruction for pc: 0x%08x - intruction: 0x%08x - dInst: ", x.pc, x.inst, fshow(x.dInst));
        pc <= x.pc;
        inst <= x.inst;
        dInst <= x.dInst;
        exception <= x.cause;
        state <= isValid(x.cause) ? Trap : RegRead;
    endmethod
    method ActionValue#(Redirect#(void)) getRedirect;
        if (verbose) $fdisplay(fout, "[backend] sending redirecting to 0x%08x", redirect.first.pc);
        redirect.deq;
        return redirect.first;
    endmethod
    method ActionValue#(TrainingData) getTrain if (False);
        return ?;
    endmethod

    interface Client dvat = toGPClient(mmuReq, mmuResp);
    interface Client dmem = toGPClient(memReq, memResp);
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
