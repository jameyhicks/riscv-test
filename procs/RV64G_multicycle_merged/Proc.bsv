`include "ProcConfig.bsv"

import Clocks::*;
import DefaultValue::*;
import ClientServer::*;
import Connectable::*;
import GetPut::*;
import RVTypes::*;
import Vector::*;
import VerificationPacket::*;
import VerificationPacketFilter::*;

import Abstraction::*;
import Core::*;
import MemorySystem::*;

interface Proc;
    // Processor Control
    method Action start(Bit#(64) startPc, Bit#(64) verificationPacketsToIgnore, Bool sendSynchronizationPackets);
    method Action stop();
    method Action configure(Bit#(64) miobase);

    // Verification
    method ActionValue#(VerificationPacket) getVerificationPacket;

    // HTIF
    method Action fromHost(Bit#(64) v);
    method ActionValue#(Bit#(64)) toHost;

    // Main Memory Connection
    interface MainMemoryClient#(MemoryClientType) mainMemory;
endinterface

// (* synthesize *)
// module `mkPerfModule("Proc", mkProc, Proc);

(* synthesize *)
module mkProc(Proc);
    Core core <- mkMulticycleCore;
    SingleCoreMemorySystem memorySystem <- mkBasicMemorySystem;

    // +----------------+ +---------------+
    // |      Core      | | verification  |
    // |                |-| packet filter |
    // +----------------+ +---------------+
    //   || ||    || |||
    // +----------------+
    // | memory system  |
    // +----------------+

    let core_to_mem <- mkConnection(core, memorySystem.core[0]);

    VerificationPacketFilter verificationPacketFilter <- mkVerificationPacketFilter(core.getVerificationPacket);

    // Processor Control
    method Action start(Bit#(64) startPc, Bit#(64) verificationPacketsToIgnore, Bool sendSynchronizationPackets);
        core.start(startPc);
        verificationPacketFilter.init(verificationPacketsToIgnore, sendSynchronizationPackets);
    endmethod
    method Action stop();
        core.stop;
    endmethod
    method Action configure(Data miobase);
        core.configure(miobase);
    endmethod

    // Verification
    method ActionValue#(VerificationPacket) getVerificationPacket;
        let verificationPacket <- verificationPacketFilter.getPacket;
        return verificationPacket;
    endmethod

    // HTIF
    method Action fromHost(Bit#(64) v);
        // $fdisplay(stderr, "[PROC] fromHost: 0x%08x", v);
        core.htif.response.put(v);
    endmethod
    method ActionValue#(Bit#(64)) toHost;
        let msg <- core.htif.request.get;
        // $fdisplay(stderr, "[PROC] toHost: 0x%08x", msg);
        return msg;
    endmethod

    // Main Memory Connection
    interface mainMemory = memorySystem.mainMemory;
endmodule

