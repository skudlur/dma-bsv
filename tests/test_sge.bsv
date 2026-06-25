import DMA::*;
import Memory_Model::*;
import MemoryBridge::*;
import ClientServer::*;
import StmtFSM::*;
import DMA_WidthAdapter::*;
import ScatterGatherEngine::*;
import Req_Rsp::*;
import LFSR::*;
typedef 64 ADDR_WIDTH;
typedef 64 DATA_WIDTH;

module mkTestDMA();
   // Instantiate memory model
   Memory_IFC mem <- mkMemory_Model();

   // Instantiate DMA and SGE
   DMA_Ifc#(64, 32) dma <- mkDMA_32_to_64();
   SG_DMA_Ifc#(64, 32) sge <- mkScatterGatherEngine(dma);

   // Instantiate bridge
   let bridge <- mkMemoryBridge(sge.mem_ifc, mem.bus_ifc[0]);

   Reg#(Bit#(32)) cycle_count <- mkReg(0);
   rule count_cycles;
      cycle_count <= cycle_count + 1;
   endrule

   LFSR#(Bit#(16)) lfsr <- mkLFSR_16();
   rule tick_lfsr;
      lfsr.next();
   endrule

   Reg#(Bit#(32)) words_to_write <- mkReg(0);
   Reg#(Bit#(32)) words_to_read <- mkReg(0);
   Reg#(Bit#(32)) read_start_cycle <- mkReg(0);

   // 50% chance to push data
   rule push_write_data (words_to_write > 0 && lfsr.value[0] == 1);
      sge.putWriteData(extend(words_to_write), 4'b1111);
      words_to_write <= words_to_write - 1;
   endrule

   // 25% chance to pop data (creates heavy backpressure)
   rule pop_read_data (words_to_read > 0 && lfsr.value[2:1] == 2'b11);
      let d <- sge.getReadData();
      if (words_to_read == 1) begin
         $display("Read Throughput: %0d words in %0d cycles (with backpressure)", 4, cycle_count - read_start_cycle);
      end
      words_to_read <= words_to_read - 1;
   endrule

   mkAutoFSM(
      seq
         delay(10);
         action
            lfsr.seed(16'hA5A5);
            mem.initialize(0, 4096, False);
            $display("Testbench: Memory initialized. Writing descriptors...");
         endaction
         
         // Desc 1 at 0x00: Write 4 words to 0x100
         action mem.debug_store(64'h00, 64'h010, BITS32); endaction
         action mem.debug_store(64'h04, 64'h100, BITS32); endaction
         action mem.debug_store(64'h08, 64'h004, BITS32); endaction
         action mem.debug_store(64'h0c, 64'h001, BITS32); endaction
         
         // Desc 2 at 0x10: Write 6 words to 0x200
         action mem.debug_store(64'h10, 64'h020, BITS32); endaction
         action mem.debug_store(64'h14, 64'h200, BITS32); endaction
         action mem.debug_store(64'h18, 64'h006, BITS32); endaction
         action mem.debug_store(64'h1c, 64'h001, BITS32); endaction
         
         // Desc 3 at 0x20: Read 4 words from 0x100
         action mem.debug_store(64'h20, 64'h000, BITS32); endaction
         action mem.debug_store(64'h24, 64'h100, BITS32); endaction
         action mem.debug_store(64'h28, 64'h004, BITS32); endaction
         action mem.debug_store(64'h2c, 64'h000, BITS32); endaction
            
         action
            words_to_write <= 10; // 4 + 6
            words_to_read <= 4;
            read_start_cycle <= cycle_count; // Rough approximation
         endaction

         action
            $display("Testbench: Kicking off Scatter/Gather Chain.");
            sge.startChain(32'h000);
         endaction

         await(sge.isDone() && words_to_read == 0);
         $display("Testbench: Scatter/Gather Chain finished successfully.");
         
         $finish(0);
      endseq
   );

endmodule // mkTestDMA
