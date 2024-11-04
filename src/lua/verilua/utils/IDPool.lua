local List = require "pl.List"
local class = require "pl.class"
local ffi = require "ffi"

local C = ffi.C
local assert = assert
local f = string.format

ffi.cdef[[
    void* idpool_init(int size, int shuffle);
    int idpool_alloc(void *idpool_void);
    void idpool_release(void *idpool_void, int id);
    int idpool_pool_size(void *idpool_void);
    void idpool_free(void *idpool_void);
]]


local IDPool = class()

function IDPool:_init(size, shuffle)
    local _shuffle = shuffle or false
    self.size = size
    
    -- Lua implementation
    -- self.pool = List()
    -- for i = self.size, 1, -1 do
    --     self.pool:append(i)
    -- end

    self.c_pool = C.idpool_init(size, _shuffle)
end

function IDPool:alloc()
    -- if #self.pool > 0 then
        -- return self.pool:pop() -- Lua implementation
    if C.idpool_pool_size(self.c_pool) > 0 then
        return C.idpool_alloc(self.c_pool) -- C implementation
    else
        assert(false, "IDPool is empty! size => " .. self.size)
    end
end

function IDPool:release(id)
    if id > self.size then
        assert(false, f("Invalid id! id:%d size:%d ", id, self.sise))
    end

    --self.pool:append(id) -- Lua implementation
    C.idpool_release(self.c_pool, id)
end

function IDPool:is_full()
    -- return #self.pool == 0 -- Lua implementation
    return C.idpool_pool_size(self.c_pool) == 0 -- C implementation
end

function IDPool:pool_size()
    -- return #self.pool -- Lua implementation
    return C.idpool_pool_size(self.c_pool) -- C implementation
end

-- Below is a tcc version of IDPool
-- local lib = ([[
-- #include <stdio.h>
-- #include <stdlib.h>
-- #include <assert.h>

-- typedef struct {
--     int *pool;
--     int size;
--     int top;
-- } IDPool;

-- // Initialize the IDPool
-- // $sym<IDPool_init> $ptr<void *(*)(int)>
-- void* IDPool_init(int size) {
--     IDPool *idpool = (IDPool *)malloc(sizeof(IDPool));
--     idpool->size = size;
--     idpool->pool = (int *)malloc(size * sizeof(int));
--     idpool->top = size - 1;
    
--     for (int i = 0; i < size; i++) {
--         idpool->pool[i] = size - i;
--     }
    
--     return (void*)idpool;
-- }

-- // Allocate an ID
-- // $sym<IDPool_alloc> $ptr<int (*)(void *)>
-- int IDPool_alloc(void *idpool_void) {
-- 	IDPool *idpool = (IDPool *)idpool_void;
--     if (idpool->top >= 0) {
--         return idpool->pool[idpool->top--];
--     } else {
--         fprintf(stderr, "IDPool is empty! size => %d\n", idpool->size);
--         assert(0);
--     }
-- }

-- // Release an ID back to the pool
-- // $sym<IDPool_release> $ptr<void (*)(void *, int)>
-- void IDPool_release(void *idpool_void, int id) {
-- 	IDPool *idpool = (IDPool *)idpool_void;
--     if (id > idpool->size) {
--         assert(0);
--         return;
--     }
--     idpool->pool[++idpool->top] = id;
-- }

-- ]]):tcc_compile()

-- local idpool_c = lib.IDPool_init(1000)
-- local a = lib.IDPool_alloc(idpool_c)
-- lib.IDPool_release(idpool_c, i)

return IDPool