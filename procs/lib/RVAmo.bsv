import RVTypes::*;
import Vector::*;

(* noinline *)
function Data amoExec(RVAmoOp amoFunc, ByteEn byteEn, Data currentData, Data inData);
    Data newData = 0;
    Data oldData = currentData;
    function Bit#(8) byteEnToBitMask(Bool en);
        return en ? 8'hFF : 8'h00;
    endfunction
    Data bitMask = pack(map(byteEnToBitMask, byteEn));

    Data currentDataMasked = currentData & bitMask;
    Data inDataMasked = inData & bitMask;

    // special case for sign extension
    if (amoFunc == Min || amoFunc == Max) begin
        if (byteEn == unpack(8'b00001111)) begin
            // sign extend if necessary
            currentDataMasked[63:32] = currentDataMasked[31] == 1 ? '1 : 0;
            inDataMasked[63:32] = inDataMasked[31] == 1 ? '1 : 0;
        end
    end

    function Bit#(t) sMax( Bit#(t) a, Bit#(t) b );
        Int#(t) x = max(unpack(a), unpack(b));
        return pack(x);
    endfunction
    function Bit#(t) sMin( Bit#(t) a, Bit#(t) b );
        Int#(t) x = min(unpack(a), unpack(b));
        return pack(x);
    endfunction
    function Bit#(t) uMax( Bit#(t) a, Bit#(t) b );
        UInt#(t) x = max(unpack(a), unpack(b));
        return pack(x);
    endfunction
    function Bit#(t) uMin( Bit#(t) a, Bit#(t) b );
        UInt#(t) x = min(unpack(a), unpack(b));
        return pack(x);
    endfunction

    newData = (case (amoFunc)
            Swap: inDataMasked;
            Add:  (currentDataMasked + inDataMasked);
            Xor:  (currentDataMasked ^ inDataMasked);
            And:  (currentDataMasked & inDataMasked);
            Or:   (currentDataMasked | inDataMasked);
            Min:  sMin(currentDataMasked, inDataMasked);
            Max:  sMax(currentDataMasked, inDataMasked);
            Minu: uMin(currentDataMasked, inDataMasked);
            Maxu: uMax(currentDataMasked, inDataMasked);
        endcase);
    newData = (oldData & ~bitMask) | (newData & bitMask);

    return newData;
endfunction
