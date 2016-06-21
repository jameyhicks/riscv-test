package SFIFO;

import Ehr::*;
import List::*;

// If you are running into a problem because MAX_SFIFO_SIZE is too small, you
// can increase it here, or you can define it
`ifndef MAX_SFIFO_SIZE
`define MAX_SFIFO_SIZE 16
`endif

interface SFIFO#(type dataType, type searchType);
    method Action enq(dataType x);
    method Action deq;
    method dataType first;
    method Action clear;
    method Bool search(searchType x);
endinterface

// search < {enq , deq} < clear
// first < deq
module mkSFIFO#(Integer size, function Bool isMatch(searchType s, dataType d))(SFIFO#(dataType, searchType)) provisos (Bits#(dataType, dataSize));
    // use valid bits to make search logic smaller
    List#(Reg#(Maybe#(dataType))) data <- List::replicateM(size, mkRegU);
    Reg#(Bit#(TLog#(`MAX_SFIFO_SIZE))) enqP <- mkReg(0);
    Reg#(Bit#(TLog#(`MAX_SFIFO_SIZE))) deqP <- mkReg(0);
    Reg#(Bool) full <- mkReg(False);
    Reg#(Bool) empty <- mkReg(True);
    // EHRs to avoid conflicts between enq and deq
    Ehr#(3, Bool) deqReq <- mkEhr(False);
    Ehr#(3, Maybe#(dataType)) enqReq <- mkEhr(tagged Invalid);

    // Canonicalize rule to handle enq and deq.
    // These attributes are statically checked by the compiler.
    (* fire_when_enabled *)         // WILL_FIRE == CAN_FIRE
    (* no_implicit_conditions *)    // CAN_FIRE == guard (True)
    rule canonicalize;
        Bool enqueued = False;
        let nextEnqP = enqP;
        Bool dequeued = False;
        let nextDeqP = deqP;

        // enqueue logic
        if (enqReq[2] matches tagged Valid .enqVal) begin
            enqueued = True;
            nextEnqP = (enqP == fromInteger(size - 1)) ? 0 : enqP + 1;
            // perform state updates
            data[enqP] <= tagged Valid enqVal;
            enqP <= nextEnqP;
        end

        // dequeue logic
        if (deqReq[2] == True) begin
            dequeued = True;
            nextDeqP = (deqP == fromInteger(size - 1)) ? 0 : deqP + 1;
            // perform state updates
            deqP <= nextDeqP;
            data[deqP] <= tagged Invalid;
        end

        // update empty and full if an element was enqueued or dequeued
        if (enqueued || dequeued) begin
            full <= (nextEnqP == nextDeqP) ? enqueued : False;
            empty <= (nextEnqP == nextDeqP) ? dequeued : False;
            enqP <= nextEnqP;
            deqP <= nextDeqP;
        end

        // clear request EHRs
        enqReq[2] <= tagged Invalid;
        deqReq[2] <= False;
    endrule

    method Action enq(dataType x) if (!full && !isValid(enqReq[0]));
        enqReq[0] <= tagged Valid x;
    endmethod
    method Action deq if (!empty && !deqReq[0]);
        deqReq[0] <= True;
    endmethod
    method dataType first if (!empty && !deqReq[0]);
        return fromMaybe(?, data[deqP]);
    endmethod
    method Action clear;
        for (Integer i = 0 ; i < size ; i = i+1) begin
            data[i] <= tagged Invalid;
        end
        enqP <= 0;
        deqP <= 0;
        full <= False;
        empty <= True;
        // clear any pending enq or deq
        enqReq[1] <= tagged Invalid;
        deqReq[1] <= False;
    endmethod

    // different search implementations
    // search < {enq, deq}
    method Bool search(searchType x) if (!isValid(enqReq[0]) && !deqReq[0]);
        // helper function for isMatch when dataType has valid bits
        function Bool maybeIsMatch(searchType s, Maybe#(dataType) md);
            return md matches tagged Valid. d ? isMatch(s, d) : False;
        endfunction
        return any(id, map(compose(maybeIsMatch(x), readReg), data));
    endmethod

    // // Alternate search implementation with the scheulde:
    // //   deq < search < enq
    // method Bool search(searchType x) if (!isValid(enqReq[0]));
    //     // compute dataPostDeq by considering deqReq[1]
    //     List#(Maybe#(dataType)) dataPostDeq = map(readReg, data);
    //     if (deqReq[1]) begin
    //         dataPostDeq[deqP] = tagged Invalid;
    //     end
    //     // helper function for isMatch when dataType has valid bits
    //     function Bool maybeIsMatch(searchType s, Maybe#(dataType) md);
    //         return md matches tagged Valid. d ? isMatch(s, d) : False;
    //     endfunction
    //     return any(map(maybeIsMatch(x), dataPostDeq));
    // endmethod
endmodule

endpackage
