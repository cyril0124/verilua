local class = require "pl.class"

local f = string.format

local Monitor = class()

function Monitor:_init(name, signal_chdl)
    self.name = name
    self.signal = signal_chdl
end

function Monitor:start()
    verilua "appendTasks" {
        function ()
            local clock = dut.clock:chdl()

            while true do
                (f("[Monitor] [%s] ", self.name) .. self.signal:dump_str()):print()
                clock:posedge()    
            end
        end
    }
end

return Monitor