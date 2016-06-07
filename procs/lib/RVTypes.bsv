/*

Copyright (C) 2012

Arvind <arvind@csail.mit.edu>
Muralidaran Vijayaraghavan <vmurali@csail.mit.edu>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

*/
`include "ProcConfig.bsv"
import DefaultValue::*;
import FShow::*;
import Vector::*;

// TODO: Make AddrSz and DataSz parameters that can be 32 or 64

typedef 64 DataSz;
typedef Bit#(DataSz) Data;
typedef Bit#(TDiv#(DataSz,8)) DataByteEn;

typedef DataSz WordSz;
typedef Bit#(WordSz) Word;
typedef Bit#(TDiv#(WordSz,8)) WordByteEn;

typedef 512 LineSz;
typedef Bit#(LineSz) Line;
typedef Bit#(TDiv#(LineSz,8)) LineByteEn;

typedef 32 InstSz;
typedef Bit#(InstSz) Instruction;

typedef 64 AddrSz;
typedef Bit#(AddrSz) Addr;

typedef AddrSz ByteAddrSz;
typedef Bit#(ByteAddrSz) ByteAddr;

typedef TSub#(AddrSz, TLog#(TDiv#(WordSz,8))) WordAddrSz;
typedef Bit#(WordAddrSz) WordAddr;

typedef TSub#(AddrSz, TLog#(TDiv#(LineSz,8))) LineAddrSz;
typedef Bit#(LineAddrSz) LineAddr;

typedef 8 AsidSz;
typedef Bit#(AsidSz) Asid;

// WARNING: Don't try updating fields when using this type.
typedef struct {
    // full instruction
    Instruction inst;
    // fields (XXX: Should these be Bits or enums?)
    Bit#(5)     rd;
    Bit#(5)     rs1;
    Bit#(5)     rs2;
    Bit#(5)     rs3;
    Bit#(2)     funct2;
    Bit#(3)     funct3;
    Bit#(5)     funct5;
    Bit#(7)     funct7;
    Bit#(2)     fmt;
    RVRoundMode rm;
    Opcode      opcode; // Bit#(7)
    Bit#(12)    csrAddr;
    CSR         csr;
} InstructionFields;
// XXX: probably don't want a Bits instance for this type
instance Bits#(InstructionFields, 32);
    function Bit#(32) pack(InstructionFields x);
        return x.inst;
    endfunction
    function InstructionFields unpack(Bit#(32) x);
        return getInstFields(x);
    endfunction
endinstance
// XXX: ... or an Eq instance
instance Eq#(InstructionFields);
    function Bool \== (InstructionFields a, InstructionFields b);
        return a.inst == b.inst;
    endfunction
endinstance
// XXX: ... or an FShow instance
instance FShow#(InstructionFields);
    function Fmt fshow(InstructionFields x);
        return $format("{InstructionFields: 0x%08x}",x);
    endfunction
endinstance
// XXX: we probably just want this function
function InstructionFields getInstFields(Instruction x);
    return InstructionFields {
            inst:       x,
            rd:         x[11:7],
            rs1:        x[19:15],
            rs2:        x[24:20],
            rs3:        x[31:27],
            funct2:     x[26:25],
            funct3:     x[14:12],
            funct5:     x[31:27],
            funct7:     x[31:25],
            fmt:        x[26:25],
            rm:         unpack(x[14:12]),
            opcode:     unpack(x[6:0]),
            csrAddr:    x[31:20],
            csr:        unpack(x[31:20])
        };
endfunction

typedef TDiv#(DataSz, 8) NumBytes;
typedef TLog#(NumBytes) IndxShamt;
typedef Vector#(NumBytes, Bool) ByteEn;

// This encoding partially matches rocket, one day we may be able to use the same caches
// These are requests that a processor may send to the 
typedef enum {
    Ld              = 3'b000,
    St              = 3'b001,
    PrefetchForLd   = 3'b010,
    PrefetchForSt   = 3'b011,
    Lr              = 3'b110,
    Sc              = 3'b111
} RVMemOp deriving (Bits, Eq, FShow);

// This encoding matches inst[31,30,29,27] since inst[28] is always 0
typedef enum {
    Swap    = 4'b0001,
    Add     = 4'b0000,
    Xor     = 4'b0010,
    And     = 4'b0110,
    Or      = 4'b0100,
    Min     = 4'b1000,
    Max     = 4'b1010,
    Minu    = 4'b1100,
    Maxu    = 4'b1110
} RVAmoOp deriving (Bits, Eq, FShow);

//// This encoding matches rocket
//typedef enum {
//    Ld              = 5'b00000,
//    St              = 5'b00001,
//    PrefetchForLd   = 5'b00010,
//    PrefetchForSt   = 5'b00011,
//    AmoSwap         = 5'b00100,
//    Nop             = 5'b00101,
//    Lr              = 5'b00110,
//    Sc              = 5'b00111,
//    AmoAdd          = 5'b01000,
//    AmoXor          = 5'b01001,
//    AmoOr           = 5'b01010,
//    AmoAnd          = 5'b01011,
//    AmoMin          = 5'b01100,
//    AmoMax          = 5'b01101,
//    AmoMinu         = 5'b01110,
//    AmoMaxu         = 5'b01111,
//    Flush           = 5'b10000,
//    Produce         = 5'b10001,
//    Clean           = 5'b10011
//} RVRocketMemOp deriving (Bits, Eq, FShow);
//
//// Functions from rocket
//function Bool isAMO(RVRocketMemOp op);
//    return (case (op)
//            AmoSwap, AmoAdd, AmoXor, AmoOr, AmoAnd, AmoMin, AmoMax, AmoMinu, AmoMaxu: True;
//            default: False;
//        endcase);
//endfunction
//function Bool isPrefetch(RVRocketMemOp op);
//    return (op == PrefetchForLd) || (op == PrefetchForSt);
//endfunction
//function Bool isRead(RVRocketMemOp op);
//    return (op == Ld) || (op == Lr) || (op == Sc) || isAMO(op);
//endfunction
//function Bool isWrite(RVRocketMemOp op);
//    return (op == St) || (op == Sc) || isAMO(op);
//endfunction
//function Bool isWriteIntent(RVRocketMemOp op);
//    return isWrite(op) || (op == PrefetchForSt) || (op == Lr);
//endfunction

// This encoding matches func3
typedef enum {
    B   = 3'b000,
    H   = 3'b001,
    W   = 3'b010,
    D   = 3'b011,
    BU  = 3'b100,
    HU  = 3'b101,
    WU  = 3'b110
} RVMemSize deriving (Bits, Eq, FShow);
function Bool isUnsigned(RVMemSize x);
    return ((x == BU) || (x == HU) || (x == WU));
endfunction
function ByteEn toByteEn(RVMemSize x);
    return unpack(case (x)
            B, BU:      8'b00000001;
            H, HU:      8'b00000011;
            W, WU:      8'b00001111;
            D:          8'b11111111;
            default:    8'b00000000;
        endcase);
endfunction

typedef union tagged {
    RVMemOp Mem;
    RVAmoOp Amo;
} RVMemAmoOp deriving (Bits, Eq, FShow);

typedef struct {
    RVMemAmoOp  op;
    RVMemSize   size;
} RVMemInst deriving (Bits, Eq, FShow);

typeclass IsMemOp#(type t);
    function Bool isLoad(t x);
    function Bool isStore(t x);
    function Bool isAmo(t x);
    function Bool getsReadPermission(t x);
    function Bool getsWritePermission(t x);
    function Bool getsResponse(t x);
endtypeclass
instance IsMemOp#(RVMemOp);
    function Bool isLoad(RVMemOp x);
        return ((x == Ld) || (x == Lr));
    endfunction
    function Bool isStore(RVMemOp x);
        return ((x == St) || (x == Sc));
    endfunction
    function Bool isAmo(RVMemOp x);
        return False;
    endfunction
    function Bool getsReadPermission(RVMemOp x);
        return ((x == Ld) || (x == PrefetchForLd));
    endfunction
    function Bool getsWritePermission(RVMemOp x);
        return (isStore(x) || (x == Lr) || (x == PrefetchForSt));
    endfunction
    function Bool getsResponse(RVMemOp x);
        return (isLoad(x) || isAmo(x) || (x == Sc));
    endfunction
endinstance
instance IsMemOp#(RVAmoOp);
    function Bool isLoad(RVAmoOp x);
        return False;
    endfunction
    function Bool isStore(RVAmoOp x);
        return False;
    endfunction
    function Bool isAmo(RVAmoOp x);
        return True;
    endfunction
    function Bool getsReadPermission(RVAmoOp x);
        return False;
    endfunction
    function Bool getsWritePermission(RVAmoOp x);
        return True;
    endfunction
    function Bool getsResponse(RVAmoOp x);
        return True;
    endfunction
endinstance
instance IsMemOp#(RVMemAmoOp);
    function Bool isLoad(RVMemAmoOp x);
        return (case (x) matches
                tagged Mem .mem: isLoad(mem);
                tagged Amo .amo: isLoad(amo);
            endcase);
    endfunction
    function Bool isStore(RVMemAmoOp x);
        return (case (x) matches
                tagged Mem .mem: isStore(mem);
                tagged Amo .amo: isStore(amo);
            endcase);
    endfunction
    function Bool isAmo(RVMemAmoOp x);
        return (case (x) matches
                tagged Mem .mem: isAmo(mem);
                tagged Amo .amo: isAmo(amo);
            endcase);
    endfunction
    function Bool getsReadPermission(RVMemAmoOp x);
        return (case (x) matches
                tagged Mem .mem: getsReadPermission(mem);
                tagged Amo .amo: getsReadPermission(amo);
            endcase);
    endfunction
    function Bool getsWritePermission(RVMemAmoOp x);
        return (case (x) matches
                tagged Mem .mem: getsWritePermission(mem);
                tagged Amo .amo: getsWritePermission(amo);
            endcase);
    endfunction
    function Bool getsResponse(RVMemAmoOp x);
        return (case (x) matches
                tagged Mem .mem: getsResponse(mem);
                tagged Amo .amo: getsResponse(amo);
            endcase);
    endfunction
endinstance

typedef struct {
    Bool rv64;
    // ISA modes
    Bool h;
    Bool s;
    Bool u;
    // standard ISA extensions
    Bool m;
    Bool a;
    Bool f;
    Bool d;
    // non-standard extensions
    Bool x;
} RiscVISASubset deriving (Bits, Eq, FShow);

`ifndef m
`define m False
`endif
`ifndef a
`define a False
`endif
`ifndef f
`define f False
`endif
`ifndef d
`define d False
`endif

instance DefaultValue#(RiscVISASubset);
    function RiscVISASubset defaultValue = RiscVISASubset{ rv64: `rv64 , h: False, s: True, u: True, m: `m , a: `a , f: `f , d: `d , x: False };
