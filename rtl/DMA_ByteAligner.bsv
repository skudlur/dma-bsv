/*
 * DMA_ByteAligner.bsv
 * 
 * Intercepts unaligned requests (where addr doesn't match the word boundary)
 * and automatically manages byte-shifting and masked generation of write strobes 
 * to bridge the unaligned memory addresses seamlessly.
 */
package DMA_ByteAligner;

import FIFOF::*;
import DMA::*;
import GetPut::*;
import ClientServer::*;

interface DMA_ByteAligner_Ifc#(numeric type data_width);
   method Action startRead(Bit#(32) addr, Bit#(32) bytes);
   method Action startWrite(Bit#(32) addr, Bit#(32) bytes);
   method Action putWriteData(Bit#(data_width) data);
   method ActionValue#(Bit#(data_width)) getReadData();
   method ActionValue#(Bool) getWriteResp();
   interface DMAMemory_Master_Ifc#(64) mem_ifc;
endinterface

// mkDMA_ByteAligner
// Wraps around the 32-bit DMA interface, managing byte boundaries and offsets.
module mkDMA_ByteAligner#(DMA_Ifc#(64, 32) core)(DMA_ByteAligner_Ifc#(32));

   FIFOF#(Bit#(32)) user_write_fifo <- mkFIFOF();
   FIFOF#(Bit#(32)) user_read_fifo <- mkFIFOF();

   // Write State
   Reg#(Bit#(32)) rg_w_bytes_rem <- mkReg(0);
   Reg#(Bit#(2))  rg_w_offset <- mkReg(0);
   Reg#(Bit#(32)) rg_w_user_bytes_rem <- mkReg(0);
   Reg#(Bit#(64)) w_payload_reg <- mkReg(0);
   Reg#(Bit#(4))  w_payload_bytes <- mkReg(0);

   // Read State
   Reg#(Bit#(32)) rg_r_bytes_rem <- mkReg(0);
   Reg#(Bit#(2))  rg_r_offset <- mkReg(0);
   Reg#(Bit#(32)) rg_r_user_bytes_rem <- mkReg(0);
   Reg#(Bit#(64)) r_payload_reg <- mkReg(0);
   Reg#(Bit#(4))  r_payload_bytes <- mkReg(0);

   // ----------------------------------------------------
   // WRITE LOGIC
   // ----------------------------------------------------
   rule rl_accept_user_w (w_payload_bytes <= 4 && rg_w_user_bytes_rem > 0);
      let d = user_write_fifo.first;
      user_write_fifo.deq;
      Bit#(32) shift = extend(w_payload_bytes);
      shift = shift * 8;
      w_payload_reg <= w_payload_reg | (extend(d) << shift);
      w_payload_bytes <= w_payload_bytes + 4;
      
      if (rg_w_user_bytes_rem > 4) rg_w_user_bytes_rem <= rg_w_user_bytes_rem - 4;
      else rg_w_user_bytes_rem <= 0;
   endrule

   rule rl_feed_core_w (rg_w_bytes_rem > 0);
      Bit#(32) bytes_in_beat = 4 - extend(rg_w_offset);
      if (bytes_in_beat > rg_w_bytes_rem) bytes_in_beat = rg_w_bytes_rem;
      
      if (w_payload_bytes >= truncate(bytes_in_beat)) begin
         Bit#(32) chunk = truncate(w_payload_reg);
         Bit#(32) shift = extend(rg_w_offset);
         shift = shift * 8;
         Bit#(32) data = chunk << shift;
         Bit#(4) mask = (4'b0001 << bytes_in_beat) - 1;
         Bit#(4) strb = mask << rg_w_offset;
         
         core.putWriteData(data, strb);
         
         w_payload_reg <= w_payload_reg >> (bytes_in_beat * 8);
         w_payload_bytes <= w_payload_bytes - truncate(bytes_in_beat);
         
         rg_w_bytes_rem <= rg_w_bytes_rem - bytes_in_beat;
         rg_w_offset <= 0; // Align for subsequent beats
      end
   endrule

   // ----------------------------------------------------
   // READ LOGIC
   // ----------------------------------------------------
   rule rl_receive_core_r (rg_r_bytes_rem > 0);
      let d <- core.getReadData();
      
      Bit#(32) bytes_in_beat = 4 - extend(rg_r_offset);
      if (bytes_in_beat > rg_r_bytes_rem) bytes_in_beat = rg_r_bytes_rem;
      
      Bit#(32) shift = extend(rg_r_offset);
      shift = shift * 8;
      Bit#(32) chunk = d >> shift;
      Bit#(32) mask = (32'b1 << (bytes_in_beat * 8)) - 1;
      chunk = chunk & mask;
      
      Bit#(32) shift2 = extend(r_payload_bytes);
      shift2 = shift2 * 8;
      r_payload_reg <= r_payload_reg | (extend(chunk) << shift2);
      r_payload_bytes <= r_payload_bytes + truncate(bytes_in_beat);
      
      rg_r_bytes_rem <= rg_r_bytes_rem - bytes_in_beat;
      rg_r_offset <= 0;
   endrule
   
   rule rl_send_user_r (r_payload_bytes >= 4 || (r_payload_bytes > 0 && rg_r_bytes_rem == 0));
      if (rg_r_user_bytes_rem > 0) begin
         user_read_fifo.enq(truncate(r_payload_reg));
         r_payload_reg <= r_payload_reg >> 32;
         r_payload_bytes <= r_payload_bytes >= 4 ? r_payload_bytes - 4 : 0;
         rg_r_user_bytes_rem <= rg_r_user_bytes_rem > 4 ? rg_r_user_bytes_rem - 4 : 0;
      end
   endrule

   // ----------------------------------------------------
   // INTERFACE
   // ----------------------------------------------------
   method Action startRead(Bit#(32) addr, Bit#(32) bytes);
      rg_r_bytes_rem <= bytes;
      rg_r_offset <= truncate(addr[1:0]);
      rg_r_user_bytes_rem <= bytes;
      r_payload_bytes <= 0;
      r_payload_reg <= 0;
      
      Bit#(32) beats = (extend(addr[1:0]) + bytes + 3) / 4;
      core.startRead(addr, truncate(beats));
   endmethod
   
   method Action startWrite(Bit#(32) addr, Bit#(32) bytes);
      rg_w_bytes_rem <= bytes;
      rg_w_offset <= truncate(addr[1:0]);
      rg_w_user_bytes_rem <= bytes;
      w_payload_bytes <= 0;
      w_payload_reg <= 0;
      
      Bit#(32) beats = (extend(addr[1:0]) + bytes + 3) / 4;
      core.startWrite(addr, truncate(beats));
   endmethod
   
   method Action putWriteData(Bit#(32) data);
      user_write_fifo.enq(data);
   endmethod
   
   method ActionValue#(Bit#(32)) getReadData();
      let d = user_read_fifo.first;
      user_read_fifo.deq;
      return d;
   endmethod
   
   method ActionValue#(Bool) getWriteResp();
      let b <- core.getWriteResp();
      return b;
   endmethod
   
   interface mem_ifc = core.mem_ifc;

endmodule

endpackage
