import ClientServer::*;
import DefaultValue::*;
import FIFO::*;
import FIFOF::*;
import Vector::*;

import Abstraction::*;
import RVRFile::*;
import RVCsrFile::*;
import RVExec::*;
import RVFpu::*;
import RVMulDiv::*;
import RVTypes::*;
import Scoreboard::*;
import VerificationPacket::*;

import RVAlu::*;
import RVControl::*;
import RVDecode::*;
import RVMemory::*;

typedef Bool EpochType;

typedef struct {
    Addr                   pc;
    Addr                   ppc;
    Instruction            inst;
    RVDecodedInst          dInst;
    Maybe#(ExceptionCause) exception;
    EpochType              epoch;
    // data read from register file
    Data                   rVal1;
    Data                   rVal2;
    Data                   rVal3;
} RegReadToExecute deriving (Bits, Eq, FShow);

typedef struct {
    Addr                   pc;
    Addr                   ppc;
    Instruction            inst;
    RVDecodedInst          dInst;
    Maybe#(ExceptionCause) exception;
    EpochType              epoch;
    // results
    Data                   data;
    Addr                   addr;
    Addr                   nextPc;
} ExecuteToMem deriving (Bits, Eq, FShow);

typedef struct {
    Addr                   pc;
    Addr                   ppc;
    Instruction            inst;
    RVDecodedInst          dInst;
    Maybe#(ExceptionCause) exception;
    EpochType              epoch;
    // results
    Data                   data;
    Addr                   addr;
    Addr                   nextPc;
    // to mark that this instruction should be killed
    Bool                   poisoned;
} MemToWriteBack deriving (Bits, Eq, FShow);

// typedef union tagged {
//     void DifferentDst;
//     void NotReady;
//     Data Ready;
// } BypassingValue deriving (Bits, Eq, FShow);
// interface BypassingFIFO#(type t);
//     method BypassingValue getBypassingValue( ??? /* TODO */ ):
//     // TODO: Finish this interface
// endinterface
// module mkBypassingFIFO(BypassingFIFO#(t));
//     // TODO: Implement me!
// endmodule

