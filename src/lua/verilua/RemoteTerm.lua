local utils = require("LuaUtils")
local socket = require("socket")
local class = require("pl.class")

RemoteTerm = class()

local colors = {
    reset = "\27[0m",
    black = "\27[30m",
    red = "\27[31m",
    green = "\27[32m",
    yellow = "\27[33m",
    blue = "\27[34m",
    magenta = "\27[35m",
    cyan = "\27[36m",
    white = "\27[37m"
}

function RemoteTerm:_init(port)
    self.domain = "localhost"
    self.port = port or 12345
    self.is_open = false

    local success = false
    local retry_cnt = 0
    local retry_max = 10
    while not success and retry_cnt < retry_max do
        client, msg = socket.connect(self.domain, self.port)

        if client then
            self.client = client
            success = true
        else
            verilua_info(msg.." retrying... ["..retry_cnt.."/"..retry_max.."]")
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
    
    assert(self.client ~= nil)
    self.is_open = true
end

function RemoteTerm:print(...)
    if not self.is_open then return end

    local msg = table.concat({...}, "\t")
    assert(self.client:send(msg .. "\n"))
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
