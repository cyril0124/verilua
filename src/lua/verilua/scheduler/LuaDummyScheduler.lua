local class = require("pl.class")

local Scheduler = class()

function Scheduler:_init()
end

function Scheduler:__index(key)
    return function (key)
        -- do nothing
    end
end

function Scheduler:get_event_hdl(name, user_event_id)
	return {
        name = name,
        event_id = user_event_id,
        wait = function()
            -- do nothing
        end,
        send = function()
            -- do nothing
        end
    }
end

return Scheduler()
