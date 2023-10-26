local List = require("pl.List")
local class = require("pl.class")

IDPool = class()

function IDPool:_init(size)
    self.size = size
    self.pool = List()
    for i = self.size, 1, -1 do
        self.pool:append(i)
    end
end

function IDPool:alloc()
    if #self.pool > 0 then
        return self.pool:pop()
    else
        return nil
    end
end

function IDPool:release(id)
    assert(id <= self.size)
    return self.pool:append(id)
end

function IDPool:is_full()
    return #self.pool == 0
end

function IDPool:pool_size()
    return #self.pool
end