(* synthesize *)
module mkInorderBackEnd(BackEnd#(EpochType));
    let verbose = False;
    File fout = stdout;

    Reg#(Bool) htifStall <- mkReg(False);

    Reg#(Bool) epochReg <- mkReg(unpack(0));

    ArchRFile rf <- mkArchRFile;
    RVCsrFile csrf <- mkRVCsrFile;
    MulDivExec mulDiv <- mkBoothRoughMulDivExec;
    FpuExec fpu <- mkFpuExecPipeline;
    Scoreboard#(4) scoreboard <- mkScoreboard;
    Reg#(Bool) systemInstInFlight <- mkReg(False);

    FIFO#(RegReadToExecute) regReadToExecute <- mkFIFO;
    FIFO#(ExecuteToMem) executeToMem <- mkFIFO;
    FIFOF#(MemToWriteBack) memToWriteBack <- mkFIFOF;

    FIFO#(FrontEndToBackEnd#(EpochType)) fromFrontEnd <- mkFIFO;
    FIFO#(Redirect#(EpochType)) redirect <- mkFIFO;

    FIFO#(RVDMMUReq)    mmuReq <- mkFIFO;
    FIFO#(RVDMMUResp)   mmuResp <- mkFIFO;

    FIFO#(RVDMemReq)    memReq <- mkFIFO;
    FIFO#(RVDMemResp)   memResp <- mkFIFO;

    FIFO#(Data)         toHost <- mkFIFO;
    FIFO#(Data)         fromHost <- mkFIFO;

    FIFO#(VerificationPacket) verificationPackets <- mkFIFO;

    rule doRegRead(!htifStall);
        let instState = fromFrontEnd.first;

        let inst = instState.inst;
        let dInst = instState.dInst;
        let exception = instState.cause; // TODO: make exception/cause/trap naming consistent

        let fullSrc1 = toFullRegIndex(dInst.rs1, getInstFields(inst).rs1);
        let fullSrc2 = toFullRegIndex(dInst.rs2, getInstFields(inst).rs2);
        let fullSrc3 = toFullRegIndex(dInst.rs3, getInstFields(inst).rs3);
        let fullDst = toFullRegIndex(dInst.dst, getInstFields(inst).rd);

        // Here we will read some CSR states such as interrupts and rm

        // Not all FPU instructions use rm, but instructions that don't use it
        // have it set to a valid value, so we don't have to deal with those
        // instructions specially when determining if rm is valid.
        let instRM = getInstFields(inst).rm;
        let csrRM = csrf.csrState.frm;
        let rm = (instRM == RDyn) ? unpack(csrRM) : instRM;
        let validRM = (case (rm)
                RNE:     True;
                RTZ:     True;
                RDN:     True;
                RUP:     True;
                RMM:     True;
                default: False;
            endcase);
        if (!isValid(exception) && !validRM) begin
            exception = tagged Valid IllegalInst;
        end

        Bool isException = isValid(exception);
        Bool isSystemInstruction = dInst.execFunc matches tagged System .* ? True : False;
        Bool rawHazard = scoreboard.search1(fullSrc1)
                         || scoreboard.search2(fullSrc2)
                         || scoreboard.search2(fullSrc3);
        Bool hazard = rawHazard || systemInstInFlight || (isSystemInstruction && scoreboard.notEmpty);
        if (!hazard || isException) begin
            // only read registers if they are ready
            let rVal1 = rf.rd1(fullSrc1);
            let rVal2 = rf.rd2(fullSrc2);
            let rVal3 = rf.rd3(fullSrc3);

            // add bookkeeping
            scoreboard.insert(fullDst);
            // forces one-at-a-time execution in the presence of system instructions
            if (isSystemInstruction) begin
                systemInstInFlight <= True;
            end

            // dequeue from previous stage
            fromFrontEnd.deq;

            // enqueue into next stage
            regReadToExecute.enq( RegReadToExecute {
                    pc:         instState.pc,
                    ppc:        fromMaybe('1, instState.ppc),
                    inst:       instState.inst,
                    dInst:      dInst,
                    exception:  exception,
                    epoch:      instState.backendEpoch,
                    rVal1:      rVal1,
                    rVal2:      rVal2,
                    rVal3:      rVal3
                });
        end
    endrule

    rule doExecute;
        let instState = regReadToExecute.first;
        regReadToExecute.deq;

        // extract some common values from instState
        let rVal1 = instState.rVal1;
        let rVal2 = instState.rVal2;
        let rVal3 = instState.rVal3;
        let dInst = instState.dInst;
        let inst = instState.inst;
        let pc = instState.pc;
        let ppc = instState.ppc;
        let exception = instState.exception;

        Data data = 0;
        Addr addr = 0;
        Addr nextPc = pc + 4;

        Maybe#(Data) imm = getImmediate(dInst.imm, dInst.inst);

        if (!isValid(exception)) begin
            case (dInst.execFunc) matches
                tagged Alu .aluInst:
                    begin
                        data = execAluInst(aluInst, rVal1, rVal2, imm, pc);
                    end
                tagged Br .brFunc:
                    begin
                        // data for jal
                        data = pc + 4;
                        nextPc = execControl(brFunc, rVal1, rVal2, imm, pc);
                    end
                tagged Mem .memInst:
                    begin
                        // data for store and AMO
                        data = rVal2;
                        addr = addrCalc(rVal1, imm);
                        mmuReq.enq(RVDMMUReq {addr: addr, size: memInst.size, op: (memInst.op matches tagged Mem .memOp ? memOp : St)});
                    end
                tagged MulDiv .mulDivInst: mulDiv.exec(mulDivInst, rVal1, rVal2);
                tagged Fence .fenceInst:  noAction; // TODO: do some fence stuff
                // TODO: Handle dynamic rounding mode
                tagged Fpu .fpuInst:    fpu.exec(fpuInst, getInstFields(inst).rm, rVal1, rVal2, rVal3);
                tagged System .systemInst:
                    begin
                        // data for CSR instructions
                        data = fromMaybe(rVal1, imm);
                    end
            endcase
        end

        executeToMem.enq( ExecuteToMem {
                pc:        instState.pc,
                ppc:       instState.ppc,
                inst:      instState.inst,
                dInst:     instState.dInst,
                exception: exception,
                epoch:     instState.epoch,
                data:      data,
                addr:      addr,
                nextPc:    nextPc
            });

    endrule

    // only allow this to fire if this instruction is last instruction in pipeline.
    // This is necessary for stores due to the lack of a speculative store buffer.
    rule doMem(!memToWriteBack.notEmpty);
        let instState = executeToMem.first;
        executeToMem.deq;

        let data = instState.data;
        let epoch = instState.epoch;
        let dInst = instState.dInst;
        let exception = instState.exception;

        if (!isValid(exception)) begin
            case (dInst.execFunc) matches
                tagged Mem .memInst:
                    begin
                        // get response from translation
                        let pAddr = mmuResp.first.addr;
                        exception = mmuResp.first.exception;
                        mmuResp.deq;

                        if (!isValid(exception) && epoch == epochReg) begin
                            // if not an exception, use response to perform memory op
                            memReq.enq( RVDMemReq {
                                    op: memInst.op,
                                    byteEn: toByteEn(memInst.size),
                                    addr: pAddr,
                                    data: data,
                                    unsignedLd: isUnsigned(memInst.size)
                                } );
                        end
                    end
            endcase
        end

        memToWriteBack.enq( MemToWriteBack {
                pc:        instState.pc,
                ppc:       instState.ppc,
                inst:      instState.inst,
                dInst:     instState.dInst,
                exception: exception,
                epoch:     epoch,
                data:      data,
                addr:      instState.addr,
                nextPc:    instState.nextPc,
                poisoned:  (dInst.execFunc matches tagged Mem .* ? (epoch != epochReg) : False)
            } );
    endrule

    rule doWriteBack;
        let instState = memToWriteBack.first;
        memToWriteBack.deq;

        let pc = instState.pc;
        let ppc = instState.ppc;
        let dInst = instState.dInst;
        let inst = instState.inst;
        let data = instState.data;
        let addr = instState.addr;
        let nextPc = instState.nextPc;
        let exception = instState.exception;
        let epoch = instState.epoch;
        let fullDst = toFullRegIndex(dInst.dst, getInstFields(inst).rd);
        let poisoned = instState.poisoned;
        let fflags = 0;

        if (verbose) $fdisplay(fout, "[backend] finishing execution of pc = ", fshow(pc));

        if (!poisoned) begin
            // get results from execution pipelines
            if (!isValid(exception)) begin
                case(dInst.execFunc) matches
                    tagged MulDiv .*: begin
                            data = mulDiv.result_data();
                            mulDiv.result_deq;
                        end
                    tagged Fpu .*: begin
                            data = fpu.result_data.data;
                            fflags = fpu.result_data.fflags;
                            fpu.result_deq;
                        end
                    tagged Mem .memInst:
                        begin
                            if (getsResponse(memInst.op)) begin
                                data = memResp.first;
                                memResp.deq;
                            end
                        end
                endcase
            end
        end

        if (!poisoned && (epoch == epochReg)) begin
            // doing CSRF stuff (system instructions, etc.)
            Bool extensionDirty = False;
            Bool fpuDirty = (dInst.dst == tagged Valid Fpu);
            let {maybeTrap, maybeData, maybeNextPc} <- csrf.wr(
                    // performing system instructions
                    dInst.execFunc matches tagged System .sysInst ? tagged Valid sysInst : tagged Invalid,
                    getInstFields(inst).csr,
                    data, // either rf[rs1] or zimm, computed in basicExec
                    // handling exceptions
                    exception, // exception cause
                    pc, // for writing to mepc/sepc
                    dInst.execFunc matches tagged Br .* ? True : False, // check inst allignment if Br Func
                    dInst.execFunc matches tagged Br .* ? nextPc : addr, // either data address or next PC, used to detect misaligned instruction addresses
                    // indirect writes
                    fflags,
                    fpuDirty,
                    extensionDirty);

            // redirect the front end
            if (maybeNextPc matches tagged Valid .replayPc) begin
                // This instruction didn't retire
                epochReg <= !epochReg;
                redirect.enq( Redirect {
                        pc: replayPc,
                        epoch: !epochReg,
                        // TODO: This is wrong, this should include state change
                        // from csrf.wr but it doesn't
                        frontEndCsrs: FrontEndCsrs { vmI: csrf.vmI, state: csrf.csrState } } );
            end else begin
                // This instruction retired
                // update the register file (no change if fullDst is tagged Invalid)
                rf.wr(fullDst, fromMaybe(data, maybeData));

                // redirect if ppc != nextPc
                if (ppc != nextPc) begin
                    epochReg <= !epochReg;
                    redirect.enq( Redirect {
                            pc: nextPc,
                            epoch: !epochReg,
                            frontEndCsrs: FrontEndCsrs { vmI: csrf.vmI, state: csrf.csrState } } );
                end else if (dInst.execFunc matches tagged Fence .*) begin
                    epochReg <= !epochReg;
                    redirect.enq( Redirect {
                            pc: nextPc,
                            epoch: !epochReg,
                            frontEndCsrs: FrontEndCsrs { vmI: csrf.vmI, state: csrf.csrState } } );
                end
            end

            // send verification packet
            verificationPackets.enq( VerificationPacket {
                    skippedPackets: 0,
                    pc: pc,
                    nextPc: fromMaybe(nextPc, maybeNextPc),
                    data: fromMaybe(data, maybeData),
                    addr: addr,
                    instruction: inst,
                    dst: {pack(dInst.dst), getInstFields(inst).rd},
                    trap: isValid(maybeTrap),
                    trapType: (case (fromMaybe(unpack(0), maybeTrap)) matches
                            tagged Exception .x: (zeroExtend(pack(x)));
                            tagged Interrupt .x: (zeroExtend(pack(x)) | 8'h80);
                        endcase) });
        end

        // remove bookkeeping entries for this instruction (even if poisoned)
        scoreboard.remove;
        // XXX: by design, this is good enough, but this is not robust
        systemInstInFlight <= False;
    endrule

    //// rule doTrap;
    ////     // TODO: move this to WB
    ////     let {maybeTrap, maybeData, maybeNextPc} <- csrf.wr(
    ////             tagged Invalid,
    ////             getInstFields(inst).csr,
    ////             0, // data
    ////             exception, // exception cause
    ////             pc, // pc
    ////             False, 
    ////             addr, // vaddr
    ////             0,
    ////             False,
    ////             False);
    ////     // send verification packet
    ////     verificationPackets.enq( VerificationPacket {
    ////             skippedPackets: 0,
    ////             pc: pc,
    ////             nextPc: fromMaybe(?, maybeNextPc),
    ////             data: fromMaybe(data, maybeData),
    ////             instruction: inst,
    ////             dst: {pack(dInst.dst), getInstFields(inst).rd},
    ////             trap: isValid(maybeTrap),
    ////             trapType: (case (fromMaybe(unpack(0), maybeTrap)) matches
    ////                     tagged Exception .x: (zeroExtend(pack(x)));
    ////                     tagged Interrupt .x: (zeroExtend(pack(x)) | 8'h80);
    ////                 endcase) });
    ////     // redirection will happpen in trap2
    ////     // by construction maybeNextPc is always valid
    ////     nextPc <= fromMaybe(?, maybeNextPc);
    //// endrule

    //// // There is a second trap state to ensure that the frontEndCsrs reflect the updated state of the processor
    //// rule doTrap2;
    ////     redirect.enq( Redirect {
    ////         pc: nextPc,
    ////         epoch: ?,
    ////         frontEndCsrs: FrontEndCsrs { vmI: csrf.vmI, state: csrf.csrState }
    ////     } );
    //// endrule

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

    method Action instFromFrontEnd(FrontEndToBackEnd#(EpochType) x);
        if (verbose) $fdisplay(fout, "[backend] receiving instruction for pc: 0x%08x - intruction: 0x%08x - dInst: ", x.pc, x.inst, fshow(x.dInst));
        if (x.backendEpoch == epochReg) begin
            fromFrontEnd.enq(x);
        end
    endmethod
    method ActionValue#(Redirect#(EpochType)) getRedirect;
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