endinstance

function Data getMCPUID(RiscVISASubset isa);
    Data mcpuid = 0;
    if (isa.rv64) mcpuid = mcpuid | {2'b10, 0, 26'b00000000000000000000000000};
    // include S and I by default
    mcpuid = mcpuid | {2'b00, 0, 26'b00000001000000000100000000};
    if (isa.m) mcpuid = mcpuid | {2'b00, 0, 26'b00000000000001000000000000};
    if (isa.a) mcpuid = mcpuid | {2'b00, 0, 26'b00000000000000000000000001};
    if (isa.f) mcpuid = mcpuid | {2'b00, 0, 26'b00000000000000000000100000};
    if (isa.d) mcpuid = mcpuid | {2'b00, 0, 26'b00000000000000000000001000};
    return mcpuid;
endfunction

typedef Bit#(5) RIndx;
typedef union tagged {
    RIndx   Gpr;
    RIndx   Fpu;
} ArchRIndx deriving (Bits, Eq, FShow, Bounded);
function Maybe#(ArchRIndx) toArchRIndx(Maybe#(RegType) rType, RIndx index);
    return (case (rType)
            tagged Valid Gpr: tagged Valid tagged Gpr index;
            tagged Valid Fpu: tagged Valid tagged Fpu index;
            default: tagged Invalid;
        endcase);
