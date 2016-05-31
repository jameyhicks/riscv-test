import Abstraction::*;
import ClientServer::*;
import GetPut::*;
import FIFO::*;
import PrintTrace::*;

interface MainMemoryArbiter;
    interface Server#(MainMemReq#(void), MainMemResp#(void)) iMMU;
    interface Server#(MainMemReq#(void), MainMemResp#(void)) iCache;
    interface Server#(MainMemReq#(void), MainMemResp#(void)) dMMU;
    interface Server#(MainMemReq#(void), MainMemResp#(void)) dCache;
    interface Client#(MainMemReq#(MemoryClientType), MainMemResp#(MemoryClientType)) mainMemory;
endinterface

module mkMainMemoryArbiter(MainMemoryArbiter);
    Bool verbose = False;
    File tracefile = verbose ? stdout : tagged InvalidFile;

    FIFO#(MainMemReq#(MemoryClientType)) memReqFifo <- fprintTraceM(tracefile, "MainMemoryArbiter::memReqFifo", mkFIFO);
    FIFO#(MainMemResp#(MemoryClientType)) memRespFifo <- fprintTraceM(tracefile, "MainMemoryArbiter::memRespFifo", mkFIFO);

    function Server#(MainMemReq#(void), MainMemResp#(void)) makeServerIFC(MemoryClientType client);
        return (interface Server;
                    interface Put request;
                        method Action put(MainMemReq#(void) r);
                            MainMemReq#(MemoryClientType) newR;
                            newR.write = r.write;
                            newR.byteen = r.byteen;
                            newR.addr = r.addr;
                            newR.data = r.data;
                            newR.tag = client;
                            memReqFifo.enq(newR);
                        endmethod
                    endinterface
                    interface Get response;
                        method ActionValue#(MainMemResp#(void)) get if (memRespFifo.first.tag == client);
                            MainMemResp#(MemoryClientType) r = memRespFifo.first;
                            memRespFifo.deq;
                            MainMemResp#(void) newR;
                            newR.write = r.write;
                            newR.data = r.data;
                            newR.tag = ?;
                            return newR;
                        endmethod
                    endinterface
                endinterface);
    endfunction

    interface Server iMMU = makeServerIFC(IMMU);
    interface Server iCache = makeServerIFC(ICache);
    interface Server dMMU = makeServerIFC(DMMU);
    interface Server dCache = makeServerIFC(DCache);

    interface Client mainMemory;
        interface Get request = toGet(memReqFifo);
        interface Put response = toPut(memRespFifo);
    endinterface
endmodule
