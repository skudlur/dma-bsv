import DMA::*;

module mkTestDMA();
   DMA_Ifc dma <- mkDMA();

   Reg#(Bool) started <- mkReg(False);

   rule do_the_test (!started);
      dma.startRead(32'h1000, 16);
      started <= True;
      $display("Testbench: Kicking off DMA read.");
   endrule

endmodule // mkTestDMA
