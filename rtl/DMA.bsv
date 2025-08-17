package DMA;

// --- IMPORTS ---
import FIFOF::*;

// --- TYPES AND INTERFACES ---

// Typedefs
typedef enum {
   IDLE,
   SEND_ADDR,
   READ_DATA
   } State deriving (Bits, Eq, FShow);

typedef struct {
   Bit#(32) addr;
   Bit#(8)  len;
   } DMA_Command deriving (Bits, FShow);

// DMA-Memory Interface
interface DMAMemory_Ifc;
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

// DMA interface
interface DMA_Ifc;
   interface DMAMemory_Ifc mem_ifc;
   method    Action        startRead(Bit#(32) addr, Bit#(8) len);
endinterface // DMA_Ifc

//--- MODULE IMPLEMENTATION ---
module mkDMA (DMA_Ifc);

   // --- INTERNAL STATE INSTANCES ---
   Reg#(State)         state       <- mkRegA(IDLE);  // State register
   Reg#(Bit#(32))      rg_cur_addr <- mkReg(0);      // Current address register
   Reg#(Bit#(8))       rg_read_len <- mkReg(0);      // Read Length (number of reads)
   FIFOF#(Bit#(32))    data_fifo   <- mkFIFOF();     // FIFO to store data
   FIFOF#(DMA_Command) cmd_fifo    <- mkFIFOF();     // Host-side commands FIFO

   Wire#(Bit#(32))     wr_ar_addr  <- mkWire();      // Wire from mem_ifc.ar_addr
   Wire#(Bool)         wr_ar_valid <- mkDWire(False);// Wire from mem_ifc.ar_valid
   Wire#(Bool)         wr_ar_ready <- mkWire();      // Wire from mem_ifc.ar_ready

   Wire#(Bit#(32))     wr_r_data   <- mkWire();      // Wire from mem_ifc.r_addr
   Wire#(Bool)         wr_r_valid  <- mkDWire(False);// Wire from mem_ifc.r_valid
   Wire#(Bool)         wr_r_ready  <- mkWire();      // Wire from mem_ifc.r_ready

   // --- RULES ---
   rule rl_start_transfer(state == IDLE && cmd_fifo.notEmpty);
      let cmd_flit = cmd_fifo.first;
      cmd_fifo.deq;
      rg_cur_addr <= cmd_flit.addr;
      rg_read_len <= cmd_flit.len - 1;
      state <= SEND_ADDR;
   endrule

   rule rl_send_address(state == SEND_ADDR);
      if (wr_ar_ready) begin
         wr_ar_valid <= True;
         wr_ar_addr  <= rg_cur_addr;
         state <= READ_DATA;
      end
   endrule

   rule rl_read_data(state == READ_DATA);
      if (wr_r_valid && data_fifo.notFull) begin
         data_fifo.enq(wr_r_data);
         if (rg_read_len > 0) begin
            rg_read_len <= rg_read_len - 1;
            rg_cur_addr <= rg_cur_addr + 4;
            state <= SEND_ADDR;
         end
         else begin
            state <= IDLE;
         end
      end
   endrule

   // --- INTERFACE IMPLEMENTATIONS ---

   interface DMA_Ifc dma_ifc;
      method Action startRead(Bit#(32) addr, Bit#(8) len);
         cmd_fifo.enq(DMA_Command {addr: addr, len: len});
      endmethod

      interface DMAMemory_Ifc mem_ifc;
         method Action ar_put(Bit#(32) ar_addr);
            //
         endmethod

         method Bool ar_isReady();
            return wr_ar_ready;
         endmethod

         method Bool r_isValid();
            return False;
         endmethod

         method Bit#(32) r_data();
            return 0;
         endmethod

         method Action r_setReady();
            //
         endmethod

         method Action aw_put(Bit#(32) aw_addr);
         endmethod

         method Bool aw_isReady();
            return False;
         endmethod

         method Action w_put(Bit#(32) w_data);

         endmethod

         method Bool w_isReady();
            return False;
         endmethod

         method Bool b_isValid();
            return False;
         endmethod

         method Bit#(2) b_resp();
            return 0;
         endmethod

         method Action b_setReady();

         endmethod
      endinterface
   endinterface

endmodule // mkDMA

endpackage // DMA