endfunction
typedef 64 NumArchReg;

`ifdef PHYS_REG_COUNT
typedef `PHYS_REG_COUNT NumPhyReg;
`else
typedef NumArchReg NumPhyReg;
`endif
// TODO: Clean this up
typedef Bit#(TLog#(NumPhyReg)) PhyRIndx;
function PhyRIndx identityRegRenaming(RegType rType, RIndx index);
    if (rType == Fpu) begin
        return {1, index};
    end else begin
        return {0, index};
    end
endfunction

// This is not really needed now
typedef struct {
    Maybe#(ArchRIndx) src1;
    Maybe#(ArchRIndx) src2;
    Maybe#(ArchRIndx) src3;
    Maybe#(ArchRIndx) dst;
} ArchRegs deriving (Bits, Eq, FShow);
typedef struct {
    Maybe#(PhyRIndx) src1;
    Maybe#(PhyRIndx) src2;
    Maybe#(PhyRIndx) src3;
    Maybe#(PhyRIndx) dst;
} PhyRegs deriving (Bits, Eq, FShow);

typedef enum {
    Load    = 7'b0000011,
    LoadFp  = 7'b0000111,
    MiscMem = 7'b0001111,
    OpImm   = 7'b0010011,
    Auipc   = 7'b0010111,
    OpImm32 = 7'b0011011,
    Store   = 7'b0100011,
    StoreFp = 7'b0100111,
    Amo     = 7'b0101111,
    Op      = 7'b0110011,
    Lui     = 7'b0110111,
    Op32    = 7'b0111011,
    Fmadd   = 7'b1000011,
    Fmsub   = 7'b1000111,
    Fnmsub  = 7'b1001011,
    Fnmadd  = 7'b1001111,
    OpFp    = 7'b1010011,
    Branch  = 7'b1100011,
    Jalr    = 7'b1100111,
    Jal     = 7'b1101111,
    System  = 7'b1110011
} Opcode deriving (Bits, Eq, FShow);

