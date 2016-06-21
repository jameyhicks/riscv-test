import RVTypes::*;
import Vector::*;

interface ArchRFile;
    // TODO: change Bit#(5) to named type
    method Action wr(Maybe#(FullRegIndex) fullRegIndex, Data data);
    method Data rd1(Maybe#(FullRegIndex) fullRegIndex);
    method Data rd2(Maybe#(FullRegIndex) fullRegIndex);
    method Data rd3(Maybe#(FullRegIndex) fullRegIndex);
endinterface

// This is a merged GPR/FPU register file
(* synthesize *)
module mkArchRFile( ArchRFile );
    let verbose = False;
    File fout = stdout;

    Vector#(32, Reg#(Data)) gpr_rfile <- replicateM(mkReg(0));
    Vector#(32, Reg#(Data)) fpu_rfile <- replicateM(mkReg(0));

    function Data read(Maybe#(FullRegIndex) fullRegIndex);
        //if (fullRegIndex matches tagged Valid .validRegIndex) begin
            return (case (fullRegIndex) matches
                    tagged Valid (tagged Gpr 0): 0;
                    tagged Valid (tagged Gpr .rIndex): gpr_rfile[rIndex];
                    tagged Valid (tagged Fpu .rIndex): fpu_rfile[rIndex];
                    default: 0;
                endcase);
        //end else begin
        //    // reading invalid register
        //    return 0;
        //end
    endfunction
   
    method Action wr(Maybe#(FullRegIndex) fullRegIndex, Data data);
        if (verbose) $fdisplay(fout, fshow(fullRegIndex), " <= %h", data);
        case (fullRegIndex) matches
            tagged Valid (tagged Gpr 0): noAction;
            tagged Valid (tagged Gpr .rIndex): gpr_rfile[rIndex] <= data;
            tagged Valid (tagged Fpu .rIndex): fpu_rfile[rIndex] <= data;
            default: noAction;
        endcase
    endmethod

    method Data rd1(Maybe#(FullRegIndex) fullRegIndex) = read(fullRegIndex);
    method Data rd2(Maybe#(FullRegIndex) fullRegIndex) = read(fullRegIndex);
    method Data rd3(Maybe#(FullRegIndex) fullRegIndex) = read(fullRegIndex);
endmodule 

