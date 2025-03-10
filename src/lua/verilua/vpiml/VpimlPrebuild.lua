
local f = string.format

local vpiml = {}

return setmetatable(vpiml, {
    __index = function (t, k)
        return function(...)
            assert(false, f("[VL_PREBUILD] `%s` is not implemented", k))
        end
    end
})