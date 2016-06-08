import RVTypes::*;

(* noinline *)
function Addr execControl(BrFunc brFunc, Data rVal1, Data rVal2, Maybe#(Data) imm, Addr pc);
    // XXX: This should only be used with a valid imm
    Bool taken = aluBr(brFunc, rVal1, rVal2);
    Addr targetPc = brAddrCalc(brFunc, pc, rVal1, fromMaybe(?, imm));
    return taken ? targetPc : (pc + 4);
endfunction

(* noinline *)
function Bool aluBr(BrFunc brFunc, Data a, Data b);
    Bool brTaken = (case(brFunc)
            Eq:         (a == b);
            Neq:        (a != b);
            Lt:         signedLT(a, b);
            Ltu:        (a < b);
            Ge:         signedGE(a, b);
            Geu:        (a >= b);
            Jal:        True;
            Jalr:       True;
            default:    True;
        endcase);
    return brTaken;
endfunction

(* noinline *)
function Addr brAddrCalc(BrFunc brFunc, Addr pc, Data val, Data imm);
    Addr targetAddr = (case (brFunc)
            Jal:        (pc + imm);
            Jalr:       {(val + imm)[valueOf(AddrSz)-1:1], 1'b0};
            default:    (pc + imm);
        endcase);
    return targetAddr;
endfunction

