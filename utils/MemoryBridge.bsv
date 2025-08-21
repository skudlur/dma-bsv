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

   Wire#(Bool)    wr_mb_ready <- mkWire();

   // --- RULES ---
   rule read_request(req_fifo.notEmpty);
      let req = req_fifo.first;
      if (mem_model_client.request.notFull) begin
         mem_model_client.request.put(req);
         req_fifo.deq;
      end
   endrule

   rule read_response(mem_model_client.response.notEmpty);
      let resp = mem_model_client.response.first;
      if (rsp_fifo.notFull) begin
         rsp_fifo.enq(resp);
         mem_model_client.response.deq;
      end
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
      method

      method Bool r_isValid();
         return rsp_fifo.notEmpty;
      endmethod

      method Bit#(32) r_data();
         return rsp_fifo.first.data;
      endmethod

      method Action r_setReady();
         rsp_fifo.deq;
      endmethod

    endinterface
endmodule
