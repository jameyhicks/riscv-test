`include "ProcConfig.bsv"
// `include "PerfMonitor.defines"
import PerfMonitor::*;
import ModuleContext::*;

import Clocks::*;
import DefaultValue::*;
import ClientServer::*;
import Connectable::*;
import GetPut::*;
//import MemTypes::*; // XXX: Remove this
import RVTypes::*;
import Vector::*;
import VerificationPacket::*;
import VerificationPacketFilter::*;

import Abstraction::*;
import FrontEnd::*;
import BackEnd::*;
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
module [Module] mkProcV(Tuple2#(PerfMonitor, Proc));
    (* hide *)
    let _m <- toSynthBoundary("Proc", mkProc0);
    return _m;
endmodule
module [m] mkProc(Proc) provisos (HasPerfCounters#(m));
    (* hide *)
    let _m <- fromSynthBoundary("Proc", mkProcV);
    return _m;
endmodule
module [m] mkProc0(Proc) provisos (HasPerfCounters#(m));
    FrontEnd#(void) frontend <- mkMulticycleFrontEnd;
    BackEnd#(void) backend <- mkMulticycleBackEnd;
    SingleCoreMemorySystem memorySystem <- mkBasicMemorySystem;

    // +-------+ +------+ +---------------+
    // | front |-| back | | verification  |
    // |  end  |=| end  |-| packet filter |
    // +-------+ +------+ +---------------+
    //   || ||    || |||
    // +----------------+
    // | memory system  |
    // +----------------+

    let front_to_back <- mkConnection(frontend, backend);
    let fron_to_mem <- mkConnection(frontend, memorySystem.core[0]);
    let back_to_mem <- mkConnection(backend, memorySystem.core[0]);

    VerificationPacketFilter verificationPacketFilter <- mkVerificationPacketFilter(backend.getVerificationPacket);

    // Processor Control
    method Action start(Bit#(64) startPc, Bit#(64) verificationPacketsToIgnore, Bool sendSynchronizationPackets);
        frontend.start(startPc);
        verificationPacketFilter.init(verificationPacketsToIgnore, sendSynchronizationPackets);
    endmethod
    method Action stop();
        frontend.stop;
    endmethod
    method Action configure(Data miobase);
        backend.configure(miobase);
    endmethod

    // Verification
    method ActionValue#(VerificationPacket) getVerificationPacket;
        let verificationPacket <- verificationPacketFilter.getPacket;
        return verificationPacket;
    endmethod

    // HTIF
    method Action fromHost(Bit#(64) v);
        // $fdisplay(stderr, "[PROC] fromHost: 0x%08x", v);
        backend.htif.response.put(v);
    endmethod
    method ActionValue#(Bit#(64)) toHost;
        let msg <- backend.htif.request.get;
        // $fdisplay(stderr, "[PROC] toHost: 0x%08x", msg);
        return msg;
    endmethod

    // Main Memory Connection
    interface mainMemory = memorySystem.mainMemory;
endmodule

