package MemoryBridge;

import FIFOF::*;
import DMA::*;
import ClientServer::*;
import GetPut::*;
import Req_Rsp::*;
import Memory_Model::*;

typedef Req_T  MemReq;
typedef Rsp_T  MemRsp;

// Connects DMA Master Interface to Memory Server Interface
module mkMemoryBridge#(
    DMAMemory_Master_Ifc dma,
    Server#(MemReq, MemRsp) mem
) (Empty);

   // Internal FIFOs to buffer Memory requests and responses
   FIFOF#(MemReq) req_fifo <- mkFIFOF();
   FIFOF#(MemRsp) rsp_fifo <- mkFIFOF();

   rule connect_req_to_mem;
      let req = req_fifo.first;
      req_fifo.deq;
      mem.request.put(req);
   endrule

   rule connect_rsp_from_mem;
      let rsp <- mem.response.get();
      rsp_fifo.enq(rsp);
   endrule

   // DMA Read Channel
   rule drive_ar;
      dma.ar_ready(req_fifo.notFull);
      if (dma.ar_valid() && req_fifo.notFull) begin
         let req = Req {
            command: READ,
            addr: extend(dma.ar_addr()),
            data: 0,
            b_size: BITS32,
            tid: 0
         };
         req_fifo.enq(req);
      end
   endrule

   rule drive_r;
      let valid = rsp_fifo.notEmpty && dma.r_ready();
      let data  = valid ? rsp_fifo.first.data : 0;
      dma.r_put(truncate(data), rsp_fifo.notEmpty);
      if (rsp_fifo.notEmpty && dma.r_ready()) begin
         rsp_fifo.deq;
      end
   endrule

   // For write, we can add dummy handlers or proper translation if needed.
   rule drive_aw_w_b;
      dma.aw_ready(False);
      dma.w_ready(False);
      dma.b_put(0, False);
   endrule

endmodule

endpackage
