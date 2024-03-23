local config = {}

config.colors = {
    reset   = "\27[0m",
    black   = "\27[30m",
    red     = "\27[31m",
    green   = "\27[32m",
    yellow  = "\27[33m",
    blue    = "\27[34m",
    magenta = "\27[35m",
    cyan    = "\27[36m",
    white   = "\27[37m"
}

function config:config_info(...)
    print(self.colors.cyan .. os.date() .. " [CONFIG INFO]", ...)
    io.write(self.colors.reset)
end

function config:config_warn(...)
    print(self.colors.yellow .. os.date() ..  "[CONFIG WARNING]", ...)
    io.write(self.colors.reset)
end

function config:config_error(cond, ...)
    if cond == nil or cond == false then
        local error_print = function(...)
            print(self.colors.red .. os.date() ..  "[CONFIG ERROR]", ...)
            io.write(self.colors.reset)
            io.flush()
        end
        assert(false, error_print(...))
    end
end

function config:get_or_else(cfg_str, default)
    local cfg = rawget(self, cfg_str)
    if cfg == nil then
        local cfg_name = self.name or "Unknown"
        self:config_warn(string.format("[%s] cfg.%s is nil! use default config => %s", cfg_name, cfg_str, tostring(default)))
        return default
    end
    return cfg
end

return config