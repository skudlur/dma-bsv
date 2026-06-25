# =============================================================================
# Makefile for the Bluespec DMA Controller Project
# =============================================================================

# --- Tools ---
BSC = bsc
RM = rm -rf

# --- Project Structure ---
RTL_DIR = rtl
TESTBENCH_DIR = testbench

# Top-level module for simulation
TOP_MODULE = mkTestDMA

# --- Build and Output Configuration ---
BUILD_DIR = build
C_FILES_DIR = $(BUILD_DIR)/C_FILES

# --- Compiler Flags ---
# The "-p" flag is crucial for telling BSC where to find source files.
# It is a colon-separated list of search paths.
BSC_PATH_FLAGS = -p +:%/Libraries:$(RTL_DIR):$(TESTBENCH_DIR):tests

# =============================================================================
# Main Targets
# =============================================================================

.PHONY: all
all: test_all

.PHONY: test_all
test_all: test_throughput test_sge test_robustness test_aligner
	@echo "========================================="
	@echo "All tests passed!"
	@echo "========================================="

# =============================================================================
# Individual Test Targets
# =============================================================================

.PHONY: setup
setup:
	@mkdir -p $(BUILD_DIR) $(C_FILES_DIR)

# Compile and run Throughput test
test_throughput: setup
	@echo "========================================="
	@echo "Running Throughput Test (Raw DMA)"
	@echo "========================================="
	$(MAKE) build_and_run TOP_FILE=tests/test_throughput.bsv MACROS="" TEST_EXE=dma_test_throughput

# Compile and run Scatter/Gather test
test_sge: setup
	@echo "========================================="
	@echo "Running Scatter/Gather Test"
	@echo "========================================="
	$(MAKE) build_and_run TOP_FILE=tests/test_sge.bsv MACROS="" TEST_EXE=dma_test_sge

# Compile and run Robustness test (SGE with backpressure)
test_robustness: setup
	@echo "========================================="
	@echo "Running Robustness Test (SGE + Heavy Backpressure)"
	@echo "========================================="
	$(MAKE) build_and_run TOP_FILE=tests/test_sge.bsv MACROS="-D BACKPRESSURE" TEST_EXE=dma_test_robustness

# Compile and run Byte Aligner test (Unaligned memory access)
test_aligner: setup
	@echo "========================================="
	@echo "Running Unaligned Byte Aligner Test"
	@echo "========================================="
	$(MAKE) build_and_run TOP_FILE=tests/test_aligner.bsv MACROS="" TEST_EXE=dma_test_aligner

# =============================================================================
# Build Rules
# =============================================================================

.PHONY: build_and_run
build_and_run: | $(BUILD_DIR) $(C_FILES_DIR)
	@echo "--- Compiling Bluespec Code ---"
	$(BSC) -u -sim -g $(TOP_MODULE) $(MACROS) $(BSC_PATH_FLAGS) -bdir $(BUILD_DIR) -simdir $(C_FILES_DIR) $(TOP_FILE)

	@echo "--- Linking Executable ---"
	$(BSC) -sim -e $(TOP_MODULE) -o $(TEST_EXE) -bdir $(BUILD_DIR) -simdir $(C_FILES_DIR) $(TESTBENCH_DIR)/C_imports.c
	
	@echo "--- Running Simulation ---"
	./$(TEST_EXE) | tee $(TEST_EXE)_output.txt

# =============================================================================
# Directory Creation
# =============================================================================

$(BUILD_DIR):
	@mkdir -p $@

$(C_FILES_DIR): | $(BUILD_DIR)
	@mkdir -p $@

# =============================================================================
# Cleaning Targets
# =============================================================================

.PHONY: clean
clean:
	@echo "--- Cleaning All Build Artifacts ---"
	@$(RM) $(BUILD_DIR)
	@$(RM) dma_test*
	@$(RM) *.bo *.ba *.so *.cxx *.h *.o
	@$(RM) $(TESTBENCH_DIR)/*.o
	@echo "Done."

# =============================================================================
# Utility Targets
# =============================================================================

.PHONY: help
help:
	@echo "DMA Controller Makefile"
	@echo "======================="
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Main Targets:"
	@echo "  all             - Build and run all tests."
	@echo "  test_all        - Build and run all tests."
	@echo "  test_throughput - Run baseline throughput test."
	@echo "  test_sge        - Run scatter/gather engine test."
	@echo "  test_robustness - Run scatter/gather engine test with heavy backpressure."
	@echo ""
	@echo "Cleaning:"
	@echo "  clean           - Remove all generated files and build artifacts."
	@echo ""
	@echo "Other:"
	@echo "  help            - Show this help message."
