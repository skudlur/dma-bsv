package DMA;

import FIFO::*;

// Typedefs
typedef enum {
   IDLE,
   SEND_ADDR,
   READ_DATA
   } State deriving (Bits, Eq, FShow);

// DMA-Memory Interface
interface DMAMemory_IFC;
   // Methods for Address Read Channel
   method Action ar_put(Bit#(32) ar_addr);     // DMA sends address to memory bus and asserts valid
   method Bool   ar_isReady();                 // DMA checks if memory bus is ready

   // Methods for Data Read Channel
   method Bool      r_isValid();               // DMA reads the R_VALID signal from memory
   method Bit#(32)  r_data();                  // DMA reads the R_DATA bus from memory
   method Action    r_setReady();              // Drives the R_READY signal to memory

   // Methods for Address Write Channel
   method Action aw_put(Bit#(32) aw_addr);     // DMA sends address to memory bus and asserts valid
   method Bool   aw_isReady();                 // DMA checks if memory bus is ready

   // Methods for Data Write Channel
   method Action w_put(Bit#(32) w_data);       // DMA sends data to be written in memory
   method Bool   w_isReady();                  // DMA checks if memory is ready to write

   // Methods for Write Response Channel
   method Bool    b_isValid();                 // Memory sends valid write response
   method Bit#(2) b_resp();                    // Memory sends write status response
   method Action  b_setReady();                // Drives the B_READY signal to memory
endinterface

// Module
module mkDMA (DMAMemory_IFC);

   // State register
   Reg#(State) state <- mkRegA(IDLE);

   // Current address register
   Reg#(Bit#(32)) rg_cur_addr <- mkReg(0);

   // Read Length (number of reads)
   Reg#(UInt#(8)) rg_read_len <- mkReg(0);
endmodule // mkDMA

endpackage // DMA
