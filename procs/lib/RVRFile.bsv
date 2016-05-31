import RVTypes::*;
import Vector::*;

interface ArchRFile;
    // TODO: change Bit#(5) to named type
    method Action wr(RegType regtype, Bit#(5) index, Data data);
    method Data rd1(RegType regtype, Bit#(5) rindx);
    method Data rd2(RegType regtype, Bit#(5) rindx);
    method Data rd3(RegType regtype, Bit#(5) rindx);
endinterface

// This is a merged GPR/FPU register file
(* synthesize *)
module mkArchRFile( ArchRFile );
    let verbose = False;
    File fout = stdout;

    Vector#(32, Reg#(Data)) gpr_rfile <- replicateM(mkReg(0));
    Vector#(32, Reg#(Data)) fpu_rfile <- replicateM(mkReg(0));

    function Data read(RegType regtype, Bit#(5) rindx);
        return (case (regtype)
                Gpr: gpr_rfile[rindx];
                Fpu: fpu_rfile[rindx];
                default: 0;
            endcase);
    endfunction
   
    method Action wr(RegType regtype, Bit#(5) rindx, Data data );
        if (verbose) $fdisplay(fout, fshow(regtype), " ", fshow(rindx), " <= %h", data);
        if (regtype == Gpr) begin
            if (rindx != 0) begin
                gpr_rfile[rindx] <= data;
            end
        end else if (regtype == Fpu) begin
            fpu_rfile[rindx] <= data;
        end
    endmethod

    method Data rd1(RegType regtype, Bit#(5) rindx) = read(regtype, rindx);
    method Data rd2(RegType regtype, Bit#(5) rindx) = read(regtype, rindx);
    method Data rd3(RegType regtype, Bit#(5) rindx) = read(regtype, rindx);
endmodule 

