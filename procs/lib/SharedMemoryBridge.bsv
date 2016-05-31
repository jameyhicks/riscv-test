import Abstraction::*;
import RVTypes::*;
import CompareProvisos::*;
import ClientServer::*;
import ConnectalConfig::*;
import GetPut::*;
import RegFile::*;
import Vector::*;
import FIFO::*;
import FIFOF::*;
import HostInterface::*;
import MemTypes::*;
import PrintTrace::*;
// import CacheUtils::*; // for PendMemRespCnt
// TODO: FIXME
typedef Bit#(4) PendMemRespCnt;

import BRAMFIFO::*;
import DefaultValue::*;

interface SharedMemoryBridge;
    // Processor Interface
    interface MainMemoryServer#(MemoryClientType) to_proc;

    // Shared Memory Interfaces
    interface MemReadClient#(DataBusWidth)  to_host_read;
    interface MemWriteClient#(DataBusWidth) to_host_write;

    // Initialize the shared memory with the ref pointer and size.
    // If an address is out of range, it will handled (somehow)
    method Action initSharedMem(Bit#(32) refPointer, Addr memSize);

    // Methods for clearing pending requests before reset
    // TODO: actually implement this
    method Action flushRespReqMem;
    method PendMemRespCnt numberFlyingOperations;
endinterface

// This bridge assumes the shared memory responds to load requests in order
(* synthesize *)
module mkSharedMemoryBridge(SharedMemoryBridge) provisos (EQ#(DataSz, DataBusWidth));
    // TODO: re-implement WORKAROUND_ISSUE_27
    `ifdef WORKAROUND_ISSUE_27
    error("WORKAROUND_ISSUE_27 is not implemented for mkSharedMemoryBridge");
    `endif
    // TODO: re-implement SERIALIZE_MEM_REQS
    `ifdef SERIALIZE_MEM_REQS
    error("SERIALIZE_MEM_REQS is not implemented for mkSharedMemoryBridge");
    `endif

    Bool verbose = False;
    File tracefile = verbose ? stdout : tagged InvalidFile;

    FIFOF#(MemoryClientType)        pendingReads  <- fprintTraceM(tracefile, "SharedMemoryBridge::pendingReads",  mkSizedFIFOF(16));
    FIFO#(MemRequest)               readReqFifo   <- fprintTraceM(tracefile, "SharedMemoryBridge::readReqFifo",   mkFIFO);
    FIFO#(MemRequest)               writeReqFifo  <- fprintTraceM(tracefile, "SharedMemoryBridge::writeReqFifo",  mkFIFO);
    FIFO#(MemData#(DataBusWidth))   writeDataFifo <- fprintTraceM(tracefile, "SharedMemoryBridge::writeDataFifo", mkSizedBRAMFIFO(1024)); // XXX: Not sure where this size came from
    FIFO#(MemData#(DataBusWidth))   readDataFifo  <- fprintTraceM(tracefile, "SharedMemoryBridge::readDataFifo",  mkFIFO);

    Reg#(SGLId)                     refPointerReg <- mkReg(0);
    Reg#(Addr)                      memSizeReg    <- mkReg(64 << 20); // 64 MB by default
    Reg#(Bool)                      flushRespReq  <- mkReg(False);

    // addr aligned with 8B boundary
    function Addr getDWordAlignAddr(Addr a);
        return {truncateLSB(a), 3'b0};
    endfunction

    // This function adjusts the address to point to a valid location in memory
    // If the memory size is a power of 2, it simply truncates it.
    // Otherwise is uses a weird mask derived form memSizeReg - 1
    function Addr adjustAddress(Addr a);
        // This works really well if the address is a power of 2, otherwise it has
        // weird behavior (but still functions as desired).
        let memSizeMask = memSizeReg - 1;
        // If the address needs adjusting, and it with memSizeMask
        return (a >= memSizeReg) ? (a & memSizeMask) : a;
    endfunction

    interface MainMemoryServer to_proc;
        interface Put request;
            method Action put(MainMemoryReq#(MemoryClientType) r);
                if (pack(r.byteen) != '1) begin
                    $fdisplay(stderr, "[ERROR] [SharedMem] request - byteEn != '1");
                end

                Addr addr = adjustAddress(getDWordAlignAddr(r.addr));
                if (r.write) begin
                    // $display("[SharedMem] write - addr: 0x%08x, data: 0x%08x", addr, r.data);
                    writeReqFifo.enq(MemRequest{sglId: refPointerReg, offset: truncate(addr), burstLen: 8, tag: 0});
                    writeDataFifo.enq(MemData{data: r.data, tag: 0, last: True });
                end else begin
                    // $display("[SharedMem] read - addr: 0x%08x", addr);
                    readReqFifo.enq(MemRequest{sglId: refPointerReg, offset: truncate(addr), burstLen: 8, tag: 1});
                    pendingReads.enq(r.tag);
                end
            endmethod
        endinterface
        interface Get response;
            method ActionValue#(MainMemoryResp#(MemoryClientType)) get;
                let client = pendingReads.first;
                pendingReads.deq;
                let d = readDataFifo.first;
                readDataFifo.deq;

                if (d.last != True) begin
                    $fdisplay(stderr, "[ERROR] [SharedMem] response - last != True");
                end

                // $display("[SharedMem] read - data: 0x%08x", d.data);
                return MainMemoryResp{write: False, data: d.data, tag: client};
            endmethod
        endinterface
    endinterface

    interface MemReadClient to_host_read;
        interface Get readReq = toGet(readReqFifo);
        interface Put readData = toPut(readDataFifo);
    endinterface

    interface MemWriteClient to_host_write;
        interface Get writeReq = toGet(writeReqFifo);
        interface Get writeData = toGet(writeDataFifo);
        interface Put writeDone;
            method Action put(Bit#(MemTagSize) x);
                // this bridge ignore write responses
                noAction;
            endmethod
        endinterface
    endinterface

    method Action initSharedMem(Bit#(32) refPointer, Addr memSize);
        // $display("[SharedMem] refPointer = 0x%08x. memSize = 0x%08x", refPointer, memSize);
        refPointerReg <= refPointer;
        memSizeReg <= memSize;
    endmethod

    method Action flushRespReqMem;
        flushRespReq <= True;
    endmethod
    method PendMemRespCnt numberFlyingOperations;
        return pendingReads.notEmpty ? 1 : 0;
    endmethod
endmodule
