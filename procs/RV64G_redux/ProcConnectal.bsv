`include "ProcConfig.bsv"
// `include "PerfMonitor.defines"
import PerfMonitor::*;
import PerfMonitorConnectal::*;

// ProcConnectal.bsv
// This is a wrapper to translate the generic Proc interface to an interface
// that is accepted by connectal.

// This assumes a Proc.bsv file that contains the mkProc definition
import BuildVector::*;
import Clocks::*;
import Connectable::*;
import Proc::*;
import Vector::*;
import VerificationPacket::*;
import MemTypes::*;
import SharedMemoryBridge::*;

// ProcControlControl
interface ProcControlRequest;
    method Action reset;
    method Action start(Bit#(64) startPc, Bit#(64) verificationPacketsToIgnore, Bool sendSynchronizationPackets);
    method Action stop;
    method Action configure(Bit#(64) miobase);
    method Action initSharedMem(Bit#(32) refPointer, Bit#(64) memSize);
endinterface
interface ProcControlIndication;
    method Action resetDone;
endinterface
// HostInterface
interface HostInterfaceRequest;
    method Action fromHost(Bit#(64) v);
endinterface
interface HostInterfaceIndication;
    method Action toHost(Bit#(64) v);
endinterface
// Verification
interface VerificationIndication;
    method Action getVerificationPacket(VerificationPacket packet);
endinterface
// PerfMonitor interfaces defined in PerfMonitor package

// This is the interface of all the requests, the indications are passed in as
// parameters to the mkProcConnectal module.
interface ProcConnectal;
    interface ProcControlRequest procControlRequest;
    interface HostInterfaceRequest hostInterfaceRequest;
    interface PerfMonitorRequest perfMonitorRequest;
    interface Vector#(1, MemReadClient#(64)) dmaReadClient;
    interface Vector#(1, MemWriteClient#(64)) dmaWriteClient;
endinterface

module [Module] mkProcConnectal#(ProcControlIndication procControlIndication,
                                 HostInterfaceIndication hostInterfaceIndication,
                                 VerificationIndication verificationIndication,
                                 PerfMonitorIndication perfMonitorIndication)
                                (ProcConnectal);
    let clock <- exposeCurrentClock;
    let reset <- exposeCurrentReset;
    let procReset <- mkReset(10, True, clock);
    Reg#(Bool) resetSent <- mkReg(False);

    Tuple2#(PerfMonitor,Proc) procWithPerf <- mkProcV(reset_by procReset.new_rst);
    PerfMonitor perfMonitor = tpl_1(procWithPerf);
    Proc proc = tpl_2(procWithPerf);

    // bridge between axi and connectal's shared memory
    SharedMemoryBridge sharedMemoryBridge <- mkSharedMemoryBridge;
    let memToSharedMem <- mkConnection(proc.mainMemory, sharedMemoryBridge.to_proc);

    // rules for connecting indications
    rule finishReset(resetSent && (sharedMemoryBridge.numberFlyingOperations == 0));
        resetSent <= False;
        procControlIndication.resetDone;
    endrule
    rule connectHostInterfaceIndication;
        let msg <- proc.toHost;
        hostInterfaceIndication.toHost(msg);
    endrule
    rule connectVerificationIndication;
        let msg <- proc.getVerificationPacket;
        verificationIndication.getVerificationPacket(msg);
    endrule
    rule connectPerfMonitorIndication;
        let msg <- perfMonitor.resp;
        perfMonitorIndication.resp(msg);
    endrule

    interface ProcControlRequest procControlRequest;
        method Action reset() if (!resetSent);
            // resets the processor
            procReset.assertReset();
            // flushes the pending memory requests
            sharedMemoryBridge.flushRespReqMem;
            resetSent <= True;
        endmethod
        method Action start(Bit#(64) startPc, Bit#(64) verificationPacketsToIgnore, Bool sendSynchronizationPackets);
            proc.start(startPc, verificationPacketsToIgnore, sendSynchronizationPackets);
        endmethod
        method Action stop();
            proc.stop;
        endmethod
        method Action configure(Bit#(64) miobase);
            proc.configure(miobase);
        endmethod
        method Action initSharedMem(Bit#(32) refPointer, Bit#(64) memSize);
            sharedMemoryBridge.initSharedMem(refPointer, memSize);
        endmethod
    endinterface
    interface HostInterfaceRequest hostInterfaceRequest;
        method Action fromHost(Bit#(64) v);
            proc.fromHost(v);
        endmethod
    endinterface
    interface PerfMonitorRequest perfMonitorRequest;
        method Action reset;
            perfMonitor.reset;
        endmethod
        method Action setEnable(Bool en);
            perfMonitor.setEnable(en);
        endmethod
        method Action req(Bit#(32) index);
            perfMonitor.req(index);
        endmethod
    endinterface

    interface MemReadClient dmaReadClient = vec(sharedMemoryBridge.to_host_read);
    interface MemWriteClient dmaWriteClient = vec(sharedMemoryBridge.to_host_write);
endmodule