typedef enum {
    CSRfflags    = 12'h001,
    CSRfrm       = 12'h002,
    CSRfcsr      = 12'h003,
    CSRstoreaddr = 12'h008,
    CSRstore8    = 12'h009,
    CSRstore16   = 12'h00a,
    CSRstore32   = 12'h00b,
    CSRload8     = 12'h00d,
    CSRload16    = 12'h00e,
    CSRload32    = 12'h00f,
    CSRstats     = 12'h0c0,
    CSRsstatus   = 12'h100,
    CSRstvec     = 12'h101,
    CSRsie       = 12'h104,
    CSRstimecmp  = 12'h121,
    CSRsscratch  = 12'h140,
    CSRsepc      = 12'h141,
    CSRsip       = 12'h144,
    CSRsptbr     = 12'h180,
    CSRsasid     = 12'h181,
    CSRhstatus   = 12'h200,
    CSRhtvec     = 12'h201,
    CSRhepc      = 12'h241,
    CSRmstatus   = 12'h300,
    CSRmtvec     = 12'h301,
    CSRmtdeleg   = 12'h302,
    CSRmie       = 12'h304,
    CSRmtimecmp  = 12'h321,
    CSRmscratch  = 12'h340,
    CSRmepc      = 12'h341,
    CSRmcause    = 12'h342,
    CSRmbadaddr  = 12'h343,
    CSRmip       = 12'h344,
    CSRmbase     = 12'h380,
    CSRmbound    = 12'h381,
    CSRmibase    = 12'h382,
    CSRmibound   = 12'h383,
    CSRmdbase    = 12'h384,
    CSRmdbound   = 12'h385,
    CSRsup0      = 12'h500,
    CSRsup1      = 12'h501,
    CSRepc       = 12'h502,
    CSRbadvaddr  = 12'h503,
    CSRptbr      = 12'h504,
    CSRasid      = 12'h505,
    CSRcount     = 12'h506,
    CSRcompare   = 12'h507,
    CSRevec      = 12'h508,
    CSRcause     = 12'h509,
    CSRstatus    = 12'h50a,
    CSRhartid    = 12'h50b,
    CSRimpl      = 12'h50c,
    CSRfatc      = 12'h50d,
    CSRsendipi   = 12'h50e,
    CSRclearipi  = 12'h50f,
    CSRtohost    = 12'h51e,
    CSRfromhost  = 12'h51f,
    CSRmtime     = 12'h701,
    CSRmtimeh    = 12'h741,
    CSRmtohost   = 12'h780,
    CSRmfromhost = 12'h781,
    CSRmreset    = 12'h782,
    CSRmipi      = 12'h783,
    CSRmiobase   = 12'h784,
    CSRcyclew    = 12'h900,
    CSRtimew     = 12'h901,
    CSRinstretw  = 12'h902,
    CSRcyclehw   = 12'h980,
    CSRtimehw    = 12'h981,
    CSRinstrethw = 12'h982,
    CSRstimew    = 12'ha01,
    CSRstimehw   = 12'ha81,
    CSRcycle     = 12'hc00,
    CSRtime      = 12'hc01,
    CSRinstret   = 12'hc02,
    CSRcycleh    = 12'hc80,
    CSRtimeh     = 12'hc81,
    CSRinstreth  = 12'hc82,
    CSRuarch0    = 12'hcc0,
    CSRuarch1    = 12'hcc1,
    CSRuarch2    = 12'hcc2,
    CSRuarch3    = 12'hcc3,
    CSRuarch4    = 12'hcc4,
    CSRuarch5    = 12'hcc5,
    CSRuarch6    = 12'hcc6,
    CSRuarch7    = 12'hcc7,
    CSRuarch8    = 12'hcc8,
    CSRuarch9    = 12'hcc9,
    CSRuarch10   = 12'hcca,
    CSRuarch11   = 12'hccb,
    CSRuarch12   = 12'hccc,
    CSRuarch13   = 12'hccd,
    CSRuarch14   = 12'hcce,
    CSRuarch15   = 12'hccf,
    CSRstime     = 12'hd01,
    CSRscause    = 12'hd42,
    CSRsbadaddr  = 12'hd43,
    CSRstimeh    = 12'hd81,
    CSRmcpuid    = 12'hf00,
    CSRmimpid    = 12'hf01,
    CSRmhartid   = 12'hf10
} CSR deriving (Bits, Eq, FShow);

