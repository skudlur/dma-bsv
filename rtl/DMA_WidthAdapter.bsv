package DMA_WidthAdapter;

import DMA::*;
import Gearbox::*;

module mkDMA_32_to_64 (DMA_Ifc#(64, 32));
   
   DMA_Ifc#(64, 64) core <- mkDMA();
   
   Gearbox#(32, 64) w_gb <- mkUpSizer();
   Gearbox#(4, 8) strb_gb <- mkUpSizer();
   Gearbox#(64, 32) r_gb <- mkDownSizer();
   
   rule push_to_core_w;
      let d <- w_gb.deq();
      let s <- strb_gb.deq();
      core.putWriteData(d, s);
   endrule
   
   rule pull_from_core_r;
      let d <- core.getReadData();
      r_gb.enq(d);
   endrule

   method Action startRead(Bit#(32) addr, Bit#(8) len);
      // len represents beats-1
      // For 32-bit to 64-bit, we divide the number of beats by 2.
      // (len + 1) / 2 - 1  ==  len >> 1
      core.startRead(addr, len >> 1);
   endmethod
   
   method Action startWrite(Bit#(32) addr, Bit#(8) len);
      core.startWrite(addr, len >> 1);
   endmethod
   
   method Action putWriteData(Bit#(32) data, Bit#(4) strb);
      w_gb.enq(data);
      strb_gb.enq(strb);
   endmethod
   
   method ActionValue#(Bit#(32)) getReadData();
      let d <- r_gb.deq();
      return d;
   endmethod
   
   method ActionValue#(Bool) getWriteResp();
      let b <- core.getWriteResp();
      return b;
   endmethod
   
   interface mem_ifc = core.mem_ifc;
   
endmodule

endpackage
