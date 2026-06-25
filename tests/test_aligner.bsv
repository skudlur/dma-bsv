import DMA::*;
import Memory_Model::*;
import MemoryBridge::*;
import ClientServer::*;
import StmtFSM::*;
import DMA_WidthAdapter::*;
import DMA_ByteAligner::*;
import Req_Rsp::*;

module mkTestDMA();
   Memory_IFC mem <- mkMemory_Model();
   
   DMA_Ifc#(64, 32) core <- mkDMA_32_to_64();
   DMA_ByteAligner_Ifc#(32) aligner <- mkDMA_ByteAligner(core);
   let bridge <- mkMemoryBridge(aligner.mem_ifc, mem.bus_ifc[0]);

   mkAutoFSM(
      seq
         delay(10);
         action
            mem.initialize(0, 4096, False);
         endaction
         
         // Unaligned Write Test
         action
            $display("Testbench: Starting Unaligned Write (5 bytes at 0x101)");
            aligner.startWrite(32'h101, 5);
         endaction
         
         action
            aligner.putWriteData(32'h44332211);
         endaction
         
         action
            aligner.putWriteData(32'h88776655);
         endaction
         
         action
            let b <- aligner.getWriteResp();
            $display("Testbench: Unaligned Write complete");
         endaction
         
         action
            let d1 <- mem.debug_load(64'h100, BITS64);
            $display("Mem[0x100] = %h", d1);
            if (d1 == 64'h0706554433221100) $display("SUCCESS: Write data matched!");
            else $display("ERROR: Write data mismatch!");
         endaction

         // Unaligned Read Test
         action
            $display("Testbench: Starting Unaligned Read (5 bytes from 0x101)");
            aligner.startRead(32'h101, 5);
         endaction
         
         action
            let r1 <- aligner.getReadData();
            $display("Read Word 1: %h", r1);
            if (r1 == 32'h44332211) $display("SUCCESS: Read Word 1 matched!");
            else $display("ERROR: Read Word 1 mismatch!");
         endaction
         
         action
            let r2 <- aligner.getReadData();
            $display("Read Word 2: %h", r2);
            if (r2 == 32'h00000055) $display("SUCCESS: Read Word 2 matched!");
            else $display("ERROR: Read Word 2 mismatch!");
         endaction
         
         $finish(0);
      endseq
   );
endmodule
