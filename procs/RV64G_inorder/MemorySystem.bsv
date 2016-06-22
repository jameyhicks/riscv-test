import ClientServer::*;
import DefaultValue::*;
import FIFOF::*;
import GetPut::*;
import Vector::*;

import PrintTrace::*;
import Abstraction::*;
import RVAmo::*;
import MainMemoryArbiter::*;
import RVExec::*;
import RVTypes::*;

module mkBasicMemorySystem(SingleCoreMemorySystem);
    Bool verbose = False;
    File tracefile = verbose ? stdout : tagged InvalidFile;

    let arbiter <- mkMainMemoryArbiter;

    let itlb <- mkDummyRVIMMU(fprintTrace(tracefile, "IMMU-Arbiter", arbiter.iMMU));
    let icache <- mkDummyRVICache(fprintTrace(tracefile, "ICache-Arbiter", arbiter.iCache));
    let dtlb <- mkDummyRVDMMU(False, fprintTrace(tracefile, "DMMU-Arbiter", arbiter.dMMU));
    let dcache <- mkDummyRVDCache(fprintTrace(stdout, "DCache-Arbiter", arbiter.dCache));

    Vector#(numCores, MemorySystem) onecore;
    onecore[0] = (interface MemorySystem;
            interface Server ivat = fprintTrace(tracefile, "Proc-IMMU", (interface Server;
                                        interface Put request = itlb.request;
                                        interface Get response = itlb.response;
                                    endinterface));
            interface Server ifetch = fprintTrace(tracefile, "Proc-ICache", icache);
            interface Server dvat = fprintTrace(tracefile, "Proc-DMMU", (interface Server;
                                        interface Put request = dtlb.request;
                                        interface Get response = dtlb.response;
                                    endinterface));
            interface Server dmem = fprintTrace(tracefile, "Proc-DCache", dcache);
            interface Server fence;
                interface Put request;
                    method Action put(FenceReq f);
                        noAction;
                    endmethod
                endinterface
                interface Get response;
                    method ActionValue#(FenceResp) get;
                        return ?;
                    endmethod
                endinterface
            endinterface
            method Action updateVMInfoI(VMInfo vmI);
                itlb.updateVMInfo(vmI);
            endmethod
            method Action updateVMInfoD(VMInfo vmD);
                dtlb.updateVMInfo(vmD);
            endmethod
        endinterface);
    return (interface SingleCoreMemorySystem;
            interface Vector core = onecore;
            interface Client mainMemory = arbiter.mainMemory;
        endinterface);
endmodule

