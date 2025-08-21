import FIFOF::*;
import DMA::*;
import ClientServer::*;
import Req_Rsp::*;

typedef Req_T  MemReq;
typedef Rsp_T  MemRsp;

`define ADDR_WIDTH 32


module mkMemoryBridge#(
    Client#(MemReq, MemRsp) mem_model_client
)
(
    DMAMemory_Ifc
);
   // --- INTERNAL STATE ---
   // The internal FIFOs for buffering requests and responses from the memory model
   FIFOF#(MemRsp) rsp_fifo <- mkFIFOF();
   FIFOF#(MemReq) req_fifo <- mkFIFOF();

   // --- RULES ---
   rule read_request(req_fifo.notEmpty && mem_model_client.request.notFull);
      let req = req_fifo.first;
      mem_model_client.request.put(req);
      req_fifo.deq;
   endrule

   rule read_response(mem_model_client.response.notEmpty && rsp_fifo.notFull);
      let resp = mem_model_client.response.first;
      rsp_fifo.enq(resp);
      mem_model_client.response.deq;
   endrule

   // --- INTERFACE IMPLEMENTATIONS ---
   interface DMAMemory_Ifc dma_side_ifc;

      method Action ar_put(Bit#(`ADDR_WIDTH) ar_addr);
         let req = Req {
               command: READ,
               addr: ar_addr,
               data: ?,
               b_size: BITS32,
               tid: 0 // TODO: simplify the memory model structs
            };
         req_fifo.enq(req);
      endmethod

      method Bool r_isValid();
         return rsp_fifo.notEmpty;
      endmethod

      method Bit#(32) r_data();
         return rsp_fifo.first.data;
      endmethod

      method Action r_setReady();
         rsp_fifo.deq;
      endmethod

      method Action aw_put(Bit#(`ADDR_WIDTH) aw_addr);
      endmethod

      method Bool aw_isReady();
         return wr_aw_ready;
      endmethod

      method Action w_put(Bit#(`ADDR_WIDTH) w_data);

      endmethod

      method Bool w_isReady();
         return wr_w_ready;
      endmethod

      method Bool b_isValid();
         return wr_w_valid;
      endmethod

      method Bit#(2) b_resp();
         return wr_b_resp;
      endmethod

      method Action b_setReady();
         wr_b_ready <= True;
      endmethod
    endinterface
endmodule
