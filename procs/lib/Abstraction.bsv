import ClientServer::*;
import Connectable::*;
import DefaultValue::*;
import GetPut::*;
import Vector::*;

import RVTypes::*;
import VerificationPacket::*;

/////////////////////////////////////////////
// Types for the three module abstraction: //
/////////////////////////////////////////////

typedef struct {
    Addr                    pc;
    Maybe#(Addr)            ppc; // invalid if front-end made no prediction
                                 // (i.e. it is waiting for a redirection)
    Instruction             inst;
    RVDecodedInst           dInst;
    Maybe#(ExceptionCause)  cause;
    epochType               backendEpoch;
} FrontEndToBackEnd#(type epochType) deriving (Bits, Eq, FShow);

typedef struct {
    Addr                pc;
    epochType           epoch;
    FrontEndCsrs        frontEndCsrs;
} Redirect#(type epochType) deriving (Bits, Eq, FShow);

typedef struct {
    VMInfo      vmI; // only if MMU is in front-end
    CsrState    state; // Bit#(2) prv;
                       // Bit#(3) frm;
                       // Bool f_enabled;
                       // Bool x_enabled;
} FrontEndCsrs deriving (Bits, Eq, FShow);
instance DefaultValue#(CsrState);
    function CsrState defaultValue = CsrState {prv: prvM, frm: 0, f_enabled: False, x_enabled: False};
endinstance
instance DefaultValue#(FrontEndCsrs);
    function FrontEndCsrs defaultValue = FrontEndCsrs {vmI: defaultValue, state: defaultValue};
endinstance

typedef struct {
    Addr    pc;
    Addr    nextPc;
    BrFunc  brFunc;
    Bool    taken;
} TrainingData deriving (Bits, Eq, FShow);

// front-end memory ports
typedef Addr RVIMMUReq; // maybe add prv
typedef struct {
    Addr                    addr;
    Maybe#(ExceptionCause)  exception;
} RVIMMUResp deriving (Bits, Eq, FShow);

typedef Addr RVIMemReq;
typedef Instruction RVIMemResp;

// back-end memory ports
typedef struct {
    Addr      addr;
    RVMemSize size; // for address misaligned
    RVMemOp   op; // really just load or store (amo counts as store)
} RVDMMUReq deriving (Bits, Eq, FShow);
typedef RVIMMUResp RVDMMUResp;

typedef struct {
    RVMemAmoOp      op;
    ByteEn          byteEn;
    Addr            addr;
    Data            data;
    // Bool aq; // XXX: I don't think these are necessary
    // Bool rl; // XXX: I don't think these are necessary
    Bool            unsignedLd;
} RVDMemReq deriving (Bits, Eq, FShow);
typedef Data RVDMemResp;

typedef Fence FenceReq;
typedef void FenceResp;

// main memory ports
typedef enum {IMMU, ICache, DMMU, DCache} MemoryClientType deriving (Bits, Eq, FShow);
typedef struct {
    Bool    write;
    Bit#(8) byteen;
    Addr    addr;
    Data    data;
    tagT    tag;
} MainMemReq#(type tagT) deriving (Bits, Eq, FShow);
typedef MainMemReq#(tagT) MainMemoryReq#(type tagT); // TODO: use only one of these types
typedef struct {
    Bool    write;
    Data    data;
    tagT    tag;
} MainMemResp#(type tagT) deriving (Bits, Eq, FShow);
typedef MainMemResp#(tagT) MainMemoryResp#(type tagT); // TODO: use only one of these types
typedef Client#(MainMemReq#(tagT),MainMemResp#(tagT)) MainMemoryClient#(type tagT);
typedef Server#(MainMemReq#(tagT),MainMemResp#(tagT)) MainMemoryServer#(type tagT);

interface FrontEnd#(type epochType);
    // To Front-End
    method ActionValue#(FrontEndToBackEnd#(epochType)) instToBackEnd;
    method Action redirect(Redirect#(epochType) r);
    method Action train(TrainingData d);
    // To Memory System
    interface Client#(RVIMMUReq, RVIMMUResp) ivat;
    interface Client#(RVIMemReq, RVIMemResp) ifetch;
    // Debugging Interface
    method Action start(Addr pc);
    method Action stop;
endinterface

interface BackEnd#(type epochType);
    // To Front-End
    method Action instFromFrontEnd(FrontEndToBackEnd#(epochType) inst);
    method ActionValue#(Redirect#(epochType)) getRedirect;
    method ActionValue#(TrainingData) getTrain;
    // To Memory System
    interface Client#(RVDMMUReq, RVDMMUResp) dvat;
    interface Client#(RVDMemReq, RVDMemResp) dmem;
    interface Client#(FenceReq, FenceResp) fence;
    method ActionValue#(VMInfo) updateVMInfoI;
    method ActionValue#(VMInfo) updateVMInfoD;
    // Debugging Interface
    interface Client#(Data, Data) htif;
    method ActionValue#(VerificationPacket) getVerificationPacket;
    method Action configure(Data miobase);
endinterface

interface MemorySystem;
    // To Front-End
    interface Server#(RVIMMUReq, RVIMMUResp) ivat;
    interface Server#(RVIMemReq, RVIMemResp) ifetch;
    // To Back-End
    interface Server#(RVDMMUReq, RVDMMUResp) dvat;
    interface Server#(RVDMemReq, RVDMemResp) dmem;
    interface Server#(FenceReq, FenceResp) fence;
    method Action updateVMInfoI(VMInfo vmI);
    method Action updateVMInfoD(VMInfo vmD);
endinterface

interface MulticoreMemorySystem#(numeric type numCores);
    interface Vector#(numCores, MemorySystem) core;
    // To main memory and devices
    // interface RiscyAxiMaster mainMemory; // XXX: old interface
    interface Client#(MainMemReq#(MemoryClientType), MainMemResp#(MemoryClientType)) mainMemory;
endinterface

typedef MulticoreMemorySystem#(1) SingleCoreMemorySystem;

instance Connectable#(FrontEnd#(epochType), BackEnd#(epochType));
    module mkConnection#(FrontEnd#(epochType) fe, BackEnd#(epochType) be)(Empty);
        rule _instToBackEnd;
            let x <- fe.instToBackEnd;
            be.instFromFrontEnd(x);
        endrule
        rule _redirectToFrontEnd;
            let x <- be.getRedirect;
            fe.redirect(x);
        endrule
        rule _trainToBackEnd;
            let x <- be.getTrain;
            fe.train(x);
        endrule
    endmodule
endinstance
instance Connectable#(FrontEnd#(epochType), MemorySystem);
    module mkConnection#(FrontEnd#(epochType) fe, MemorySystem mem)(Empty);
        mkConnection(fe.ivat, mem.ivat);
        mkConnection(fe.ifetch, mem.ifetch);
    endmodule
endinstance
instance Connectable#(BackEnd#(epochType), MemorySystem);
    module mkConnection#(BackEnd#(epochType) be, MemorySystem mem)(Empty);
        mkConnection(be.dvat, mem.dvat);
        mkConnection(be.dmem, mem.dmem);
        mkConnection(be.fence, mem.fence);
        mkConnection(toGet(be.updateVMInfoI), toPut(mem.updateVMInfoI));
        mkConnection(toGet(be.updateVMInfoD), toPut(mem.updateVMInfoD));
    endmodule
endinstance
