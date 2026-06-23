import DMA::*;
import Memory_Model::*;
import MemoryBridge::*;
import ClientServer::*;
import StmtFSM::*;

typedef 64 ADDR_WIDTH;
typedef 64 DATA_WIDTH;

module mkTestDMA();
   // Instantiate memory model
   Memory_IFC mem <- mkMemory_Model();

   // Instantiate DMA
   DMA_Ifc dma <- mkDMA();

   // Instantiate bridge
   let bridge <- mkMemoryBridge(dma.mem_ifc, mem.bus_ifc[0]);

   Reg#(Bool) started <- mkReg(False);
   Reg#(Bit#(32)) count <- mkReg(0);

   rule init_and_start (!started);
      // Initialize memory: base=0, size=1024 bytes, not from file
      mem.initialize(0, 1024, False);
      dma.startRead(32'h0, 4); // read 4 words
      started <= True;
      $display("Testbench: Memory initialized. Kicking off DMA read.");
   endrule

   rule finish_test (started);
      count <= count + 1;
      // Provide a timeout for the test to ensure it finishes
      if (count > 50) begin
         $display("Testbench: Simulation finished.");
         $finish(0);
      end
   endrule

endmodule // mkTestDMA
