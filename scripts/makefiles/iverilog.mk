# --------------------------------------------
# iverilog tool selection
# --------------------------------------------
IVERILOG = vl-iverilog
VVP_BIN ?= vvp_wrapper


# --------------------------------------------
# simv vvp file runtime configuration
# --------------------------------------------
VVP_FILE ?= $(SIM_BUILD)/simv.vvp
VVP_FLAGS ?= -M ${VERILUA_HOME}/shared -m lua_vpi


# --------------------------------------------
# simulation files
# --------------------------------------------
SIM_FILE ?= $(SIM_BUILD)/sim_file.f


# --------------------------------------------
# verilua mode selection
# --------------------------------------------
VL_MODE ?= NORMAL
# VL_MODE ?= STEP
# VL_MODE ?= DOMINANT
IVERILOG_FLAGS += -D $(VL_MODE)_MODE


# --------------------------------------------
# other iverilog flags
# --------------------------------------------
IVERILOG_FLAGS += -D SIM_IVERILOG


# --------------------------------------------
# TODO: wave enable
# --------------------------------------------
# WAVE_ENABLE ?= 0


# --------------------------------------------
# rules
# --------------------------------------------
default: build

run:
	$(VVP_BIN) $(VVP_FLAGS) $(VVP_FILE)

build: simv.vvp

debug:
	gdb --args $(VVP_BIN) $(VVP_FLAGS) $(VVP_FILE)

valgrind:
	valgrind --tool=memcheck --leak-check=full $(VVP_BIN) $(VVP_FLAGS) $(VVP_FILE)

simv.vvp: $(VVP_FILE)

$(VVP_FILE): $(SIM_BUILD) $(SIM_FILE)
	@echo -e "$(INFO) ${GREEN}-- BUILD SIMV.VVP ------------------------$(RESET)"
	$(IVERILOG) $(IVERILOG_FLAGS) -f $(SIM_FILE) -o $@ || { echo -e "$(INFO_STR) $(COLOR_RED)-- BUILD FAILED --------$(COLOR_RESET)"; exit 1; }
	@echo -e "$(INFO) ${GREEN}-- BUILD SUCCESS ---------------------$(RESET)"

$(SIM_FILE): $(DUT_FILE)
	-rm $@
	@cat $(DUT_FILE) >> $@
	@echo $(CSRCS) >> $@

clean:
	-rm -rf $(SIM_BUILD)

.PHONY: default run debug valgrind simv.vvp build clean
