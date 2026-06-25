# Bluespec DMA Controller

A highly pipelined, robust, and feature-rich Direct Memory Access (DMA) controller written in Bluespec SystemVerilog (BSV).

## Features

- **Pipelined Architecture:** Decoupled AXI read, write, and response channels for maximum throughput and latency hiding.
- **Scatter/Gather Engine (SGE):** Hardware-based linked-list descriptor traversal for executing complex, multi-block memory transfers without CPU intervention. Supports standard backpressure handling.
- **Data Width Adaptation:** A built-in Gearbox mechanism up-sizes internal 32-bit data streams to a wider 64-bit Memory Controller bus seamlessly, ensuring high throughput.
- **Unaligned Memory Access:** A dynamic Byte Aligner module manages unaligned start/end boundaries, managing byte shifts and automatically generating precise AXI Write Strobes (`wstrb`) for the target memory.
- **C-based Memory Model Simulation:** An integrated testing environment featuring a C-backend to test DMA transactions against a highly realistic memory model layout.

## Repository Structure

- `rtl/`: Contains the core hardware modules:
  - `DMA.bsv`: Core AXI transaction management and FIFO dispatch logic.
  - `ScatterGatherEngine.bsv`: Descriptor parsing and DMA command sequencing.
  - `DMA_WidthAdapter.bsv`: Integrates the up-sizing Gearbox to adapt the 32-bit DMA core to a 64-bit memory bus.
  - `DMA_ByteAligner.bsv`: Handles misaligned accesses and dynamic byte shifting.
  - `Gearbox.bsv`: Generic logic for packing and unpacking vectors of data for width conversion.
- `tests/`: Individual simulation scenarios for validating functionality:
  - `test_throughput.bsv`: Verifies pure linear burst throughput.
  - `test_sge.bsv`: Verifies linked-list descriptor fetching.
  - `test_aligner.bsv`: Verifies byte-level masking and unaligned transfers.
- `testbench/`: Testbench infrastructure, C-imports, and `MemoryBridge` adapters.

## Building and Testing

A `Makefile` is provided for running simulations via the Bluesim compiler.

### Prerequisites
- Bluespec compiler (`bsc`)

### Commands

**Run all test suites:**
```bash
make test_all
```

**Run individual tests:**
```bash
make test_throughput
make test_sge
make test_robustness  # Runs Scatter/Gather with heavy backpressure enabled
make test_aligner
```

**Clean build artifacts:**
```bash
make clean
```
