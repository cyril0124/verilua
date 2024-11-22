local os = require "os"
local ffi = require 'ffi'
local tcc = require("tcc").load()

local print = print
local assert = assert
local colors = _G.colors
local verilua_debug = _G.verilua_debug

-- 
-- overwrite the origin tcc.new() 
-- 
function tcc.new(add_paths)
    local add_paths = add_paths or true
    local state = tcc.clib.tcc_new()

    verilua_debug("`so` file is " .. tcc.libfile)
  
    ffi.gc(state, tcc.State.__gc)
  
    assert(tcc.install_dir ~= nil, "tcc.install_dir is nil!!")
  
    if add_paths ~= false and tcc.install_dir then
        state:set_home_path(tcc.install_dir .. "/lib/tcc")
        state:add_sysinclude_path(tcc.install_dir .. "/lib/tcc" .. "/include")
        state:add_library_path(tcc.install_dir .. "/lib")
        state:add_library_path(tcc.install_dir .. "/lib/tcc")
    end

    local VERILUA_HOME = os.getenv("VERILUA_HOME")
    state:add_sysinclude_path(VERILUA_HOME .. "/src/include")

    state:set_error_func(function (err_msg)
        print(colors.red .. "[TCC_ERROR]", "\n\t".. err_msg .. colors.reset)
    end)
  
   return state
end


return tcc