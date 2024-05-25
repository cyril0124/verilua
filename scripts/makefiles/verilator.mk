# --------------------------------------------
# verilator tool selection
# --------------------------------------------
# VERILATOR = vl-verilator-p
VERILATOR = vl-verilator


# --------------------------------------------
# threads
# --------------------------------------------
EMU_THREADS ?= 2


# --------------------------------------------
# module access permission configuration
# --------------------------------------------
# CONFIG_VLT ?= $(DUT_DIR)/config.vlt
CONFIG_VLT ?= 


# --------------------------------------------
# verilua mode selection
# --------------------------------------------
VL_MODE ?= NORMAL_MODE
# VL_MODE ?= STEP_MODE
# VL_MODE ?= DOMINANT_MODE
CFLAGS += -D$(VL_MODE)


# --------------------------------------------
# emu binary runtime configuration
# --------------------------------------------
EMU_RUN_BIN = $(SIM_BUILD)/V$(TOPLEVEL)
EMU_RUN_FLAGS += 


# --------------------------------------------
# simulation files
# --------------------------------------------
SIM_FILE ?= $(SIM_BUILD)/sim_file.f
CSRCS += $(VERILUA_HOME)/src/verilator/verilator_main.cpp


# --------------------------------------------
# compiler flags
# --------------------------------------------
CFLAGS +=  -std=c++20
CFLAGS += -O2 -funroll-loops -march=native
LDFLAGS += -flto


# --------------------------------------------
# coverage enable
# --------------------------------------------
COV_ENABLE ?= 0
ifeq ($(COV_ENABLE), 1)
EMU_FLAGS += --coverage-line 
EMU_FLAGS += --coverage-toggle
endif


# --------------------------------------------
# wave enable
# --------------------------------------------
WAVE_ENABLE ?= 0
ifeq ($(WAVE_ENABLE), 1)
EMU_FLAGS += --trace --no-trace-top
endif


# --------------------------------------------
# other verilator flags
# --------------------------------------------
EMU_FLAGS += -cc --exe --build --MMD --no-timing
EMU_FLAGS += -Mdir $(SIM_BUILD)
EMU_FLAGS += -j $(shell nproc)
EMU_FLAGS += --compiler clang
EMU_FLAGS += --threads $(EMU_THREADS)
EMU_FLAGS += --x-assign unique -O3
EMU_FLAGS += --top $(TOPLEVEL)
EMU_FLAGS += -CFLAGS "${CFLAGS}" -LDFLAGS "${LDFLAGS}"
EMU_FLAGS += --Wno-PINMISSING  --Wno-MODDUP --Wno-WIDTHEXPAND --Wno-WIDTHTRUNC
EMU_FLAGS += --Wno-UNOPTTHREADS --Wno-IMPORTSTAR
EMU_FLAGS += --timescale-override 1ns/1ns
EMU_FLAGS += +define+SIM_VERILATOR


# --------------------------------------------
# rules
# --------------------------------------------
default: run

run:
	@echo -e "$(INFO_STR) $(COLOR_GREEN)-- RUN ---------------------$(COLOR_RESET)"
	numactl -m 0 -C 0-7 ${EMU_RUN_BIN} ${EMU_RUN_FLAGS}
	@echo -e "$(INFO_STR) $(COLOR_GREEN)-- DONE --------------------$(COLOR_RESET)"

build: $(EMU_RUN_BIN)

emu-run:
	@echo -e "$(INFO_STR) $(COLOR_GREEN)-- RUN ---------------------$(COLOR_RESET)"
	numactl -m 0 -C 0-7 ${EMU_RUN_BIN} ${EMU_RUN_FLAGS}
	@echo -e "$(INFO_STR) $(COLOR_GREEN)-- DONE --------------------$(COLOR_RESET)"

$(EMU_RUN_BIN): $(SIM_BUILD) $(SIM_FILE)
	@echo -e "$(INFO_STR) $(COLOR_GREEN)-- VERILATE & BUILD --------$(COLOR_RESET)"
	$(VERILATOR) $(EMU_FLAGS) -f $(SIM_FILE) $(CONFIG_VLT) || { echo -e "$(INFO_STR) $(COLOR_RED)-- BUILD FAILED --------$(COLOR_RESET)"; exit 1; }
	@echo -e "$(INFO_STR) $(COLOR_GREEN)-- BUILD SUCCESS --------$(COLOR_RESET)"


$(SIM_FILE): $(DUT_FILE)
	-rm $@
	@cat $(DUT_FILE) >> $@
	@echo $(CSRCS) >> $@

clean:
	-rm -rf $(SIM_BUILD)

.PHONY: default run build emu-run clean
