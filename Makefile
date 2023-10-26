PRJ_DIR = $(realpath .)
SOURCE_DIR = $(PRJ_DIR)/src
LUA_DIR = $(PRJ_DIR)/luajit2.1
SHARED_DIR = $(PRJ_DIR)/shared

C_SOURCES = $(shell find $(SOURCE_DIR) -name "*.c" -or -name "*.cpp" -or -name "*.cc")

CXX_FLAGS += -I$(PRJ_DIR)/LuaBridge/Source
CXX_FLAGS += -I$(PRJ_DIR)/src
CXX_FLAGS += -I$(PRJ_DIR)/src/include
CXX_FLAGS += -I${LUA_DIR}/include
CXX_FLAGS += -g 

LD_FLAGS  += -L$(LUA_DIR)/lib -lluajit-5.1

default: build_so

without_bootstrap_so: $(SHARED_DIR)/lua_vpi_1.so

build_so: without_bootstrap_so $(SHARED_DIR)/lua_vpi.so

init:
	git submodule update --init --recursive

$(SHARED_DIR)/lua_vpi.so: $(C_SOURCES)
	gcc -shared -fPIC $(CXX_FLAGS) $(PRJ_DIR)/src/lua_vpi.cpp $(LD_FLAGS) -o $@

$(SHARED_DIR)/lua_vpi_1.so: $(C_SOURCES)
	g++ -shared -fPIC $(CXX_FLAGS) -DWITHOUT_BOOT_STRAP $(PRJ_DIR)/src/lua_vpi.cpp $(LD_FLAGS) -o $@

.PHONY: default build_so without_bootstrap_so init clean
clean:
	rm -rf $(SHARED_DIR)/* 