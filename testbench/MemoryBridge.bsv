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
    DMAMemory_Master_Ifc#(64) dma,
    Server#(MemReq, MemRsp) mem
) (Empty);

   FIFOF#(MemReq) req_fifo <- mkSizedFIFOF(16);
   FIFOF#(MemRsp) rsp_fifo <- mkSizedFIFOF(16);

   Reg#(Bit#(8))  rg_br_len  <- mkReg(0);
   Reg#(Bit#(32)) rg_br_addr <- mkReg(0);
   FIFOF#(Bit#(8)) r_len_fifo <- mkFIFOF();
   Reg#(Bit#(8))  rg_r_resp_count <- mkReg(0);

   Reg#(Bit#(8))  rg_bw_len  <- mkReg(0);
   Reg#(Bit#(32)) rg_bw_addr <- mkReg(0);
   FIFOF#(Bit#(8)) b_len_fifo <- mkFIFOF();
   Reg#(Bit#(8))  rg_b_resp_count <- mkReg(0);

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
      dma.ar_ready(rg_br_len == 0);
      dma.aw_ready(rg_bw_len == 0);
      dma.w_ready(rg_bw_len > 0 && req_fifo.notFull);
   endrule

   // ------------------------------------------
   // READ BURST UNPACKING
   // ------------------------------------------
   rule drive_ar (rg_br_len == 0);
      if (dma.ar_valid()) begin
         rg_br_addr <= dma.ar_addr();
         let len = dma.ar_len() + 1;
         rg_br_len  <= len;
         r_len_fifo.enq(len);
      end
   endrule

   rule issue_ar_req (rg_br_len > 0 && req_fifo.notFull);
      MemReq req = Req {
         command: READ,
         addr: extend(rg_br_addr),
         data: 0,
         b_size: BITS64,
         tid: 0
      };
      req_fifo.enq(req);
      rg_br_addr <= rg_br_addr + 8;
      rg_br_len  <= rg_br_len - 1;
   endrule

   // ------------------------------------------
   // WRITE BURST UNPACKING
   // ------------------------------------------
   rule drive_aw (rg_bw_len == 0);
      if (dma.aw_valid()) begin
         rg_bw_addr <= dma.aw_addr();
         let len = dma.aw_len() + 1;
         rg_bw_len  <= len;
         b_len_fifo.enq(len);
      end
   endrule

   // debug rule removed

   rule issue_aw_w_req;
      if (rg_bw_len > 0 && dma.w_valid() && req_fifo.notFull) begin
         MemReq req = Req {
            command: WRITE,
            addr: extend(rg_bw_addr),
            data: extend(dma.w_data()), // w_data is already 64-bit, but extend is safe
            b_size: BITS64,
            tid: 0
         };
         req_fifo.enq(req);
         rg_bw_addr <= rg_bw_addr + 8;
         rg_bw_len  <= rg_bw_len - 1;
      end
   endrule

   // ------------------------------------------
   // RESPONSES
   // ------------------------------------------
   rule drive_write_responses (rsp_fifo.notEmpty && rsp_fifo.first.command == WRITE);
      let rsp = rsp_fifo.first;
      let count = rg_b_resp_count;
      if (count == 0) begin
         count = b_len_fifo.first;
      end

      let b_last = (count == 1);
      dma.b_put(0, b_last);

      if (!b_last || (b_last && dma.b_ready())) begin
         rsp_fifo.deq;
         if (b_last) begin
            rg_b_resp_count <= 0;
            b_len_fifo.deq;
         end else begin
            rg_b_resp_count <= count - 1;
         end
      end
   endrule

   rule drive_read_responses (rsp_fifo.notEmpty && rsp_fifo.first.command == READ);
      let rsp = rsp_fifo.first;
      let data = rsp.data;
      let count = rg_r_resp_count;
      if (count == 0) begin
         count = r_len_fifo.first;
      end

      let r_last = (count == 1);
      dma.r_put(data, r_last, True);

      if (dma.r_ready()) begin
         rsp_fifo.deq;
         if (r_last) begin
            rg_r_resp_count <= 0;
            r_len_fifo.deq;
         end else begin
            rg_r_resp_count <= count - 1;
         end
      end
   endrule

endmodule

endpackage
