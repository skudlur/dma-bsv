/*
 * ScatterGatherEngine.bsv
 * 
 * Hardware linked-list descriptor processor.
 * Fetches 4-word descriptors from memory and executes the specified DMA
 * transfers (Read or Write) autonomously until reaching a null pointer.
 */
package ScatterGatherEngine;

import FIFOF::*;
import DMA::*;

typedef enum {
   IDLE,
   FETCH_REQ,
   FETCH_DATA,
   EXECUTE_REQ,
   EXECUTE_WAIT_WRITE,
   EXECUTE_WAIT_READ,
   NEXT_DESC
} SG_State deriving (Bits, Eq, FShow);

typedef struct {
   Bit#(32) next_desc_ptr;
   Bit#(32) mem_addr;
   Bit#(32) length;
   Bit#(32) control;
} Descriptor deriving(Bits, Eq, FShow);

interface SG_DMA_Ifc#(numeric type mem_width, numeric type stream_width);
   method Action startChain(Bit#(32) first_desc_addr);
   method Bool isDone();
   
   method Action putWriteData(Bit#(stream_width) data, Bit#(TDiv#(stream_width, 8)) strb);
   method ActionValue#(Bit#(stream_width)) getReadData();
   
   interface DMAMemory_Master_Ifc#(mem_width) mem_ifc;
endinterface

// mkScatterGatherEngine
// Wraps a raw DMA interface to provide linked-list autonomous capabilities.
module mkScatterGatherEngine#(DMA_Ifc#(mem_width, stream_width) dma)(SG_DMA_Ifc#(mem_width, stream_width))
   provisos (
      Add#(a__, 32, stream_width)
   );

   Reg#(SG_State) state <- mkReg(IDLE);
   Reg#(Bit#(32)) current_desc_addr <- mkReg(0);
   Reg#(Descriptor) current_desc <- mkRegU;
   
   Reg#(Bit#(2)) fetch_word_count <- mkReg(0);
   Reg#(Bit#(32)) payload_word_count <- mkReg(0);
   
   FIFOF#(Bit#(stream_width)) user_read_fifo <- mkFIFOF();
   FIFOF#(Tuple2#(Bit#(stream_width), Bit#(TDiv#(stream_width, 8)))) user_write_fifo <- mkFIFOF();
   
   rule rl_fetch_req (state == FETCH_REQ);
      // Request 4 words (16 bytes). length parameter is words
      dma.startRead(current_desc_addr, 4);
      state <= FETCH_DATA;
      fetch_word_count <= 0;
   endrule
   
   rule rl_fetch_data (state == FETCH_DATA);
      let d <- dma.getReadData();
      Bit#(32) word32 = truncate(d);
      
      Descriptor desc = current_desc;
      if (fetch_word_count == 0) desc.next_desc_ptr = word32;
      else if (fetch_word_count == 1) desc.mem_addr = word32;
      else if (fetch_word_count == 2) desc.length = word32;
      else if (fetch_word_count == 3) desc.control = word32;
      
      current_desc <= desc;
      
      if (fetch_word_count == 3) begin
         state <= EXECUTE_REQ;
      end
      fetch_word_count <= fetch_word_count + 1;
   endrule
   
   rule rl_execute_req (state == EXECUTE_REQ);
      let is_write = (current_desc.control[0] == 1);
      payload_word_count <= current_desc.length;
      
      if (is_write) begin
         dma.startWrite(current_desc.mem_addr, truncate(current_desc.length));
         state <= EXECUTE_WAIT_WRITE;
      end else begin
         dma.startRead(current_desc.mem_addr, truncate(current_desc.length));
         state <= EXECUTE_WAIT_READ;
      end
   endrule
   
   rule rl_route_write (state == EXECUTE_WAIT_WRITE);
      let t = user_write_fifo.first;
      user_write_fifo.deq;
      dma.putWriteData(tpl_1(t), tpl_2(t));
   endrule
   
   rule rl_wait_write_resp (state == EXECUTE_WAIT_WRITE);
      let b <- dma.getWriteResp();
      state <= NEXT_DESC;
   endrule
   
   rule rl_route_read (state == EXECUTE_WAIT_READ);
      let d <- dma.getReadData();
      user_read_fifo.enq(d);
      
      if (payload_word_count == 1) begin
         state <= NEXT_DESC;
      end
      payload_word_count <= payload_word_count - 1;
   endrule
   
   rule rl_next_desc (state == NEXT_DESC);
      if (current_desc.next_desc_ptr == 0) begin
         state <= IDLE;
      end else begin
         current_desc_addr <= current_desc.next_desc_ptr;
         state <= FETCH_REQ;
      end
   endrule

   method Action startChain(Bit#(32) first_desc_addr) if (state == IDLE);
      current_desc_addr <= first_desc_addr;
      state <= FETCH_REQ;
   endmethod
   
   method Bool isDone();
      return (state == IDLE);
   endmethod
   
   method Action putWriteData(Bit#(stream_width) data, Bit#(TDiv#(stream_width, 8)) strb);
      user_write_fifo.enq(tuple2(data, strb));
   endmethod
   
   method ActionValue#(Bit#(stream_width)) getReadData();
      let d = user_read_fifo.first;
      user_read_fifo.deq;
      return d;
   endmethod
   
   interface mem_ifc = dma.mem_ifc;
endmodule

endpackage
