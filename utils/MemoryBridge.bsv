package MemoryBridge;

import FIFOF::*;
import DMA::*;
import ClientServer::*;
import GetPut::*;
import Req_Rsp::*;
import Memory_Model::*;

typedef Req_T  MemReq;
typedef Rsp_T  MemRsp;

module mkMemoryBridge#(
    DMAMemory_Master_Ifc dma,
    Server#(MemReq, MemRsp) mem
) (Empty);

   FIFOF#(MemReq) req_fifo <- mkFIFOF();
   FIFOF#(MemRsp) rsp_fifo <- mkFIFOF();
   
   Reg#(Maybe#(Bit#(32))) rg_aw_addr <- mkReg(tagged Invalid);

   rule connect_req_to_mem;
      let req = req_fifo.first;
      req_fifo.deq;
      mem.request.put(req);
   endrule

   rule connect_rsp_from_mem;
      let rsp <- mem.response.get();
      rsp_fifo.enq(rsp);
   endrule

   rule drive_ready;
      dma.ar_ready(req_fifo.notFull);
      dma.aw_ready(rg_aw_addr == tagged Invalid);
      dma.w_ready(rg_aw_addr != tagged Invalid && req_fifo.notFull);
   endrule

   rule drive_ar (dma.ar_valid() && req_fifo.notFull);
      let req = Req {
         command: READ,
         addr: extend(dma.ar_addr()),
         data: 0,
         b_size: BITS32,
         tid: 0
      };
      req_fifo.enq(req);
   endrule

   rule drive_aw (rg_aw_addr == tagged Invalid && dma.aw_valid());
      rg_aw_addr <= tagged Valid dma.aw_addr();
   endrule

   rule drive_w (rg_aw_addr matches tagged Valid .addr &&& dma.w_valid() &&& req_fifo.notFull);
      let req = Req {
         command: WRITE,
         addr: extend(addr),
         data: extend(dma.w_data()),
         b_size: BITS32,
         tid: 0
      };
      req_fifo.enq(req);
      rg_aw_addr <= tagged Invalid;
   endrule

   rule drive_responses;
      let is_valid = rsp_fifo.notEmpty;
      let cmd = is_valid ? rsp_fifo.first.command : UNKNOWN;
      
      let r_valid = is_valid && (cmd == READ);
      let b_valid = is_valid && (cmd == WRITE);

      let data = is_valid ? truncate(rsp_fifo.first.data) : 0;
      
      dma.r_put(data, r_valid);
      dma.b_put(0, b_valid);

      if (r_valid && dma.r_ready()) begin
         rsp_fifo.deq;
      end else if (b_valid && dma.b_ready()) begin
         rsp_fifo.deq;
      end
   endrule

endmodule

endpackage
