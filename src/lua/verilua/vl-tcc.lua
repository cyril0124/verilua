local ffi = require 'ffi'
local tcc = require("tcc").load()

-- 
-- overwrite the origin tcc.new() 
-- 
function tcc.new(add_paths)
    local add_paths = add_paths or true
    local state = tcc.clib.tcc_new()
  
    ffi.gc(state, tcc.State.__gc)
  
    assert(tcc.install_dir ~= nil, "tcc.install_dir is nil!!")
  
    local VERILUA_HOME = os.getenv("VERILUA_HOME")
    state:add_sysinclude_path(VERILUA_HOME .. "/src/include")

    state:set_error_func(function (err_msg)
        print("\27[31m" .. "[TCC_ERROR]", "\n\t".. err_msg .. "\27[0m")
    end)
  
   return state
end


return tcc