function Bool hasCSRPermission(CSR csr, Bit#(2) prv, Bool write);
    Bit#(12) csr_index = pack(csr);
    return ((prv >= csr_index[9:8]) && (!write || (csr_index[11:10] != 2'b11)));
endfunction

function Bool isValidCSR(CSR csr, Bool fpuEn);
    return (case (csr)
            // User Floating-Point CSRs
            CSRfflags:    fpuEn;
            CSRfrm:       fpuEn;
            CSRfcsr:      fpuEn;
            // User stats
            CSRstats:     False; // This isn't supported for now
            // User Counter/Timers
            CSRcycle:     True;
            CSRtime:      True;
            CSRinstret:   True;

            // Supervisor Trap Setup
            CSRsstatus:   True;
            CSRstvec:     True;
            CSRsie:       True;
            CSRstimecmp:  True;
            // Supervisor Timer
            CSRstime:     True;
            // Supervisor Trap Handling
            CSRsscratch:  True;
            CSRsepc:      True;
            CSRscause:    True;
            CSRsbadaddr:  True;
            CSRsip:       True;
            // Supervisor Protection and Translation
            CSRsptbr:     True;
            CSRsasid:     True;
            // Supervisor Read/Write Shadow of User Read-Only registers
            CSRcyclew:    True;
            CSRtimew:     True;
            CSRinstretw:  True;

            // Machine Information Registers
            CSRmcpuid:    True;
            CSRmimpid:    True;
            CSRmhartid:   True;
            // Machine Trap Setup
            CSRmstatus:   True;
            CSRmtvec:     True;
            CSRmtdeleg:   True;
            CSRmie:       True;
            CSRmtimecmp:  True;
            // Machine Timers and Counters
            CSRmtime:     True;
            // Machine Trap Handling
            CSRmscratch:  True;
            CSRmepc:      True;
            CSRmcause:    True;
            CSRmbadaddr:  True;
            CSRmip:       True;
            // Machine Protection and Translation
            CSRmbase:     True;
            CSRmbound:    True;
            CSRmibase:    True;
            CSRmibound:   True;
            CSRmdbase:    True;
            CSRmdbound:   True;
            // Machine Host-Target Interface (Non-Standard Berkeley Extension)
            CSRmtohost:   True;
            CSRmfromhost: True;
            CSRmiobase:   True;

            default:      False;
        endcase);
endfunction

// These enumeration values match the bit values for funct3
typedef enum {
    Eq   = 3'b000,
    Neq  = 3'b001,
    Jal  = 3'b010,
    Jalr = 3'b011,
    Lt   = 3'b100,
    Ge   = 3'b101,
    Ltu  = 3'b110,
    Geu  = 3'b111
} BrFunc deriving (Bits, Eq, FShow);

// This encoding tries to match {inst[30], funct3}
typedef enum {
    Add  = 4'b0000,
    Sll  = 4'b0001,
    Slt  = 4'b0010,
    Sltu = 4'b0011,
    Xor  = 4'b0100,
    Srl  = 4'b0101,
    Or   = 4'b0110,
    And  = 4'b0111,
    Sub  = 4'b1000,
    Sra  = 4'b1101,
    // These don't follow the {inst[30], funct3} encoding since they use
    // different opcodes
    // TODO: check the values of these instructions
    // XXX: Should these not specify a value?
    Auipc = 5'b10000,
    Lui   = 5'b11000
} AluFunc deriving (Bits, Eq, FShow);
typedef struct {
    AluFunc             op;
    Bool                w;
} AluInst deriving (Bits, Eq, FShow);

typedef enum {
    Mul     = 2'b00,
    Mulh    = 2'b01,
    Div     = 2'b10,
    Rem     = 2'b11
} MulDivFunc deriving (Bits, Eq, FShow);
typedef enum {Signed, Unsigned, SignedUnsigned} MulDivSign deriving (Bits, Eq, FShow);
typedef struct {
    MulDivFunc  func;
    Bool        w;
    MulDivSign  sign;
} MulDivInst deriving (Bits, Eq, FShow);


typedef enum {
    FAdd, FSub, FMul, FDiv, FSqrt,
    FSgnj, FSgnjn, FSgnjx,
    FMin, FMax,
    FCvt_FF,
    FCvt_WF, FCvt_WUF, FCvt_LF, FCvt_LUF,
    FCvt_FW, FCvt_FWU, FCvt_FL, FCvt_FLU,
    FEq, FLt, FLe,
    FClass, FMv_XF, FMv_FX,
    FMAdd, FMSub, FNMSub, FNMAdd
} FpuFunc deriving (Bits, Eq, FShow);
typedef enum {
    Single,
    Double
} FpuPrecision deriving (Bits, Eq, FShow);
typedef struct {
    FpuFunc         func;
    FpuPrecision    precision;
} FpuInst deriving (Bits, Eq, FShow);


typedef enum {
    FenceI,
    SFenceVM
} IntraCoreFence deriving (Bits, Eq, FShow);

typedef struct {
    Bool sw; // successor wrtie
    Bool sr; // successor read
    Bool so; // successor output
    Bool si; // successor input
    Bool pw; // predecessor write
    Bool pr; // predecessor read
    Bool po; // predecessor output
    Bool pi; // predecessor input
} InterCoreFence deriving (Bits, Eq, FShow);

typedef union tagged {
    IntraCoreFence IntraCore;
    InterCoreFence InterCore;
} Fence deriving (Bits, Eq, FShow);


typedef enum {
    ECall,
    EBreak,
    ERet,
    WFI,
    MRTH,
    MRTS,
    HRTS,
    CSRRW,
    CSRRS,
    CSRRC,
    CSRR, // read-only CSR operation
    CSRW // write-only CSR operation
} SystemInst deriving (Bits, Eq, FShow);

// LdStInst and AmoInst are defined in Types.bsv
typedef union tagged {
    AluInst     Alu;
    BrFunc      Br;
    RVMemInst   Mem;
    MulDivInst  MulDiv;
    FpuInst     Fpu;
    Fence       Fence;
    SystemInst  System;
    // void        Other; // Should be none
} ExecFunc deriving (Bits, Eq, FShow);

typedef enum {
    Gpr = 1'b0,
    Fpu = 1'b1
} RegType deriving (Bits, Eq, FShow);

typedef enum {
    S, SB, U, UJ, I, Z, None
} ImmType deriving (Bits, Eq, FShow);

typedef struct {
    ExecFunc        execFunc;
    ImmType         imm;
    Maybe#(RegType) rs1;
    Maybe#(RegType) rs2;
    Maybe#(RegType) rs3;
    Maybe#(RegType) dst;
    Instruction     inst;
} RVDecodedInst deriving (Bits, Eq, FShow);

// Rounding Modes
typedef enum {
    RNE  = 3'b000,
    RTZ  = 3'b001,
    RDN  = 3'b010,
    RUP  = 3'b011,
    RMM  = 3'b100,
    RDyn = 3'b111
} RVRoundMode deriving (Bits, Eq, FShow);

typedef enum {
    InstAddrMisaligned  = 4'd0,
    InstAccessFault     = 4'd1,
    IllegalInst         = 4'd2,
    Breakpoint          = 4'd3,
    LoadAddrMisaligned  = 4'd4,
    LoadAccessFault     = 4'd5,
    StoreAddrMisaligned = 4'd6,
    StoreAccessFault    = 4'd7,
    EnvCallU            = 4'd8,
    EnvCallS            = 4'd9,
    EnvCallH            = 4'd10,
    EnvCallM            = 4'd11,
    IllegalException    = 4'd15 // to get a 4-bit implementation
} ExceptionCause deriving (Bits, Eq, FShow);

typedef enum {
    SoftwareInterrupt   = 4'd0,
    TimerInterrupt      = 4'd1,
    HostInterrupt       = 4'd2,
    IllegalInterrupt    = 4'd15 // to get 4-bit implementation
} Interrupt deriving (Bits, Eq, FShow);

// Traps are either an exception or an interrupt
typedef union tagged {
    ExceptionCause Exception;
    Interrupt      Interrupt;
} Trap deriving (Bits, Eq, FShow);

typedef struct {
    Bit#(2) prv;
    Bit#(3) frm;
    Bool f_enabled;
    Bool x_enabled;
} CsrState deriving (Bits, Eq, FShow);

typedef struct {
    Addr  pc;
    Addr  nextPc;
    Bool  taken;
    Bool  mispredict;
} Redirect deriving (Bits, Eq, FShow);

typedef struct {
    Addr pc;
    Addr nextPc;
    Bool taken;
    Bool mispredict;
} ControlFlow deriving (Bits, Eq, FShow);

// typedef struct {
//   IType         iType;
//   ExecFunc      execFunc;
//   Maybe#(CSR)   csr;
//   Maybe#(Data)  imm;
// } DecodedInst deriving (Bits, Eq, FShow);

typedef struct {
    Data        data;
    Addr        addr;
    ControlFlow controlFlow;
} ExecResult deriving (Bits, Eq, FShow);

typedef struct {
    Data                    data;
    Bit#(5)                 fflags;
    Addr                    vaddr;
    Addr                    paddr;
    ControlFlow             controlFlow;
    Maybe#(ExceptionCause)  cause;
} FullResult deriving (Bits, Eq, FShow);

typeclass FullResultSubset#(type t);
    function FullResult updateFullResult(t x, FullResult full_result);
endtypeclass
instance FullResultSubset#(ExecResult);
    function FullResult updateFullResult(ExecResult x, FullResult full_result);
        full_result.data = x.data;
        full_result.vaddr = x.addr;
        full_result.controlFlow = x.controlFlow;
        return full_result;
    endfunction
endinstance
instance DefaultValue#(ControlFlow);
    function ControlFlow defaultValue = ControlFlow{pc: 0,
                                                    nextPc: 0,
                                                    taken: False,
                                                    mispredict: False};
endinstance
instance DefaultValue#(FullResult);
    function FullResult defaultValue = FullResult{  data: 0,
                                                    fflags: 0,
                                                    vaddr: 0,
                                                    paddr: 0,
                                                    controlFlow: defaultValue,
                                                    cause: tagged Invalid};
endinstance
function FullResult toFullResult(t x) provisos (FullResultSubset#(t));
    return updateFullResult(x, defaultValue);
endfunction

typedef struct {
  Bit#(2) prv;
  Asid    asid;
  Bit#(5) vm;
  Addr    base;
  Addr    bound;
} VMInfo deriving (Bits, Eq, FShow);
instance DefaultValue#(VMInfo);
    function VMInfo defaultValue = VMInfo {prv: prvM, asid: 0, vm: 0, base: 0, bound: 0};
endinstance

typedef 4 NumSpecTags;
typedef Bit#(TLog#(NumSpecTags)) SpecTag;
typedef Bit#(NumSpecTags) SpecBits;

// typedef 32 NumInstTags; // Old definition
typedef TSub#(NumPhyReg, NumArchReg) NumInstTags;
typedef Bit#(TLog#(NumInstTags)) InstTag;

Bit#(2) prvU = 0;
Bit#(2) prvS = 1;
Bit#(2) prvH = 2;
Bit#(2) prvM = 3;

typedef struct{
    RVMemOp op;
    Addr    addr;
} TlbReq deriving (Eq, Bits, FShow);
typedef Tuple2#(Addr, Maybe#(ExceptionCause)) TlbResp;

// Virtual Memory Types
Bit#(5) vmMbare = 0;
Bit#(5) vmMbb   = 1;
Bit#(5) vmMbbid = 2;
Bit#(5) vmSv32  = 8;
Bit#(5) vmSv39  = 9;
Bit#(5) vmSv48  = 10;
Bit#(5) vmSv57  = 11;
Bit#(5) vmSv64  = 12;

typedef struct {
  Bit#(16) reserved;
  Bit#(20) ppn2;
  Bit#(9) ppn1;
  Bit#(9) ppn0;
  Bit#(3) reserved_sw;
  Bool d;
  Bool r;
  PTE_Type pte_type;
  Bool valid;
} PTE_Sv39 deriving (Eq, FShow); // Has custom Bits implementation
typedef struct {
  Bool global;
  Bool s_r;
  Bool s_w;
  Bool s_x;
  Bool u_r;
  Bool u_w;
  Bool u_x;
} PTE_Type deriving (Eq, FShow);
function Bool is_leaf_pte_type(PTE_Type pte_type) = pte_type.s_r;
instance Bits#(PTE_Type, 4);
  function Bit#(4) pack(PTE_Type x);
    Bit#(7) bitvec = {pack(x.global), pack(x.s_r), pack(x.s_w), pack(x.s_x), pack(x.u_r), pack(x.u_w), pack(x.u_x)};
    return (case (bitvec)
        7'b0000000: 0;
        7'b1000000: 1;
        7'b0100101: 2;
        7'b0110111: 3;
        7'b0100100: 4;
        7'b0110110: 5;
        7'b0101101: 6;
        7'b0111111: 7;
        7'b0100000: 8;
        7'b0110000: 9;
        7'b0101000: 10;
        7'b0111000: 11;
        7'b1100000: 12;
        7'b1110000: 13;
        7'b1101000: 14;
        7'b1111000: 15;
        default:    ?;
      endcase);
  endfunction
  function PTE_Type unpack(Bit#(4) x);
    Bit#(7) bitvec = (case (x)
        0:  7'b0000000;
        1:  7'b1000000;
        2:  7'b0100101;
        3:  7'b0110111;
        4:  7'b0100100;
        5:  7'b0110110;
        6:  7'b0101101;
        7:  7'b0111111;
        8:  7'b0100000;
        9:  7'b0110000;
        10: 7'b0101000;
        11: 7'b0111000;
        12: 7'b1100000;
        13: 7'b1110000;
        14: 7'b1101000;
        15: 7'b1111000;
      endcase);
    return (PTE_Type {
        global: unpack(bitvec[6]),
        s_r:    unpack(bitvec[5]),
        s_w:    unpack(bitvec[4]),
        s_x:    unpack(bitvec[3]),
        u_r:    unpack(bitvec[2]),
        u_w:    unpack(bitvec[1]),
        u_x:    unpack(bitvec[0])
      });
  endfunction
endinstance
instance Bits#(PTE_Sv39, 64);
  function Bit#(64) pack(PTE_Sv39 x);
    return {x.reserved, x.ppn2, x.ppn1, x.ppn0, x.reserved_sw, pack(x.d), pack(x.r), pack(x.pte_type), pack(x.valid)};
  endfunction
  function PTE_Sv39 unpack(Bit#(64) x);
    return (PTE_Sv39 {
        reserved:     x[63:48],
        ppn2:         x[47:28],
        ppn1:         x[27:19],
        ppn0:         x[18:10],
        reserved_sw:  x[9:7],
        d:            unpack(x[6]),
        r:            unpack(x[5]),
        pte_type:     unpack(x[4:1]),
        valid:        unpack(x[0])
      });
  endfunction
endinstance

