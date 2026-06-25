package MemoryBridge;

import FIFOF::*;
import DMA::*;
import ClientServer::*;
import GetPut::*;
import Req_Rsp::*;
import LFSR::*;
import Memory_Model::*;

typedef Req_T  MemReq;
typedef Rsp_T  MemRsp;

module mkMemoryBridge#(
    DMAMemory_Master_Ifc#(64) dma,
    Server#(MemReq, MemRsp) mem
) (Empty);

   FIFOF#(Tuple2#(Bit#(32), Bit#(8))) ar_fifo <- mkSizedFIFOF(4);
   FIFOF#(Tuple2#(Bit#(32), Bit#(8))) aw_fifo <- mkSizedFIFOF(4);

   FIFOF#(MemReq) req_fifo <- mkSizedFIFOF(16);
   FIFOF#(MemRsp) rsp_fifo <- mkSizedFIFOF(16);

   Reg#(Bit#(8))  rg_br_len  <- mkReg(0);
   Reg#(Bit#(32)) rg_br_addr <- mkReg(0);
   FIFOF#(Bit#(8)) bridge_req_fifo <- mkSizedFIFOF(16);

`ifdef BACKPRESSURE
   LFSR#(Bit#(16)) lfsr <- mkLFSR_16();
   Reg#(Bool) lfsr_started <- mkReg(False);
   rule start_lfsr (!lfsr_started);
      lfsr.seed(16'h5A5A);
      lfsr_started <= True;
   endrule
   rule tick_lfsr (lfsr_started);
      lfsr.next();
   endrule
`endif
   Reg#(Bit#(8))  rg_r_resp_count <- mkReg(0);

   Reg#(Bit#(8))  rg_bw_len  <- mkReg(0);
   Reg#(Bit#(32)) rg_bw_addr <- mkReg(0);
   FIFOF#(Bit#(8)) b_len_fifo <- mkSizedFIFOF(16);
   Reg#(Bit#(8))  rg_b_resp_count <- mkReg(0);

   rule accept_ar (dma.ar_valid() && ar_fifo.notFull);
      ar_fifo.enq(tuple2(dma.ar_addr(), dma.ar_len() + 1));
   endrule

   rule accept_aw (dma.aw_valid() && aw_fifo.notFull);
      aw_fifo.enq(tuple2(dma.aw_addr(), dma.aw_len() + 1));
   endrule

   rule forward_requests;
      let req = req_fifo.first;
      req_fifo.deq;
      mem.request.put(req);
   endrule

   rule forward_responses;
      let rsp <- mem.response.get();
      rsp_fifo.enq(rsp);
   endrule

   rule drive_ready;
      dma.ar_ready(ar_fifo.notFull);
      dma.aw_ready(aw_fifo.notFull);
`ifdef BACKPRESSURE
      dma.w_ready(rg_bw_len > 0 && req_fifo.notFull && lfsr_started && lfsr.value[0] == 1);
`else
      dma.w_ready(rg_bw_len > 0 && req_fifo.notFull);
`endif
   endrule

   // ------------------------------------------
   // READ BURST UNPACKING
   // ------------------------------------------
   rule load_ar (rg_br_len == 0 && ar_fifo.notEmpty);
      let t = ar_fifo.first;
      ar_fifo.deq;
      rg_br_addr <= tpl_1(t);
      rg_br_len  <= tpl_2(t);
      bridge_req_fifo.enq(tpl_2(t));
   endrule

   rule issue_ar_req (rg_br_len > 0 && req_fifo.notFull);
      MemReq req = Req {
         command: READ,
         addr: extend(rg_br_addr & ~32'h7),
         data: 0,
         wstrb: '0,
         b_size: BITS64,
         tid: 0
      };
      req_fifo.enq(req);
      rg_br_addr <= (rg_br_addr & ~32'h7) + 8;
      rg_br_len  <= rg_br_len - 1;
   endrule

   // ------------------------------------------
   // WRITE BURST UNPACKING
   // ------------------------------------------
   rule load_aw (rg_bw_len == 0 && aw_fifo.notEmpty);
      let t = aw_fifo.first;
      aw_fifo.deq;
      rg_bw_addr <= tpl_1(t);
      rg_bw_len  <= tpl_2(t);
      b_len_fifo.enq(tpl_2(t));
   endrule

   rule issue_aw_w_req;
`ifdef BACKPRESSURE
      if (rg_bw_len > 0 && dma.w_valid() && req_fifo.notFull && lfsr_started && lfsr.value[0] == 1) begin
`else
      if (rg_bw_len > 0 && dma.w_valid() && req_fifo.notFull) begin
`endif
         MemReq req = Req {
            command: WRITE,
            addr: extend(rg_bw_addr & ~32'h7),
            data: extend(dma.w_data()), // w_data is already 64-bit, but extend is safe
            wstrb: dma.w_strb(),
            b_size: BITS64,
            tid: 0
         };
         req_fifo.enq(req);
         rg_bw_addr <= (rg_bw_addr & ~32'h7) + 8;
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

`ifdef BACKPRESSURE
   rule drive_read_responses (rsp_fifo.notEmpty && rsp_fifo.first.command == READ && lfsr_started && lfsr.value[1] == 1);
`else
   rule drive_read_responses (rsp_fifo.notEmpty && rsp_fifo.first.command == READ);
`endif
      let rsp = rsp_fifo.first;
      let data = rsp.data;
      let count = rg_r_resp_count;
      if (count == 0) begin
         count = bridge_req_fifo.first;
      end

      let r_last = (count == 1);
      dma.r_put(data, r_last, True);

      if (dma.r_ready()) begin
         rsp_fifo.deq;
         if (r_last) begin
            rg_r_resp_count <= 0;
            bridge_req_fifo.deq;
         end else begin
            rg_r_resp_count <= count - 1;
         end
      end
   endrule

endmodule

endpackage
