import DMA::*;
import Memory_Model::*;
import MemoryBridge::*;
import ClientServer::*;
import StmtFSM::*;
import DMA_WidthAdapter::*;
import Req_Rsp::*;

typedef 64 ADDR_WIDTH;
typedef 64 DATA_WIDTH;

module mkTestDMA();
   Memory_IFC mem <- mkMemory_Model();
   DMA_Ifc#(64, 32) dma <- mkDMA_32_to_64();
   let bridge <- mkMemoryBridge(dma.mem_ifc, mem.bus_ifc[0]);

   Reg#(Bit#(32)) cycle_count <- mkReg(0);
   rule count_cycles;
      cycle_count <= cycle_count + 1;
   endrule

   Reg#(Bit#(32)) words_to_write <- mkReg(0);
   Reg#(Bit#(32)) words_to_read <- mkReg(0);
   Reg#(Bit#(32)) read_start_cycle <- mkReg(0);

   rule push_write_data (words_to_write > 0);
      dma.putWriteData(extend(words_to_write), 4'b1111);
      words_to_write <= words_to_write - 1;
   endrule

   rule pop_read_data (words_to_read > 0);
      let d <- dma.getReadData();
      if (words_to_read == 1) begin
         $display("Throughput: %0d words in %0d cycles", 254, cycle_count - read_start_cycle);
      end
      words_to_read <= words_to_read - 1;
   endrule

   mkAutoFSM(
      seq
         delay(10);
         action
            mem.initialize(0, 4096, False);
         endaction
         
         // Write test
         action
            words_to_write <= 254;
            dma.startWrite(32'h100, 254);
            $display("Testbench: Kicking off 254-word write DMA transfer");
         endaction

         await(words_to_write == 0);
         
         // Drain write responses
         action
            let b <- dma.getWriteResp();
            $display("Testbench: Write transfer complete");
         endaction

         // Read test
         action
            read_start_cycle <= cycle_count;
            words_to_read <= 254;
            dma.startRead(32'h100, 254);
            $display("Testbench: Kicking off 254-word read DMA transfer");
         endaction

         await(words_to_read == 0);
         $display("Testbench: Read transfer complete. Test finished.");
         $finish(0);
      endseq
   );

endmodule
