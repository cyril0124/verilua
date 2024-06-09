# --------------------------------------------
# vcs tool selection
# --------------------------------------------
VCS ?= vl-vcs
VCS_CC ?= gcc

# --------------------------------------------
# simv binary runtime configuration
# --------------------------------------------
BIN ?= $(SIM_BUILD)/simv
RUN_FLAGS ?= +vcs+initreg+0 +notimingcheck 
# RUN_FLAGS += -simprofile time


# --------------------------------------------
# simulation files
# --------------------------------------------
SIM_FILE ?= $(SIM_BUILD)/sim_file.f
CSRCS += 


# --------------------------------------------
# compiler flags
# --------------------------------------------
VCS_CFLAGS += -Ofast -march=native -loop-unroll 
VCS_LDFLAGS += -Wl,--no-as-needed -flto 
VCS_FLAGS += -cc $(VCS_CC)
VCS_FLAGS += -CFLAGS "$(VCS_CFLAGS)" 
VCS_FLAGS += -LDFLAGS "$(VCS_LDFLAGS)"


# --------------------------------------------
# other vcs flags
# --------------------------------------------
VCS_FLAGS += -sverilog -full64 -top $(TOPLEVEL)
VCS_FLAGS += +v2k -timescale=1ns/1ns
# VCS_FLAGS += -debug # simulate the design in the interactive mode
VCS_FLAGS += -Mdir=$(SIM_BUILD)
VCS_FLAGS += +vcs+initreg+random 
# VCS_FLAGS += -simprofile
VCS_FLAGS += +define+SIM_VCS
VCS_FLAGS += +define+VCS
VCS_FLAGS += -j 16 # $(shell nproc)


# --------------------------------------------
# verilua mode selection
# --------------------------------------------
VL_MODE ?= NORMAL_MODE
# VL_MODE ?= STEP_MODE
# VL_MODE ?= DOMINANT_MODE
VCS_FLAGS += +define+$(VL_MODE)


# --------------------------------------------
# fgp enable
# --------------------------------------------
FGP_ENABLE ?= 1
ifeq ($(FGP_ENABLE), 1)
VCS_FLAGS += -fgp
endif


# --------------------------------------------
# wave enable
# --------------------------------------------
WAVE_ENABLE ?= 1
ifeq ($(WAVE_ENABLE), 1)
$(info $(INFO) Enable $(BOLD)$(GREEN)fsdb$(RESET_1)$(NORMAL) wave)
VCS_FLAGS += +define+WAVE_ENABLE=1

ifndef VERDI_HOME
    $(error VERDI_HOME is not set. Try whereis verdi, abandon /bin/verdi and set VERID_HOME manually)
else
    NOVAS_HOME = $(VERDI_HOME)
    NOVAS = $(NOVAS_HOME)/share/PLI/VCS/LINUX64
	VCS_FLAGS += -kdb
    VCS_FLAGS += -P $(NOVAS)/novas.tab $(NOVAS)/pli.a
endif

endif


# --------------------------------------------
# coverage enable
# --------------------------------------------
COV_ENABLE ?= 0
ifeq ($(COV_ENABLE), 1)
$(info $(INFO) Enable $(BOLD)$(GREEN)coverage$(RESET_1)$(NORMAL))
# VCS_FLAGS += +define+SYNTHESIS
VCS_FLAGS += -cm line+tgl+cond+fsm+branch+assert
VCS_FLAGS += -cm_line contassign -cm_cond allops
# VCS_FLAGS += -cm_hier $(DUT_DIR)/cov.cm.cfg
endif


# --------------------------------------------
# rules
# --------------------------------------------
default: build

run:
	$(BIN) $(RUN_FLAGS)

build: simv

simv: $(BIN)

$(BIN): $(SIM_BUILD) $(SIM_FILE)
	@echo -e "$(INFO) ${GREEN}-- BUILD SIMV ------------------------$(RESET)"
	$(VCS) $(VCS_FLAGS) -f $(SIM_FILE) -o $@ || { echo -e "$(INFO_STR) $(COLOR_RED)-- BUILD FAILED --------$(COLOR_RESET)"; exit 1; }
	@echo -e "$(INFO) ${GREEN}-- BUILD SUCCESS ---------------------$(RESET)"

$(SIM_FILE): $(DUT_FILE)
	-rm $@
	@cat $(DUT_FILE) >> $@
	@echo $(CSRCS) >> $@

clean:
	-rm -rf $(SIM_BUILD) ucli.key csrc

.PHONY: default run simv build clean
