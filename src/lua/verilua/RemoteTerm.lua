local utils = require("LuaUtils")
local socket = require("socket")
local class = require("pl.class")

RemoteTerm = class()

function RemoteTerm:_init(port)
    self.domain = "localhost"
    self.port = port or 12345
    self.is_open = false
    self.retry_max = 50

    self:reconnect()
    assert(self.client ~= nil)
    self.is_open = true
end

function RemoteTerm:print(...)
    if not self.is_open then return end

    local msg = table.concat({...}, "\t")
    -- assert(self.client:send(msg .. "\n"))

    local ok, _ = pcall(function() assert(self.client:send(msg .. "\n")) end)
    if not ok then self:reconnect() end
end

function RemoteTerm:reconnect()
    local success = false
    local retry_cnt = 0
    while not success and retry_cnt < self.retry_max do
        client, msg = socket.connect(self.domain, self.port)

        if client then
            self.client = client
            success = true
        else
            verilua_info("["..self.domain..":"..self.port.."] ".. msg.." retrying... ["..retry_cnt.."/"..self.retry_max.."]")
            io.flush()
            socket.sleep(1)
            retry_cnt = retry_cnt + 1
        end
    end

    if not success then
        self.client = assert(socket.connect(self.domain, self.port))
    else
        verilua_info(self.domain..":"..tostring(self.port).." connection good!")
    end
end

function RemoteTerm:info(...)
    if not self.is_open then return end
    self:print(colors.cyan .. os.date() .. " [VERILUA INFO]", ...)
    io.write(colors.reset)
end

function RemoteTerm:warning(...)
    if not self.is_open then return end
    self:print(colors.yellow .. os.date() .. " [VERILUA WARNING]", ...)
    io.write(colors.reset)
end

function RemoteTerm:error(...)
    if not self.is_open then return end
    self:print(colors.red .. os.date() .. " [VERILUA ERROR]", ...)
    io.write(colors.reset)
end

function RemoteTerm:close()
    self.client:close()
    self.is_open = false
end

return RemoteTerm
