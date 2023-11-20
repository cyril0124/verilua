PRJ_DIR = $(realpath .)
SOURCE_DIR = $(PRJ_DIR)/src
LUA_DIR = $(PRJ_DIR)/luajit2.1
SHARED_DIR = $(PRJ_DIR)/shared

C_SOURCES = $(shell find $(SOURCE_DIR) -name "*.c" -or -name "*.cpp" -or -name "*.cc")

CXX_FLAGS += -I$(PRJ_DIR)/extern/LuaBridge/Source
CXX_FLAGS += -I$(PRJ_DIR)/extern/LuaBridge/Source/LuaBridge
CXX_FLAGS += -I$(PRJ_DIR)/extern/fmt/include
CXX_FLAGS += -I$(PRJ_DIR)/src
CXX_FLAGS += -I$(PRJ_DIR)/src/include
CXX_FLAGS += -I${LUA_DIR}/include
CXX_FLAGS += -g -std=c++17 

LD_FLAGS  += -L$(LUA_DIR)/lib -lluajit-5.1
LD_FLAGS  += -L$(PRJ_DIR)/extern/fmt/build -lfmt

default: build_so without_bootstrap_so

without_bootstrap_so: $(SHARED_DIR)/liblua_vpi_1.so

build_so: $(SHARED_DIR)/liblua_vpi.so

init:
	git submodule update --init --recursive
	mkdir -p extern/fmt/build; 
	cd extern/fmt/build; cmake -DCMAKE_POSITION_INDEPENDENT_CODE=TRUE ..; make -j $(nproc)

$(SHARED_DIR)/liblua_vpi.so: $(C_SOURCES)
	mkdir -p shared
	g++ -shared -fPIC $(CXX_FLAGS) $(PRJ_DIR)/src/lua_vpi.cpp $(LD_FLAGS) -o $@

$(SHARED_DIR)/liblua_vpi_1.so: $(C_SOURCES)
	mkdir -p shared
	g++ -shared -fPIC $(CXX_FLAGS) -DWITHOUT_BOOT_STRAP $(PRJ_DIR)/src/lua_vpi.cpp $(LD_FLAGS) -o $@

.PHONY: default build_so without_bootstrap_so init clean
clean:
	rm -rf $(SHARED_DIR)/* 