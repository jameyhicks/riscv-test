import RVTypes::*;

(* noinline *)
function Data execAluInst(AluInst aluInst, Data rVal1, Data rVal2, Maybe#(Data) imm, Data pc);
    Data aluVal1 = (case (aluInst.op)
                        Auipc:   pc;
                        Lui:     0;
                        default: rVal1;
                    endcase);
    Data aluVal2 = (case (imm) matches
                        tagged Valid .validImm: validImm;
                        default:                rVal2;
                    endcase);

    Data data = alu(aluInst.op, aluInst.w, aluVal1, aluVal2);

    return data;
endfunction

(* noinline *)
function Data alu(AluFunc func, Bool w, Data a, Data b);
    // setup inputs
    if (w) begin
        a = (func == Sra) ? signExtend(a[31:0]) : zeroExtend(a[31:0]);
        b = zeroExtend(b[31:0]);
    end
    Bit#(6) shamt = truncate(b);
    if (w) begin
        shamt = {1'b0, shamt[4:0]};
    end

    Data res = (case(func)
            Add:        (a + b);
            Sub:        (a - b);
            And:        (a & b);
            Or:         (a | b);
            Xor:        (a ^ b);
            Slt:        zeroExtend( pack( signedLT(a, b) ) );
            Sltu:       zeroExtend( pack( a < b ) );
            Sll:        (a << shamt);
            Srl:        (a >> shamt);
            Sra:        signedShiftRight(a, shamt);
            Auipc:      (a + b);
            Lui:        (a + b);
            default:    0;
        endcase);

    if (w) begin
        res = signExtend(res[31:0]);
    end

    return res;
endfunction

