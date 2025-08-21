package DMA;

// --- IMPORTS ---
import FIFOF::*;

// --- PARAMETERS ---
`define ADDR_WIDTH 32
`define DATA_WIDTH 32

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
   method Action ar_put(Bit#(`ADDR_WIDTH) ar_addr);     // DMA sends address to memory bus and asserts valid
   method Bool   ar_isReady();                 // DMA checks if memory bus is ready

   // Methods for Data Read Channel
   method Bool      r_isValid();               // DMA reads the R_VALID signal from memory
   method Bit#(`DATA_WIDTH) r_data();                  // DMA reads the R_DATA bus from memory
   method Action    r_setReady();              // Drives the R_READY signal to memory

   // Methods for Address Write Channel
   method Action aw_put(Bit#(`ADDR_WIDTH) aw_addr);     // DMA sends address to memory bus and asserts valid
   method Bool   aw_isReady();                 // DMA checks if memory bus is ready

   // Methods for Data Write Channel
   method Action w_put(Bit#(`DATA_WIDTH) w_data);       // DMA sends data to be written in memory
   method Bool   w_isReady();                  // DMA checks if memory is ready to write

   // Methods for Write Response Channel
   method Bool    b_isValid();                 // Memory sends valid write response
   method Bit#(2) b_resp();                    // Memory sends write status response
   method Action  b_setReady();                // Drives the B_READY signal to memory
endinterface

// DMA interface
interface DMA_Ifc;
   interface DMAMemory_Ifc mem_ifc;
   method    Action        startRead(Bit#(`ADDR_WIDTH) addr, Bit#(8) len);
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

   Wire#(Bit#(32))     wr_aw_addr  <- mkWire();      // Wire from mem_ifc.aw_addr
   Wire#(Bool)         wr_aw_valid <- mkDWire(False);// Wire from mem_ifc.aw_valid
   Wire#(Bool)         wr_aw_ready <- mkWire();      // Wire from mem_ifc.aw_ready

   Wire#(Bit#(32))     wr_w_data   <- mkWire();      // Wire from mem_ifc.w_addr
   Wire#(Bool)         wr_w_valid  <- mkDWire(False);// Wire from mem_ifc.w_valid
   Wire#(Bool)         wr_w_ready  <- mkWire();      // Wire from mem_ifc.w_ready

   Wire#(Bit#(2))      wr_b_resp   <- mkWire();      // Wire from mem_ifc.b_resp
   Wire#(Bool)         wr_b_valid  <- mkDWire(False);// Wire from mem_ifc.b_valid
   Wire#(Bool)         wr_b_ready  <- mkWire();      // Wire from mem_ifc.b_ready

   // --- RULES ---
   rule rl_start_transfer(state == IDLE && cmd_fifo.notEmpty);
      let cmd_flit = cmd_fifo.first;
      cmd_fifo.deq;
      rg_cur_addr <= cmd_flit.addr;
      rg_read_len <= cmd_flit.len;
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
      if (data_fifo.notFull) begin
         wr_r_ready <= True;
      end
      if (wr_r_valid && data_fifo.notFull) begin
         data_fifo.enq(wr_r_data);
         if (rg_read_len == 1) begin
            state <= IDLE; // Transfer is complete, go back to idle.
         end
         else begin
            rg_read_len <= rg_read_len - 1;
            rg_cur_addr <= rg_cur_addr + 4;
            state <= SEND_ADDR;
         end
      end
   endrule

   // --- INTERFACE IMPLEMENTATIONS ---

   method Action startRead(Bit#(`ADDR_WIDTH) addr, Bit#(8) len);
      cmd_fifo.enq(DMA_Command {addr: addr, len: len});
   endmethod

   interface DMAMemory_Ifc mem_ifc;
      method Action ar_put(Bit#(`ADDR_WIDTH) ar_addr);
      endmethod

      method Bool ar_isReady();
         return wr_ar_ready;
      endmethod

      method Bool r_isValid();
         return wr_r_valid;
      endmethod

      method Bit#(32) r_data();
         return wr_r_data;
      endmethod

      method Action r_setReady();
         wr_r_ready <= True;
      endmethod

      method Action aw_put(Bit#(`ADDR_WIDTH) aw_addr);
      endmethod

      method Bool aw_isReady();
         return wr_aw_ready;
      endmethod

      method Action w_put(Bit#(`ADDR_WIDTH) w_data);

      endmethod

      method Bool w_isReady();
         return wr_w_ready;
      endmethod

      method Bool b_isValid();
         return wr_w_valid;
      endmethod

      method Bit#(2) b_resp();
         return wr_b_resp;
      endmethod

      method Action b_setReady();
         wr_b_ready <= True;
      endmethod
   endinterface

endmodule // mkDMA

endpackage // DMA
