import SearchFIFO::*;
import RVTypes::*;

interface Scoreboard#(numeric type size);
    method Action insert(Maybe#(FullRegIndex) fullRegIndex);
    method Action remove;
    method Bool search1(Maybe#(FullRegIndex) fullRegIndex);
    method Bool search2(Maybe#(FullRegIndex) fullRegIndex);
    method Bool search3(Maybe#(FullRegIndex) fullRegIndex);
    method Bool notEmpty;
    method Action clear;
endinterface

module mkScoreboard(Scoreboard#(size));
    function Bool isFound(Maybe#(FullRegIndex) x, Maybe#(FullRegIndex) y);
        return isValid(x) && isValid(y) && x == y;
    endfunction

    SearchFIFO#(size, Maybe#(FullRegIndex), Maybe#(FullRegIndex)) f <- mkSearchFIFO(isFound);

    method insert = f.enq;
    method remove = f.deq;
    method search1 = f.search;
    method search2 = f.search;
    method search3 = f.search;
    method notEmpty = f.notEmpty;
    method clear = f.clear;
endmodule

