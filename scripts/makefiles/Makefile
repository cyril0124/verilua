# --------------------------------------------
# simulator select
# --------------------------------------------
SIM ?= vcs
# SIM ?= verilator

PRJ_DIR = $(realpath .)


# --------------------------------------------
# user configuration
# --------------------------------------------
SIM_BUILD ?= $(PRJ_DIR)/sim_build
DUT_DIR ?= $(PRJ_DIR)/dut
TOPLEVEL ?= tb_top
DUT_FILE = $(SIM_BUILD)/dut_file.f


# --------------------------------------------
# some usefull macros
# --------------------------------------------
INFO=[INFO]

BOLD    = $(shell tput bold)
NORMAL  = $(shell tput sgr0)
RED     = $(shell tput setaf 1)
GREEN   = $(shell tput setaf 2)
RESET_1 = $(shell tput setaf 0)
RESET   = \033[0m


# --------------------------------------------
# makefile selection based on SIM
# --------------------------------------------
ifeq ($(SIM), vcs)
    include vcs.mk
    $(info $(INFO) Using $(BOLD)$(GREEN)VCS$(RESET_1)$(NORMAL) as simulator)
endif

ifeq ($(SIM), verilator)
    include verilator.mk
    $(info $(INFO) Using $(BOLD)$(GREEN)VERILATOR$(RESET_1)$(NORMAL) as simulator)
endif

ifeq ($(SIM), iverilog)
    include iverilog.mk
    $(info $(INFO) Using $(BOLD)$(GREEN)IVERILOG$(RESET_1)$(NORMAL) as simulator)
endif


# --------------------------------------------
# common rules
# --------------------------------------------
$(SIM_BUILD):
	mkdir -p $@

$(DUT_FILE):
	$(shell find $(DUT_DIR) -name "*.v" -or -name "*.sv" > $@)

