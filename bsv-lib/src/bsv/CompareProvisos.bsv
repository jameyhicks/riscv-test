// CompareProvisos.bsv
// These are human readable provisos for comparing sizes of numberic types

// a > b
typeclass GT#(numeric type a, numeric type b);
endtypeclass
instance GT#(a, b) provisos (Add#(_n, TAdd#(b,1), a));
endinstance

// a >= b
typeclass GTE#(numeric type a, numeric type b);
endtypeclass
instance GTE#(a, b) provisos (Add#(_n, b, a));
endinstance

// a < b
typeclass LT#(numeric type a, numeric type b);
endtypeclass
instance LT#(a, b) provisos (Add#(_n, TAdd#(a,1), b));
endinstance

// a <= b
typeclass LTE#(numeric type a, numeric type b);
endtypeclass
instance LTE#(a, b) provisos (Add#(_n, a, b));
endinstance

// a == b
typeclass EQ#(numeric type a, numeric type b);
endtypeclass
instance EQ#(a, b) provisos (Add#(0, a, b));
endinstance
