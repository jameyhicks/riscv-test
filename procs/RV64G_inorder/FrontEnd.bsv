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

typedef struct {
    Addr pc;
    Addr ppc;
    Bool epoch;
} Stage1 deriving (Bits, Eq, FShow);

typedef struct {
    Addr                   pc;
    Addr                   ppc;
    Maybe#(ExceptionCause) exception;
    Bool                   epoch;
} Stage2 deriving (Bits, Eq, FShow);

typedef Bool EpochType;

(* synthesize *)
module mkInorderFrontEnd(FrontEnd#(EpochType)); // TODO: Change Epoch Type
    Bool verbose = False;
    File fout = stdout;

    Reg#(Bool) running <- mkReg(False);


    // Reg#(Addr) pc <- mkReg(0);
    // Reg#(Maybe#(ExceptionCause)) exception <- mkReg(tagged Invalid);
    // Reg#(Instruction) inst <- mkReg(0);
    // Reg#(RVDecodedInst) dInst <- mkReg(unpack(0));
    // Reg#(FrontEndCsrs) csrState <- mkReg(defaultValue);
    // Reg#(FEState) state <- mkReg(Wait);
    Reg#(Addr) pcReg <- mkReg(0);
    Reg#(EpochType) epochReg <- mkReg(unpack(0));

    FIFO#(Stage1) stage1Fifo <- mkFIFO;
    FIFO#(Stage2) stage2Fifo <- mkFIFO;


    FIFO#(RVIMMUReq)    mmuReq <- mkFIFO;
    FIFO#(RVIMMUResp)   mmuResp <- mkFIFO;

    FIFO#(RVIMemReq)    memReq <- mkFIFO;
    FIFO#(RVIMemResp)   memResp <- mkFIFO;

    FIFO#(FrontEndToBackEnd#(EpochType)) toBackEnd <- mkFIFO;


    rule doInstMMU(running);
        // predict next pc
        let nextPc = pcReg + 4;

        // request address translation from MMU
        mmuReq.enq(pcReg);
        // update pcReg with new prediction
        pcReg <= nextPc;
        // store information in stage1Fifo
        stage1Fifo.enq( Stage1 {
                pc:    pcReg,
                ppc:   nextPc,
                epoch: epochReg
            } );
    endrule

    rule doInstFetch(running);
        // get response from MMU
        let translationResp = mmuResp.first;
        mmuResp.deq;
        // get information about current instruction
        let instState = stage1Fifo.first;
        stage1Fifo.deq;
        
        if (instState.epoch == epochReg) begin
            // only continue executing this instruction if the epochs match
            let phyPc = translationResp.addr;
            let translationException = translationResp.exception;

            if (!isValid(translationException)) begin
                // if there was no translation exception, load the instruction
                // from the instruction cache
                memReq.enq(phyPc);
            end

            // store information in stage2Fifo
            stage2Fifo.enq( Stage2 {
                    pc:        instState.pc,
                    ppc:       instState.ppc,
                    exception: translationException,
                    epoch:     instState.epoch
                } );
        end
    endrule

    rule doDecode;
        // get information about current instruction
        let instState = stage2Fifo.first;
        stage2Fifo.deq;

        Maybe#(ExceptionCause) exception = instState.exception;
        Instruction inst = unpack(0);
        RVDecodedInst dInst = unpack(0);

        if (!isValid(exception)) begin
            // get response from Memory
            inst = memResp.first;
            memResp.deq;
            // decode instruction
            case (decodeInst(inst)) matches
                tagged Valid .validDInst:
                    // valid instruction; update dInst
                    dInst = validDInst;
                tagged Invalid:
                    // invalid instruction; update exception
                    exception = tagged Valid IllegalInst;
            endcase
        end

        if (instState.epoch == epochReg) begin
            // only send to backend if epochs match
            toBackEnd.enq( FrontEndToBackEnd {
                    pc:           instState.pc,
                    ppc:          tagged Valid instState.ppc,
                    inst:         inst,
                    dInst:        dInst,
                    cause:        exception,
                    backendEpoch: instState.epoch
                } );
        end
    endrule

    method ActionValue#(FrontEndToBackEnd#(EpochType)) instToBackEnd;
        if (verbose) $fdisplay(fout, "[frontend] sending instruction for pc: 0x%08x - intruction: 0x%08x - dInst: ", toBackEnd.first.pc, toBackEnd.first.inst, fshow(toBackEnd.first.dInst));
        toBackEnd.deq;
        return toBackEnd.first;
    endmethod
    method Action redirect(Redirect#(EpochType) r);
        pcReg <= r.pc;
        epochReg <= r.epoch;
        if (verbose) $fdisplay(fout, "[frontend] receiving redirecting to 0x%08x", r.pc);
    endmethod
    method Action train(TrainingData d);
        noAction;
    endmethod

    interface Client ivat = toGPClient(mmuReq, mmuResp);
    interface Client ifetch = toGPClient(memReq, memResp);

    method Action start(Addr startPc);
        running <= True;
        pcReg <= startPc;
        if (verbose) $fdisplay(fout, "[frontend] starting from pc = 0x%08x", startPc);
    endmethod
    method Action stop;
        running <= False;
    endmethod
endmodule
