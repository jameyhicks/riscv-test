import RVTypes::*;

(* noinline *)
function Addr addrCalc(Data rVal1, Maybe#(Data) imm);
    return rVal1 + fromMaybe(0, imm);
endfunction

//function Data gatherLoad(Addr addr, ByteEn byteEn, Bool unsignedLd, Data data);
//    function extend = unsignedLd ? zeroExtend : signExtend;
//    Bit#(IndxShamt) offset = truncate(addr);
//
//    if(byteEn[7]) begin
//        return extend(data);
//    end else if(byteEn[3]) begin
//        Vector#(2, Bit#(32)) dataVec = unpack(data);
//        return extend(dataVec[offset[2]]);
//    end else if(byteEn[1]) begin
//        Vector#(4, Bit#(16)) dataVec = unpack(data);
//        return extend(dataVec[offset[2:1]]);
//    end else begin
//        Vector#(8, Bit#(8)) dataVec = unpack(data);
//        return extend(dataVec[offset]);
//    end
//endfunction
//
//function Tuple2#(ByteEn, Data) scatterStore(Addr addr, ByteEn byteEn, Data data);
//    Bit#(IndxShamt) offset = truncate(addr);
//    if(byteEn[7]) begin
//        return tuple2(byteEn, data);
//    end else if(byteEn[3]) begin
//        return tuple2(unpack(pack(byteEn) << (offset)), data << {(offset), 3'b0});
//    end else if(byteEn[1]) begin
//        return tuple2(unpack(pack(byteEn) << (offset)), data << {(offset), 3'b0});
//    end else begin
//        return tuple2(unpack(pack(byteEn) << (offset)), data << {(offset), 3'b0});
//    end
//endfunction

