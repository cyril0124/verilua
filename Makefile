PRJ_DIR = $(realpath .)
SOURCE_DIR = $(PRJ_DIR)/src/verilua
INC_DIR = $(PRJ_DIR)/src/include
LUA_DIR = $(PRJ_DIR)/luajit2.1
SHARED_DIR = $(PRJ_DIR)/shared
BUILD_DIR = $(PRJ_DIR)/build

C_HEADERS = $(shell find $(INC_DIR) -name "*.h" -or -name "*.hpp")
C_SOURCES = $(shell find $(SOURCE_DIR) -name "*.c" -or -name "*.cpp" -or -name "*.cc")

OBJECTS = $(C_SOURCES:$(SOURCE_DIR)/%.cpp=$(BUILD_DIR)/%.o)

INC_FLAGS += -I$(PRJ_DIR)/extern/LuaBridge/Source
INC_FLAGS += -I$(PRJ_DIR)/extern/LuaBridge/Source/LuaBridge
INC_FLAGS += -I$(PRJ_DIR)/extern/fmt/include
INC_FLAGS += -I$(PRJ_DIR)/src
INC_FLAGS += -I$(PRJ_DIR)/src/include
INC_FLAGS += -I$(PRJ_DIR)/src/include/sol
INC_FLAGS += -I${LUA_DIR}/include

CXX_FLAGS += $(INC_FLAGS)
CXX_FLAGS += -w # disable warning
CXX_FLAGS += -std=c++17
CXX_FLAGS += -Ofast -funroll-loops -march=native -fomit-frame-pointer
CXX_FLAGS += -DACCUMULATE_LUA_TIME
# CXX_FLAGS += -g

LD_FLAGS  += -Wl,--no-as-needed
LD_FLAGS  += -L$(LUA_DIR)/lib -lluajit-5.1
LD_FLAGS  += -L$(PRJ_DIR)/extern/fmt/build -lfmt

default: build_so 

# without_bootstrap_so
# without_bootstrap_so: $(SHARED_DIR)/liblua_vpi_1.so

build_so: $(SHARED_DIR) $(SHARED_DIR)/liblua_vpi.so

CXX = clang++
# CXX = g++
init:
	git submodule update --init --recursive
	mkdir -p extern/fmt/build; 
	cd extern/fmt/build; cmake -DCMAKE_POSITION_INDEPENDENT_CODE=TRUE ..; make -j $(nproc)

# $(SHARED_DIR)/liblua_vpi_1.so: $(OBJECTS)
# 	@echo -e "LINK \t $(notdir $@)"
# 	@$(CXX) $(CXX_FLAGS) -fPIC -DWITHOUT_BOOT_STRAP -o $@ $^ -shared $(LD_FLAGS) 

$(SHARED_DIR)/liblua_vpi.so: $(OBJECTS)
	@echo -e "LINK \t $(notdir $@)"
	@$(CXX) $(CXX_FLAGS) -fPIC -o $@ $^ -shared $(LD_FLAGS) 

$(BUILD_DIR)/%.o: $(SOURCE_DIR)/%.cpp $(C_HEADERS) $(BUILD_DIR)
	@echo -e "CXX \t $(notdir $<) \t ==> \t $(notdir $@)"
	@$(CXX) $(CXX_FLAGS) -fPIC -c $< -o $@

$(BUILD_DIR):
	mkdir -p $@

$(SHARED_DIR):
	mkdir -p $@

.PHONY: default build_so without_bootstrap_so init clean
clean:
	-rm -rf $(SHARED_DIR)/* 
	-rm -rf $(BUILD_DIR)/*