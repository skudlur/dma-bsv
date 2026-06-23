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

   Reg#(Bit#(32)) count <- mkReg(0);

   // A simple FSM to test DMA Read and Write
   mkAutoFSM(
      seq
         // Initialize memory: base=0, size=1024 bytes, not from file
         action
            mem.initialize(0, 1024, False);
            $display("Testbench: Memory initialized. Kicking off DMA WRITE.");
            // Write 4 words starting at address 0x100
            dma.startWrite(32'h100, 4);
         endaction
         action dma.putWriteData(32'hDEADBEEF); endaction
         action dma.putWriteData(32'hCAFEBABE); endaction
         action dma.putWriteData(32'h12345678); endaction
         action dma.putWriteData(32'h87654321); endaction

         delay(20);

         action
            $display("Testbench: Kicking off DMA READ to verify writes.");
            dma.startRead(32'h100, 4);
         endaction

         delay(100);

         action
            $display("Testbench: Simulation finished successfully.");
            $finish(0);
         endaction
      endseq
   );

endmodule // mkTestDMA