module mkDummyRVDCache#(MainMemoryServer#(void) mainMemory)(Server#(RVDMemReq, RVDMemResp));
    FIFOF#(RVDMemReq) procMemReq <- mkFIFOF;
    FIFOF#(RVDMemResp) procMemResp <- mkFIFOF;

    // True if this dummy cache is currently handling the "modify-write" part
    // of a read-modify-write operation.
    // NOTE: normal stores with byte enables count as RMW operations.
    Reg#(Bool) rmw <- mkReg(False);

    // Forces this dummy cache to wait for writes to finish before handling new reads
    Reg#(Bool) writePending <- mkReg(False);
    Reg#(Bool) readPending <- mkReg(False);

    FIFOF#(Tuple3#(Addr,ByteEn,Bool)) outstanding <- mkFIFOF;

    function Bool requiresRMW(RVDMemReq r);
        // The AxiSharedMemoryBridge can't handle byte enables, so we are handling it here
        return ((isStore(r.op) && r.byteEn != replicate(True)) || isAmo(r.op));
    endfunction

    rule ignoreWriteResps;
        let _x <- mainMemory.response.get();
        when(_x.write == True, noAction);
        writePending <= False;
    endrule

    // hanle request
    rule handleRVDMemReq(!rmw && !writePending && !readPending); // XXX: hopefully this fixed it // FIXME: This can result in an issue if there are multiple outstanding loads
        let r = procMemReq.first;
        // This dummy cache does not support LR/SR instructions
        if (isLoad(r.op) || requiresRMW(r)) begin
            // send read request
            mainMemory.request.put(MainMemoryReq{write: False, byteen: '1, addr: r.addr, data: ?, tag: ?});
            readPending <= True;
        end else if (isStore(r.op)) begin
            // send write request
            mainMemory.request.put(MainMemoryReq{write: True, byteen: pack(r.byteEn), addr: r.addr, data: r.data, tag: ?});
            writePending <= True;
            if (r.op == tagged Mem Sc) begin
                // successful
                procMemResp.enq(0);
            end
        end
        if (requiresRMW(r)) begin
            rmw <= True;
        end else begin
            procMemReq.deq;
        end
    endrule

    rule finishRMW(rmw && !writePending);
        let r = procMemReq.first;
        // get read data
        let memResp <- mainMemory.response.get;
        when(memResp.write == False, noAction);
        readPending <= False;
        let data = memResp.data;
        // amoExec also handles plain stores with byte enables
        // If r.op is not an AMO operation, use Swap to perform stores with byte enables
        let newData = amoExec(r.op matches tagged Amo .amoFunc ? amoFunc : Swap, r.byteEn, data, r.data);
        mainMemory.request.put(MainMemoryReq{write: True, byteen: '1, addr: r.addr, data: newData, tag: ?});
        writePending <= True;
        if (r.op == tagged Mem Sc) begin
            // Successful
            procMemResp.enq(0);
        end else if (r.op matches tagged Amo .*) begin
            procMemResp.enq(data);
        end
        // finish
        rmw <= False;
        procMemReq.deq;
    endrule

    rule handleRVDMemResp(!rmw);
        let memResp <- mainMemory.response.get;
        when(memResp.write == False, noAction);
        procMemResp.enq(memResp.data);
        readPending <= False;
    endrule

    interface Put request;
        method Action put(RVDMemReq r);
            if (isLoad(r.op) || isAmo(r.op)) begin
                // old byte enable is used for gatherLoad
                outstanding.enq(tuple3(r.addr, r.byteEn, r.unsignedLd));
            end else if (r.op == tagged Mem Sc) begin
                outstanding.enq(tuple3(0, replicate(True), False));
            end
            if (isStore(r.op) || isAmo(r.op)) begin
                // new byte enable is used within the cache
                let {newByteEn, newData} = scatterStore(r.addr, r.byteEn, r.data);
                r.byteEn = newByteEn;
                r.data = newData;
            end
            procMemReq.enq(r);
        endmethod
    endinterface
    interface Get response;
        method ActionValue#(RVDMemResp) get;
            let {addr, byteEn, unsignedLd} = outstanding.first;
            outstanding.deq;
            procMemResp.deq;
            return gatherLoad(addr, byteEn, unsignedLd, procMemResp.first);
        endmethod
    endinterface
endmodule

module mkRVIMemWrapper#(Server#(RVDMemReq, RVDMemResp) dMem)(Server#(RVIMemReq, RVIMemResp));
    interface Put request;
        method Action put(RVIMemReq req);
            let dReq = RVDMemReq {
                    op: tagged Mem Ld,
                    byteEn: unpack(8'b00001111),
                    addr: req,
                    data: 0,
                    unsignedLd: False };
            dMem.request.put(dReq);
        endmethod
    endinterface
    interface Get response;
        method ActionValue#(RVIMemResp) get;
            let resp <- dMem.response.get;
            return truncate(resp);
        endmethod
    endinterface
endmodule

module mkDummyRVICache#(MainMemoryServer#(void) mainMemory)(Server#(RVIMemReq, RVIMemResp));
    let _dMem <- mkDummyRVDCache(mainMemory);
    let _iMem <- mkRVIMemWrapper(_dMem);
    return _iMem;
endmodule

interface RVDMMU;
    interface Put#(RVDMMUReq) request;
    interface Get#(RVDMMUResp) response;
    method Action updateVMInfo(VMInfo vm);
endinterface

interface RVIMMU;
    interface Put#(RVIMMUReq) request;
    interface Get#(RVIMMUResp) response;
    method Action updateVMInfo(VMInfo vm);
endinterface

// This does not support any paged virtual memory modes
module mkBasicDummyRVDMMU#(Bool isInst, MainMemoryServer#(void) mainMemory)(RVDMMU);
    FIFOF#(RVDMMUReq) procMMUReq <- mkFIFOF;
    FIFOF#(RVDMMUResp) procMMUResp <- mkFIFOF;

    // TODO: This should be defaultValue
    Reg#(VMInfo) vmInfo <- mkReg(VMInfo{prv:2'b11, asid:0, vm:0, base:0, bound:'1});

    rule doTranslate;
        // TODO: add misaligned address exceptions

        // let {addr: .vaddr, op: .op} = procMMUReq.first;
        let vaddr = procMMUReq.first.addr;
        let op = procMMUReq.first.op;
        procMMUReq.deq;

        Bool isStore = getsWritePermission(op); // XXX: was isStore(r.op) || isAmo(r.op) || (r.op == tagged Mem PrefetchForSt);
        Bool isSupervisor = vmInfo.prv == prvS;

        Addr paddr = 0;
        Maybe#(ExceptionCause) exception = tagged Invalid;
        Maybe#(ExceptionCause) accessFault = tagged Valid (isInst ? InstAccessFault :
                                                            (isStore ? StoreAccessFault :
                                                                LoadAccessFault));

        if (vmInfo.prv == prvM) begin
            paddr = vaddr;
        end else begin
            case (vmInfo.vm)
                vmMbare:        paddr = vaddr;
                vmMbb, vmMbbid: begin
                                    if (vaddr > vmInfo.bound) begin
                                        exception = accessFault;
                                    end else begin
                                        paddr = vaddr + vmInfo.base;
                                    end
                                end
                default:
                    // unsupported virtual addressing mode
                    exception = accessFault;
            endcase
        end

        procMMUResp.enq(RVDMMUResp{addr: paddr, exception: exception});
    endrule

    interface Put request;
        method Action put(RVDMMUReq r);
            procMMUReq.enq(r);
        endmethod
    endinterface
    interface Get response;
        method ActionValue#(RVDMMUResp) get;
            procMMUResp.deq;
            return procMMUResp.first;
        endmethod
    endinterface
    method Action updateVMInfo(VMInfo vm);
        vmInfo <= vm;
    endmethod
endmodule

module mkRVIMMUWrapper#(RVDMMU dMMU)(RVIMMU);
    interface Put request;
        method Action put(RVIMMUReq req);
            dMMU.request.put(RVDMMUReq{addr: req, size: W, op: Ld}); // XXX: Should this type include AMO instructions too?
        endmethod
    endinterface
    interface Get response;
        method ActionValue#(RVIMMUResp) get;
            let resp <- dMMU.response.get;
            return resp;
        endmethod
    endinterface
    method Action updateVMInfo(VMInfo vm);
        dMMU.updateVMInfo(vm);
    endmethod
endmodule

module mkDummyRVIMMU#(MainMemoryServer#(void) mainMemory)(RVIMMU);
    let _dMMU <- mkDummyRVDMMU(True, mainMemory);
    let _iMMU <- mkRVIMMUWrapper(_dMMU);
    return _iMMU;
endmodule

module mkDummyRVDMMU#(Bool isInst, MainMemoryServer#(void) mainMemory)(RVDMMU);
    FIFOF#(RVDMMUReq) procMMUReq <- mkFIFOF;
    FIFOF#(RVDMMUResp) procMMUResp <- mkFIFOF;

    // TODO: This should be defaultValue
    Reg#(VMInfo) vmInfo <- mkReg(VMInfo{prv:2'b11, asid:0, vm:0, base:0, bound:'1});

    // Registers for hardware pagetable walk
    Reg#(Bool) walking <- mkReg(False);
    Reg#(Bool) store <- mkReg(False);
    Reg#(Bool) supervisor <- mkReg(False);
    Reg#(Addr) a <- mkReg(0);
    Reg#(Bit#(2)) i <- mkReg(0);
    Reg#(Bit#(64)) pte <- mkReg(0);
    Reg#(Vector#(3,Bit#(9))) vpn <- mkReg(replicate(0));
    Reg#(Bit#(12)) pageoffset <- mkReg(0);

    // if the response from main memory is for a write, drop it
    // XXX: this does not work if mainMemory has a synthesize boundary
    rule ignoreWriteResps;
        let _x <- mainMemory.response.get();
        when(_x.write == True, noAction);
    endrule

    rule doPageTableWalk(walking);
        let memResp <- mainMemory.response.get();
        when(memResp.write == False, noAction);

        PTE_Sv39 pte = unpack(memResp.data);
        Maybe#(ExceptionCause) accessFault = tagged Valid (isInst ? InstAccessFault :
                                                            (store ? StoreAccessFault :
                                                                LoadAccessFault));
        if (!pte.valid) begin
            // invalid page, access fault
            procMMUResp.enq(RVDMMUResp{addr: 0, exception: accessFault});
            walking <= False;
        end else if (is_leaf_pte_type(pte.pte_type)) begin
            // valid leaf page

            // check page permissions
            Bool hasPermission = False;
            if (isInst) begin
                hasPermission = supervisor ? pte.pte_type.s_x : pte.pte_type.u_x;
            end else if (store) begin
                hasPermission = supervisor ? pte.pte_type.s_w : pte.pte_type.u_w;
            end else begin
                hasPermission = supervisor ? pte.pte_type.s_r : pte.pte_type.u_r;
            end

            if (!hasPermission) begin
                // illegal, access fault
                procMMUResp.enq(RVDMMUResp{addr: 0, exception: accessFault});
                walking <= False;
            end else begin
                // legal, return translation
                Addr paddr = '1;
                if (i == 0) begin
                    paddr = {0, pte.ppn2, pte.ppn1, pte.ppn0, pageoffset};
                end else if (i == 1) begin
                    paddr = {0, pte.ppn2, pte.ppn1, vpn[0], pageoffset};
                end else if (i == 2) begin
                    paddr = {0, pte.ppn2, vpn[1], vpn[0], pageoffset};
                end
                procMMUResp.enq(RVDMMUResp{addr: paddr, exception: tagged Invalid});
                walking <= False;
                if (!pte.r || (store && !pte.d)) begin
                    // write back necessary
                    // update pte
                    pte.r = True;
                    if (store) begin
                        pte.d = True;
                    end
                    // send write request
                    mainMemory.request.put(MainMemoryReq{write: True, byteen: '1, addr: a, data: pack(pte), tag: ? });
                end
            end
        end else if (i != 0) begin
            // go to next level
            Addr newA = {0, pte.ppn2, pte.ppn1, pte.ppn0, 12'b0} + (zeroExtend(vpn[i-1]) << 3);
            mainMemory.request.put(MainMemoryReq{write: False, byteen: '1, addr: newA, data: ?, tag: ?});
            a <= newA;
            i <= i - 1;
        end else begin
            // non-leaf page at lowest level, access fault
            procMMUResp.enq(RVDMMUResp{addr: 0, exception: accessFault});
            walking <= False;
        end
    endrule

    rule doTranslate(!walking);
        // let {addr: .vaddr, op: .op} = procMMUReq.first;
        let vaddr = procMMUReq.first.addr;
        let size = procMMUReq.first.size;
        let op = procMMUReq.first.op;
        procMMUReq.deq;

        Bool isStore = (op == St || op == Sc || op == PrefetchForSt);
        Bool isSupervisor = vmInfo.prv == prvS;
        Bool pageTableWalk = False;

        Addr paddr = 0;
        Maybe#(ExceptionCause) exception = tagged Invalid;
        Maybe#(ExceptionCause) accessFault = tagged Valid (isInst ? InstAccessFault :
                                                            (isStore ? StoreAccessFault :
                                                                LoadAccessFault));
        Maybe#(ExceptionCause) misalignedFault = tagged Valid (isInst ? InstAddrMisaligned :
                                                            (isStore ? StoreAddrMisaligned :
                                                                LoadAddrMisaligned));
        Bit#(3) alignmentBits = (case(size)
                D:       3'b111;
                W, WU:   3'b011;
                H, HU:   3'b001;
                B, BU:   3'b000;
                default: 3'b111;
            endcase);
        if ((truncate(vaddr) & alignmentBits) != 0) begin
            exception = misalignedFault;
        end else if (vmInfo.prv == prvM) begin
            paddr = vaddr;
        end else begin
            case (vmInfo.vm)
                vmMbare:        paddr = vaddr;
                vmMbb, vmMbbid: begin
                                    if (vaddr > vmInfo.bound) begin
                                        exception = accessFault;
                                    end else begin
                                        paddr = vaddr + vmInfo.base;
                                    end
                                end
                vmSv39: begin
                            // start page table walk
                            // Addr newA = vmInfo.base + (zeroExtend(vpn[2]) << 3);
                            Vector#(3, Bit#(9)) newvpn = unpack(vaddr[38:12]);
                            Addr newA = vmInfo.base + (zeroExtend(newvpn[2]) << 3);
                            mainMemory.request.put(MainMemoryReq{write: False, byteen: '1, addr: newA, data: ?, tag: ? });
                            walking <= True;
                            pageTableWalk = True;
                            a <= newA;
                            i <= 2;
                            vpn <= newvpn;
                            pageoffset <= truncate(vaddr);
                            store <= isStore;
                            supervisor <= isSupervisor;
                        end
                default:
                    // unsupported virtual addressing mode
                    exception = accessFault;
            endcase
        end

        if (!pageTableWalk) begin
            procMMUResp.enq(RVDMMUResp{addr: paddr, exception: exception});
        end
    endrule

    interface Put request;
        method Action put(RVDMMUReq r);
            procMMUReq.enq(r);
        endmethod
    endinterface
    interface Get response;
        method ActionValue#(RVDMMUResp) get;
            procMMUResp.deq;
            return procMMUResp.first;
        endmethod
    endinterface
    method Action updateVMInfo(VMInfo vm);
        vmInfo <= vm;
    endmethod
endmodule

