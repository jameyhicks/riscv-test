`include "ProcConfig.bsv"
`include "Opcodes.defines"

import Opcodes::*;
import RVTypes::*;
import Vector::*;
import DefaultValue::*;

function Maybe#(ExecFunc) toExecFuncI(Instruction inst);
    return (case (inst) matches
            // BRANCH
            `BEQ:   tagged Valid (tagged Br Eq);
            `BNE:   tagged Valid (tagged Br Neq);
            `BLT:   tagged Valid (tagged Br Lt);
            `BGE:   tagged Valid (tagged Br Ge);
            `BLTU:  tagged Valid (tagged Br Ltu);
            `BGEU:  tagged Valid (tagged Br Geu);
            // JALR
            `JALR:  tagged Valid (tagged Br Jalr);
            // JAL
            `JAL:   tagged Valid (tagged Br Jal);

            // LUI
            `LUI:   tagged Valid (tagged Alu AluInst{op: Lui,   w: False});
            // AUIPC
            `AUIPC: tagged Valid (tagged Alu AluInst{op: Auipc, w: False});
            // OP-IMM
            `ADDI:  tagged Valid (tagged Alu AluInst{op: Add,   w: False});
            `SLLI:  tagged Valid (tagged Alu AluInst{op: Sll,   w: False});
            `SLTI:  tagged Valid (tagged Alu AluInst{op: Slt,   w: False});
            `SLTIU: tagged Valid (tagged Alu AluInst{op: Sltu,  w: False});
            `XORI:  tagged Valid (tagged Alu AluInst{op: Xor,   w: False});
            `SRLI:  tagged Valid (tagged Alu AluInst{op: Srl,   w: False});
            `SRAI:  tagged Valid (tagged Alu AluInst{op: Sra,   w: False});
            `ORI:   tagged Valid (tagged Alu AluInst{op: Or,    w: False});
            `ANDI:  tagged Valid (tagged Alu AluInst{op: And,   w: False});
            // OP
            `ADD:   tagged Valid (tagged Alu AluInst{op: Add,   w: False});
            `SUB:   tagged Valid (tagged Alu AluInst{op: Sub,   w: False});
            `SLL:   tagged Valid (tagged Alu AluInst{op: Sll,   w: False});
            `SLT:   tagged Valid (tagged Alu AluInst{op: Slt,   w: False});
            `SLTU:  tagged Valid (tagged Alu AluInst{op: Sltu,  w: False});
            `XOR:   tagged Valid (tagged Alu AluInst{op: Xor,   w: False});
            `SRL:   tagged Valid (tagged Alu AluInst{op: Srl,   w: False});
            `SRA:   tagged Valid (tagged Alu AluInst{op: Sra,   w: False});
            `OR:    tagged Valid (tagged Alu AluInst{op: Or,    w: False});
            `AND:   tagged Valid (tagged Alu AluInst{op: And,   w: False});
            // OP-IMM-32
            `ADDIW: tagged Valid (tagged Alu AluInst{op: Add,   w: True});
            `SLLIW: tagged Valid (tagged Alu AluInst{op: Sll,   w: True});
            `SRLIW: tagged Valid (tagged Alu AluInst{op: Srl,   w: True});
            `SRAIW: tagged Valid (tagged Alu AluInst{op: Sra,   w: True});
            // OP-32
            `ADDW:  tagged Valid (tagged Alu AluInst{op: Add,   w: True});
            `SUBW:  tagged Valid (tagged Alu AluInst{op: Sub,   w: True});
            `SLLW:  tagged Valid (tagged Alu AluInst{op: Sll,   w: True});
            `SRLW:  tagged Valid (tagged Alu AluInst{op: Srl,   w: True});
            `SRAW:  tagged Valid (tagged Alu AluInst{op: Sra,   w: True});

            // LOAD
            `LB:    tagged Valid (tagged Mem RVMemInst{op: tagged Mem Ld, size: B});
            `LH:    tagged Valid (tagged Mem RVMemInst{op: tagged Mem Ld, size: H});
            `LW:    tagged Valid (tagged Mem RVMemInst{op: tagged Mem Ld, size: W});
            `LBU:   tagged Valid (tagged Mem RVMemInst{op: tagged Mem Ld, size: BU});
            `LHU:   tagged Valid (tagged Mem RVMemInst{op: tagged Mem Ld, size: HU});
            // 64-bit Only
            `LD:    tagged Valid (tagged Mem RVMemInst{op: tagged Mem Ld, size: D});
            `LWU:   tagged Valid (tagged Mem RVMemInst{op: tagged Mem Ld, size: WU});
            // STORE
            `SB:    tagged Valid (tagged Mem RVMemInst{op: tagged Mem St, size: B});
            `SH:    tagged Valid (tagged Mem RVMemInst{op: tagged Mem St, size: H});
            `SW:    tagged Valid (tagged Mem RVMemInst{op: tagged Mem St, size: W});
            // 64-bit Only
            `SD:    tagged Valid (tagged Mem RVMemInst{op: tagged Mem St, size: D});

            // MISC-MEM
            `FENCE:     tagged Valid (tagged Fence (tagged InterCore unpack(truncate(inst[27:20]))));
            `FENCE_I:   tagged Valid (tagged Fence (tagged IntraCore FenceI));

            default: tagged Invalid;
        endcase);
endfunction

function Maybe#(ExecFunc) toExecFuncSupervisor(Instruction inst);
    InstructionFields instFields = unpack(inst);
    return (case (inst) matches
            `ECALL:     tagged Valid (tagged System ECall);
            `EBREAK:    tagged Valid (tagged System EBreak);
            `SRET:      tagged Valid (tagged System ERet);
            `SFENCE_VM: tagged Valid (tagged Fence (tagged IntraCore SFenceVM));
            `WFI:       tagged Valid (tagged System WFI);
            // `MRTH:      tagged Invalid;
            `MRTS:      tagged Valid (tagged System MRTS);
            // `HRTS:      tagged Invalid;
            `CSRRW:     tagged Valid (tagged System ((instFields.rd == 0) ? CSRW : CSRRW));
            `CSRRS:     tagged Valid (tagged System ((instFields.rs1 == 0) ? CSRR : CSRRS));
            `CSRRC:     tagged Valid (tagged System ((instFields.rs1 == 0) ? CSRR : CSRRC));
            `CSRRWI:    tagged Valid (tagged System ((instFields.rd == 0) ? CSRW : CSRRW));
            `CSRRSI:    tagged Valid (tagged System ((instFields.rs1 == 0) ? CSRR : CSRRS));
            `CSRRCI:    tagged Valid (tagged System ((instFields.rs1 == 0) ? CSRR : CSRRC));
            default:    tagged Invalid;
        endcase);
