import DMA::*;
import Memory_Model::*;
import MemoryBridge::*;
import ClientServer::*;
import StmtFSM::*;
import DMA_WidthAdapter::*;

typedef 64 ADDR_WIDTH;
typedef 64 DATA_WIDTH;

module mkTestDMA();
   // Instantiate memory model
   Memory_IFC mem <- mkMemory_Model();

   // Instantiate DMA
   DMA_Ifc#(64, 32) dma <- mkDMA_32_to_64();

   // Instantiate bridge
   let bridge <- mkMemoryBridge(dma.mem_ifc, mem.bus_ifc[0]);

   Reg#(Bit#(32)) cycle_count <- mkReg(0);
   rule count_cycles;
      cycle_count <= cycle_count + 1;
   endrule

   Reg#(Bit#(32)) words_to_write <- mkReg(0);
   rule push_write_data (words_to_write > 0);
      dma.putWriteData(extend(words_to_write));
      words_to_write <= words_to_write - 1;
   endrule

   Reg#(Bit#(32)) words_to_read <- mkReg(0);
   Reg#(Bit#(32)) read_start_cycle <- mkReg(0);

   rule pop_read_data (words_to_read > 0);
      let d <- dma.getReadData();
      if (words_to_read == 1) begin
         $display("Read Throughput: 254 words in %0d cycles", cycle_count - read_start_cycle);
      end
      words_to_read <= words_to_read - 1;
   endrule

   Reg#(Bit#(32)) write_start_cycle <- mkReg(0);

   mkAutoFSM(
      seq
         action
            mem.initialize(0, 4096, False);
            $display("Testbench: Memory initialized. Kicking off DMA WRITE.");
            write_start_cycle <= cycle_count;
            words_to_write <= 254;
            dma.startWrite(32'h100, 255); // 255 >> 1 = 127. 127 beats of 64-bit = 254 words
         endaction

         action
            let b <- dma.getWriteResp();
            $display("Write Throughput: 254 words in %0d cycles", cycle_count - write_start_cycle);
         endaction

         delay(20);

         action
            $display("Testbench: Kicking off DMA READ to verify writes.");
            read_start_cycle <= cycle_count;
            words_to_read <= 254;
            dma.startRead(32'h100, 255);
         endaction

         await(words_to_read == 0);

         action
            $display("Testbench: Simulation finished successfully.");
            $finish(0);
         endaction
      endseq
   );

endmodule // mkTestDMA
