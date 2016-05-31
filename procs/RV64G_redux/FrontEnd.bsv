// `include "PerfMonitor.defines"
import PerfMonitor::*;
import ModuleContext::*;

import ClientServer::*;
import DefaultValue::*;
import FIFO::*;

import Abstraction::*;
import RVExec::*;
import RVDecode::*;
import RVTypes::*;

typedef enum {
    Wait,
    IMMU,
    IF,
    Dec,
    Send
} FEState deriving (Bits, Eq, FShow);

// (* synthesize *)
// module `mkPerfModule("FrontEnd", mkMulticycleFrontEnd, FrontEnd#(void));
(* synthesize *)
module [Module] mkMulticycleFrontEndV(Tuple2#(PerfMonitor, FrontEnd#(void)));
    (* hide *)
    let _m <- toSynthBoundary("FrontEnd", mkMulticycleFrontEnd0);
    return _m;
endmodule
module [m] mkMulticycleFrontEnd(FrontEnd#(void)) provisos (HasPerfCounters#(m));
    (* hide *)
    let _m <- fromSynthBoundary("FrontEnd", mkMulticycleFrontEndV);
    return _m;
endmodule
module [m] mkMulticycleFrontEnd0(FrontEnd#(void)) provisos (HasPerfCounters#(m));
    Bool verbose = False;
    File fout = stdout;

    Reg#(Bool) running <- mkReg(False);

    Reg#(Addr) pc <- mkReg(0);
    Reg#(Maybe#(ExceptionCause)) exception <- mkReg(tagged Invalid);
    Reg#(Instruction) inst <- mkReg(0);
    Reg#(RVDecodedInst) dInst <- mkReg(unpack(0));
    Reg#(FrontEndCsrs) csrState <- mkReg(defaultValue);
    Reg#(FEState) state <- mkReg(Wait);

    FIFO#(RVIMMUReq)    mmuReq <- mkFIFO;
    FIFO#(RVIMMUResp)   mmuResp <- mkFIFO;

    FIFO#(RVIMemReq)    memReq <- mkFIFO;
    FIFO#(RVIMemResp)   memResp <- mkFIFO;

    FIFO#(FrontEndToBackEnd#(void)) toBackEnd <- mkFIFO;

    // Performance Counters
    PerfCounter fetchCounter <- mkPerfCounter("fetches");
    PerfCounter fetchFaultCounter <- mkPerfCounter("fetch-faults");
    PerfCounter cycleCounter <- mkPerfCounter("cycles");
    rule incrementCycleCounter;
        cycleCounter.increment(1);
    endrule

    rule doInstMMU(running && state == IMMU);
        // request address translation from MMU
        mmuReq.enq(pc);
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

        let phyPc = mmuResp.first.addr;
        let exMMU = mmuResp.first.exception;
        mmuResp.deq;

        if (!isValid(exMMU)) begin
            // no translation exception
            memReq.enq(phyPc);
            fetchCounter.increment(1);
            // go to decode stage
            state <= Dec;
        end else begin
            // translation exception (instruction access fault)
            exception <= exMMU;
            fetchFaultCounter.increment(1);
            // send instruction to backend
            state <= Send;
        end
    endrule

    rule doDecode(state == Dec);
        let fInst = memResp.first;
        memResp.deq;

        let decInst = decodeInst(fInst);

        if (decInst matches tagged Valid .validDInst) begin
            // Legal instruction
            dInst <= validDInst;
        end else begin
            // Illegal instruction
            exception <= tagged Valid IllegalInst;
        end

        inst <= fInst;
        state <= Send;
    endrule

    // XXX: TODO: Continue integrating the new decode function and types (am I done with this?)

    rule doSend(state == Send);
        toBackEnd.enq( FrontEndToBackEnd{
            pc: pc,
            ppc: tagged Invalid,
            inst: inst,
            dInst: dInst,
            cause: exception,
            backendEpoch: ?
        });
        state <= Wait;
    endrule

    method ActionValue#(FrontEndToBackEnd#(void)) instToBackEnd;
        if (verbose) $fdisplay(fout, "[frontend] sending instruction for pc: 0x%08x - intruction: 0x%08x - dInst: ", toBackEnd.first.pc, toBackEnd.first.inst, fshow(toBackEnd.first.dInst));
        toBackEnd.deq;
        return toBackEnd.first;
    endmethod
    method Action redirect(Redirect#(void) r) if (state == Wait);
        pc <= r.pc;
        // ignore epoch because it's type is void
        csrState <= r.frontEndCsrs;
        state <= IMMU;
        if (verbose) $fdisplay(fout, "[frontend] receiving redirecting to 0x%08x", r.pc);
    endmethod
    method Action train(TrainingData d);
        noAction;
    endmethod

    interface Client ivat = toGPClient(mmuReq, mmuResp);
    interface Client ifetch = toGPClient(memReq, memResp);

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
endmodule
