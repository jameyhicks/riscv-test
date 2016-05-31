// PerfMonitorConnectal.bsv
// ------------------------
// PerfMonitor interfaces for connectal

package PerfMonitorConnectal;

interface PerfMonitorRequest;
    method Action reset;
    method Action setEnable(Bool en);
    method Action req(Bit#(32) index); // XXX: assumes PerfIndex == Bit#(32)
endinterface

interface PerfMonitorIndication;
    method Action resp(Bit#(64) x); // XXX: assumes PerfData == Bit#(64)
endinterface

endpackage
