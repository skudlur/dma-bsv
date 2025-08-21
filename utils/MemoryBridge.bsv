import FIFOF::*;

interface

module mkMemoryBridge();
   rule dma_addr_req_to_mem_req;

   endrule

   rule mem_resp_to_bridge_fifo;

   endrule

   rule bridge_fifo_to_dma_resp;

   endrule
endmodule
