.DEFAULT_GOAL := build
.PHONY: build run makevcd runvcd see seefst seevcd clean

VERILOG = $(wildcard vsrc/*.sv)
VERILOG += $(wildcard vsrc/*.v)
CSOURCE=$(shell find csrc -name "*.cpp" -not -path "*/tools/capstone/repo/*")
CSOURCE+=$(shell find csrc -name "*.c" -not -path "*/tools/capstone/repo/*")
CSOURCE+=$(shell find csrc -name "*.cc" -not -path "*/tools/capstone/repo/*")

# Top module name used by Verilator. create_top_sv.sh can update this value.
TOP_NAME ?= TEST_PLATFORM
FST_OBJ_DIR ?= obj_dir_fst
VCD_OBJ_DIR ?= obj_dir_vcd

VERILATOR_BASE_FLAGS = -cc $(VERILOG) --exe $(CSOURCE) --top-module $(TOP_NAME) -Mdir $(OBJ_DIR) -Ivsrc -DSIMULATION

build: OBJ_DIR = $(FST_OBJ_DIR)
build:
	verilator --trace-fst $(VERILATOR_BASE_FLAGS)
	$(MAKE) -C $(OBJ_DIR) -f V$(TOP_NAME).mk V$(TOP_NAME)

run: build
	./$(FST_OBJ_DIR)/V$(TOP_NAME)

makevcd: OBJ_DIR = $(VCD_OBJ_DIR)
makevcd:
	verilator --trace -CFLAGS "-DTRACE_VCD" $(VERILATOR_BASE_FLAGS)
	$(MAKE) -C $(OBJ_DIR) -f V$(TOP_NAME).mk V$(TOP_NAME)

runvcd: makevcd
	./$(VCD_OBJ_DIR)/V$(TOP_NAME)

see: seefst

seefst:
	gtkwave waveform.fst

seevcd:
	gtkwave waveform.vcd

clean:
	rm -rf $(FST_OBJ_DIR) $(VCD_OBJ_DIR) obj_dir waveform.fst waveform.vcd