endfunction

function Maybe#(ExecFunc) toExecFuncM(Instruction inst);
    return (case(inst) matches
            `MUL:       tagged Valid (tagged MulDiv MulDivInst{func: Mul,  w: False, sign: Signed});
            `MULH:      tagged Valid (tagged MulDiv MulDivInst{func: Mulh, w: False, sign: Signed});
            `MULHSU:    tagged Valid (tagged MulDiv MulDivInst{func: Mulh, w: False, sign: SignedUnsigned});
            `MULHU:     tagged Valid (tagged MulDiv MulDivInst{func: Mulh, w: False, sign: Unsigned});
            `DIV:       tagged Valid (tagged MulDiv MulDivInst{func: Div,  w: False, sign: Signed});
            `DIVU:      tagged Valid (tagged MulDiv MulDivInst{func: Div,  w: False, sign: Unsigned});
            `REM:       tagged Valid (tagged MulDiv MulDivInst{func: Rem,  w: False, sign: Signed});
            `REMU:      tagged Valid (tagged MulDiv MulDivInst{func: Rem,  w: False, sign: Unsigned});
            // RV64M Only
            `MULW:      tagged Valid (tagged MulDiv MulDivInst{func: Mul,  w: True,  sign: Signed});
            `DIVW:      tagged Valid (tagged MulDiv MulDivInst{func: Div,  w: True,  sign: Signed});
            `DIVUW:     tagged Valid (tagged MulDiv MulDivInst{func: Div,  w: True,  sign: Unsigned});
            `REMW:      tagged Valid (tagged MulDiv MulDivInst{func: Rem,  w: True,  sign: Signed});
            `REMUW:     tagged Valid (tagged MulDiv MulDivInst{func: Rem,  w: True,  sign: Unsigned});

            default:    tagged Invalid;
        endcase);
endfunction

function Maybe#(ExecFunc) toExecFuncA(Instruction inst);
    return (case (inst) matches
            // RV32A
            `AMOADD_W:  tagged Valid (tagged Mem RVMemInst{op: tagged Amo Add,  size: W});
            `AMOXOR_W:  tagged Valid (tagged Mem RVMemInst{op: tagged Amo Xor,  size: W});
            `AMOOR_W:   tagged Valid (tagged Mem RVMemInst{op: tagged Amo Or,   size: W});
            `AMOAND_W:  tagged Valid (tagged Mem RVMemInst{op: tagged Amo And,  size: W});
            `AMOMIN_W:  tagged Valid (tagged Mem RVMemInst{op: tagged Amo Min,  size: W});
            `AMOMAX_W:  tagged Valid (tagged Mem RVMemInst{op: tagged Amo Max,  size: W});
            `AMOMINU_W: tagged Valid (tagged Mem RVMemInst{op: tagged Amo Minu, size: W});
            `AMOMAXU_W: tagged Valid (tagged Mem RVMemInst{op: tagged Amo Maxu, size: W});
            `AMOSWAP_W: tagged Valid (tagged Mem RVMemInst{op: tagged Amo Swap, size: W});
            `LR_W:      tagged Valid (tagged Mem RVMemInst{op: tagged Mem Lr,   size: W});
            `SC_W:      tagged Valid (tagged Mem RVMemInst{op: tagged Mem Sc,   size: W});
            // RV64A
            `AMOADD_D:  tagged Valid (tagged Mem RVMemInst{op: tagged Amo Add,  size: D});
            `AMOXOR_D:  tagged Valid (tagged Mem RVMemInst{op: tagged Amo Xor,  size: D});
            `AMOOR_D:   tagged Valid (tagged Mem RVMemInst{op: tagged Amo Or,   size: D});
            `AMOAND_D:  tagged Valid (tagged Mem RVMemInst{op: tagged Amo And,  size: D});
            `AMOMIN_D:  tagged Valid (tagged Mem RVMemInst{op: tagged Amo Min,  size: D});
            `AMOMAX_D:  tagged Valid (tagged Mem RVMemInst{op: tagged Amo Max,  size: D});
            `AMOMINU_D: tagged Valid (tagged Mem RVMemInst{op: tagged Amo Minu, size: D});
            `AMOMAXU_D: tagged Valid (tagged Mem RVMemInst{op: tagged Amo Maxu, size: D});
            `AMOSWAP_D: tagged Valid (tagged Mem RVMemInst{op: tagged Amo Swap, size: D});
            `LR_D:      tagged Valid (tagged Mem RVMemInst{op: tagged Mem Lr,   size: D});
            `SC_D:      tagged Valid (tagged Mem RVMemInst{op: tagged Mem Sc,   size: D});

            default:    tagged Invalid;
        endcase);
endfunction

function Maybe#(ExecFunc) toExecFuncFD(Instruction inst);
    return (case (inst) matches
            `FADD_S:    tagged Valid (tagged Fpu FpuInst{func: FAdd,     precision: Single});
            `FSUB_S:    tagged Valid (tagged Fpu FpuInst{func: FSub,     precision: Single});
            `FMUL_S:    tagged Valid (tagged Fpu FpuInst{func: FMul,     precision: Single});
            `FDIV_S:    tagged Valid (tagged Fpu FpuInst{func: FDiv,     precision: Single});
            `FSGNJ_S:   tagged Valid (tagged Fpu FpuInst{func: FSgnj,    precision: Single});
            `FSGNJN_S:  tagged Valid (tagged Fpu FpuInst{func: FSgnjn,   precision: Single});
            `FSGNJX_S:  tagged Valid (tagged Fpu FpuInst{func: FSgnjx,   precision: Single});
            `FMIN_S:    tagged Valid (tagged Fpu FpuInst{func: FMin,     precision: Single});
            `FMAX_S:    tagged Valid (tagged Fpu FpuInst{func: FMax,     precision: Single});
            `FSQRT_S:   tagged Valid (tagged Fpu FpuInst{func: FSqrt,    precision: Single});

            `FADD_D:    tagged Valid (tagged Fpu FpuInst{func: FAdd,     precision: Double});
            `FSUB_D:    tagged Valid (tagged Fpu FpuInst{func: FSub,     precision: Double});
            `FMUL_D:    tagged Valid (tagged Fpu FpuInst{func: FMul,     precision: Double});
            `FDIV_D:    tagged Valid (tagged Fpu FpuInst{func: FDiv,     precision: Double});
            `FSGNJ_D:   tagged Valid (tagged Fpu FpuInst{func: FSgnj,    precision: Double});
            `FSGNJN_D:  tagged Valid (tagged Fpu FpuInst{func: FSgnjn,   precision: Double});
            `FSGNJX_D:  tagged Valid (tagged Fpu FpuInst{func: FSgnjx,   precision: Double});
            `FMIN_D:    tagged Valid (tagged Fpu FpuInst{func: FMin,     precision: Double});
            `FMAX_D:    tagged Valid (tagged Fpu FpuInst{func: FMax,     precision: Double});
            `FCVT_S_D:  tagged Valid (tagged Fpu FpuInst{func: FCvt_FF,  precision: Single});
            `FCVT_D_S:  tagged Valid (tagged Fpu FpuInst{func: FCvt_FF,  precision: Double});
            `FSQRT_D:   tagged Valid (tagged Fpu FpuInst{func: FSqrt,    precision: Double});

            `FLE_S:     tagged Valid (tagged Fpu FpuInst{func: FLe,      precision: Single});
            `FLT_S:     tagged Valid (tagged Fpu FpuInst{func: FLt,      precision: Single});
            `FEQ_S:     tagged Valid (tagged Fpu FpuInst{func: FEq,      precision: Single});
            `FLE_D:     tagged Valid (tagged Fpu FpuInst{func: FLe,      precision: Double});
            `FLT_D:     tagged Valid (tagged Fpu FpuInst{func: FLt,      precision: Double});
            `FEQ_D:     tagged Valid (tagged Fpu FpuInst{func: FEq,      precision: Double});

            `FCVT_W_S:  tagged Valid (tagged Fpu FpuInst{func: FCvt_WF,  precision: Single});
            `FCVT_WU_S: tagged Valid (tagged Fpu FpuInst{func: FCvt_WUF, precision: Single});
            `FCVT_L_S:  tagged Valid (tagged Fpu FpuInst{func: FCvt_LF,  precision: Single});
            `FCVT_LU_S: tagged Valid (tagged Fpu FpuInst{func: FCvt_LUF, precision: Single});

            `FMV_X_S:   tagged Valid (tagged Fpu FpuInst{func: FMv_XF,   precision: Single});

            `FCLASS_S:  tagged Valid (tagged Fpu FpuInst{func: FClass,   precision: Single});

            `FCVT_W_D:  tagged Valid (tagged Fpu FpuInst{func: FCvt_WF,  precision: Double});
            `FCVT_WU_D: tagged Valid (tagged Fpu FpuInst{func: FCvt_WUF, precision: Double});
            `FCVT_L_D:  tagged Valid (tagged Fpu FpuInst{func: FCvt_LF,  precision: Double});
            `FCVT_LU_D: tagged Valid (tagged Fpu FpuInst{func: FCvt_LUF, precision: Double});

            `FMV_X_D:   tagged Valid (tagged Fpu FpuInst{func: FMv_XF,   precision: Double});

            `FCLASS_D:  tagged Valid (tagged Fpu FpuInst{func: FClass,   precision: Double});

            `FCVT_S_W:  tagged Valid (tagged Fpu FpuInst{func: FCvt_FW,  precision: Single});
            `FCVT_S_WU: tagged Valid (tagged Fpu FpuInst{func: FCvt_FWU, precision: Single});
            `FCVT_S_L:  tagged Valid (tagged Fpu FpuInst{func: FCvt_FL,  precision: Single});
            `FCVT_S_LU: tagged Valid (tagged Fpu FpuInst{func: FCvt_FLU, precision: Single});
            `FMV_S_X:   tagged Valid (tagged Fpu FpuInst{func: FMv_FX,   precision: Single});

            `FCVT_D_W:  tagged Valid (tagged Fpu FpuInst{func: FCvt_FW,  precision: Double});
            `FCVT_D_WU: tagged Valid (tagged Fpu FpuInst{func: FCvt_FWU, precision: Double});
            `FCVT_D_L:  tagged Valid (tagged Fpu FpuInst{func: FCvt_FL,  precision: Double});
            `FCVT_D_LU: tagged Valid (tagged Fpu FpuInst{func: FCvt_FLU, precision: Double});
            `FMV_D_X:   tagged Valid (tagged Fpu FpuInst{func: FMv_FX,   precision: Double});

            // Floating-Point Memory instructions
            `FLW:       tagged Valid (tagged Mem RVMemInst{op: tagged Mem Ld, size: WU});
            `FLD:       tagged Valid (tagged Mem RVMemInst{op: tagged Mem Ld, size: D});
            `FSW:       tagged Valid (tagged Mem RVMemInst{op: tagged Mem St, size: WU});
            `FSD:       tagged Valid (tagged Mem RVMemInst{op: tagged Mem St, size: D});

            // FMA instructions
            `FMADD_S:   tagged Valid (tagged Fpu FpuInst{func: FMAdd,  precision: Single});
            `FMSUB_S:   tagged Valid (tagged Fpu FpuInst{func: FMSub,  precision: Single});
            `FNMSUB_S:  tagged Valid (tagged Fpu FpuInst{func: FNMSub, precision: Single});
            `FNMADD_S:  tagged Valid (tagged Fpu FpuInst{func: FNMAdd, precision: Single});
            `FMADD_D:   tagged Valid (tagged Fpu FpuInst{func: FMAdd,  precision: Double});
            `FMSUB_D:   tagged Valid (tagged Fpu FpuInst{func: FMSub,  precision: Double});
            `FNMSUB_D:  tagged Valid (tagged Fpu FpuInst{func: FNMSub, precision: Double});
            `FNMADD_D:  tagged Valid (tagged Fpu FpuInst{func: FNMAdd, precision: Double});

            default:    tagged Invalid;
        endcase);
endfunction

// This returns a valid result if the instruction is legal, otherwise it
// returns a tagged invalid.
function Maybe#(RVDecodedInst) decodeInst(Instruction inst);
    Maybe#(ExecFunc) execFunc = toExecFuncI(inst);
    if (!isValid(execFunc)) begin
        execFunc = toExecFuncSupervisor(inst);
    end
    if (!isValid(execFunc)) begin
        execFunc = toExecFuncM(inst);
    end
    if (!isValid(execFunc)) begin
        execFunc = toExecFuncA(inst);
    end
    if (!isValid(execFunc)) begin
        execFunc = toExecFuncFD(inst);
    end
    if (execFunc matches tagged Valid .validExecFunc) begin
        InstType instType = toInstType(inst);
        return tagged Valid (RVDecodedInst {
                execFunc: validExecFunc,
                imm: instType.imm,
                rs1: instType.rs1,
                rs2: instType.rs2,
                rs3: instType.rs3,
                dst: instType.dst,
                inst: inst });
    end else begin
        return tagged Invalid;
    end
endfunction

// This function is used to get the immediate value from a decoded instruction
function Maybe#(Data) getImmediate(ImmType imm, Instruction inst);
    Data immI  = signExtend(inst[31:20]);
    Data immS  = signExtend({inst[31:25], inst[11:7]});
    Data immSB = signExtend({inst[31], inst[7], inst[30:25], inst[11:8], 1'b0});
    Data immU  = signExtend({inst[31:12], 12'b0});
    Data immUJ = signExtend({inst[31], inst[19:12], inst[20], inst[30:21], 1'b0});
    Data immZ  = zeroExtend(inst[19:15]);
    return (case (imm)
            S:  tagged Valid immS;
            SB: tagged Valid immSB;
            U:  tagged Valid immU;
            UJ: tagged Valid immUJ;
            I:  tagged Valid immI;
            Z:  tagged Valid immZ;
            default: tagged Invalid;
        endcase);
endfunction

