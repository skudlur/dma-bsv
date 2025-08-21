import DMA::*;
import Memory_Model::*;
import ClientServer::*;
import StmtFSM::*;

typedef 64 ADDR_WIDTH;
typedef 64 DATA_WIDTH;

module mkTestDMA();
   DMA_Ifc dma <- mkDMA();

   Reg#(Bool) started <- mkReg(False);
   rule read_test (!started);
      dma.startRead(32'h1000, 16);
      started <= True;
      $display("Testbench: Kicking off DMA read.");
   endrule

endmodule // mkTestDMA
