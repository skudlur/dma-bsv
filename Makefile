# =============================================================================
# Makefile for the Bluespec DMA Controller Project
# Adapted from a reference project structure.
# =============================================================================

# --- Tools ---
BSC = bsc
RM = rm -rf

# --- Project Structure ---
RTL_DIR = rtl
TESTBENCH_DIR = testbench

# Top-level module and file for simulation
TOP_MODULE = mkTestDMA
TOP_FILE = test_DMA.bsv

# --- Build and Output Configuration ---
BUILD_DIR = build
C_FILES_DIR = $(BUILD_DIR)/C_FILES
TEST_EXE = dma_test
OUTPUT_FILE = dma_simulation_output.txt

# --- Compiler Flags ---
# The "-p" flag is crucial for telling BSC where to find source files.
# It is a colon-separated list of search paths.
BSC_PATH_FLAGS =
BSC_SIM_FLAGS = -u -sim -g $(TOP_MODULE) $(BSC_PATH_FLAGS)
BSC_LINK_FLAGS = -sim -e $(TOP_MODULE) -o $(TEST_EXE)

# =============================================================================
# Main Targets
# =============================================================================

# Default target: build and run the test
.PHONY: all
all: test

# Build and run the simulation testbench
.PHONY: test
test: $(TEST_EXE)
	@echo "--- Running DMA Simulation ---"
	./$(TEST_EXE) | tee $(OUTPUT_FILE)
	@echo "--- Simulation Finished ---"
	@echo "Output saved to $(OUTPUT_FILE)"

# =============================================================================
# Build Rules
# =============================================================================

# Rule to build the final simulation executable
# Corrected version with symbolic link workaround
$(TEST_EXE): $(RTL_DIR)/DMA.bsv $(TESTBENCH_DIR)/$(TOP_FILE) | $(BUILD_DIR) $(C_FILES_DIR)
	@echo "--- Creating symbolic link for compilation ---"
	cd $(TESTBENCH_DIR) && ln -sf ../$(RTL_DIR)/DMA.bsv DMA.bsv

	@echo "--- Compiling Bluespec Code ---"
	cd $(TESTBENCH_DIR) && $(BSC) $(BSC_SIM_FLAGS) -bdir ../$(BUILD_DIR) -simdir ../$(C_FILES_DIR) $(TOP_FILE)

	@echo "--- Removing symbolic link ---"
	cd $(TESTBENCH_DIR) && rm -f DMA.bsv

	@echo "--- Linking Executable ---"
	$(BSC) $(BSC_LINK_FLAGS) -bdir $(BUILD_DIR) -simdir $(C_FILES_DIR)

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
	@$(RM) $(TEST_EXE)
	@$(RM) $(OUTPUT_FILE)
	@$(RM) *.bo *.ba *.so *.cxx *.h *.o
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
	@echo "  all          - (Default) Build and run the simulation testbench."
	@echo "  test         - Build and run the simulation testbench."
	@echo "  $(TEST_EXE)  - Compile and link the executable without running it."
	@echo ""
	@echo "Cleaning:"
	@echo "  clean        - Remove all generated files and build artifacts."
	@echo ""
	@echo "Other:"
	@echo "  help         - Show this help message."
