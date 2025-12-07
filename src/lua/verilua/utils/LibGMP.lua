---@diagnostic disable: unnecessary-assert

-- References: https://github.com/Playermet/luajit-gmp
-- TODO: For now, only mpz(Multiple Precision Integer) is supported.

local ffi = require "ffi"

local ffi_string = ffi.string

---@class (exact) verilua.utils.LibGMP.params
---@field path string? Path to the library, e.g. /usr/lib/lib?.so
---@field name string? Name of the library, e.g. gmp

---@class (exact) verilua.utils.LibGMP.const
---@field SUCCESS 0
---@field ERROR -1

---@class verilua.utils.LibGMP.mpz_t
---@overload fun(): verilua.utils.LibGMP.mpz_t
---@field init_set_str fun(self: verilua.utils.LibGMP.mpz_t, str: string, base: integer): verilua.utils.LibGMP.const
---@field set_str fun(self: verilua.utils.LibGMP.mpz_t, str: string, base: integer): verilua.utils.LibGMP.const
---@field set_hex_str fun(self: verilua.utils.LibGMP.mpz_t, hex_str: string): verilua.utils.LibGMP.const
---@field set_bitfield fun(self: verilua.utils.LibGMP.mpz_t, s: integer, e: integer, value: verilua.utils.LibGMP.mpz_t): verilua.utils.LibGMP.mpz_t
---@field set_bitfield_hex_str fun(self: verilua.utils.LibGMP.mpz_t, s: integer, e: integer, hex_str: string): verilua.utils.LibGMP.mpz_t
---@field get_str fun(self: verilua.utils.LibGMP.mpz_t, base: integer): string
---@field get_hex_str fun(self: verilua.utils.LibGMP.mpz_t): string
---@field get_bin_str fun(self: verilua.utils.LibGMP.mpz_t): string
---@field get_bitfield fun(self: verilua.utils.LibGMP.mpz_t, s: integer, e: integer): verilua.utils.LibGMP.mpz_t
---@field get_bitfield_hex_str fun(self: verilua.utils.LibGMP.mpz_t, s: integer, e: integer): string
---@field popcount fun(self: verilua.utils.LibGMP.mpz_t): integer
---@field add fun(self: verilua.utils.LibGMP.mpz_t, v: verilua.utils.LibGMP.mpz_t): verilua.utils.LibGMP.mpz_t
---@field add_hex_str fun(self: verilua.utils.LibGMP.mpz_t, hex_str: string): verilua.utils.LibGMP.mpz_t
---@field sub_ui fun(self: verilua.utils.LibGMP.mpz_t, n: integer): verilua.utils.LibGMP.mpz_t
---@field lshift fun(self: verilua.utils.LibGMP.mpz_t, n: integer): verilua.utils.LibGMP.mpz_t
---@field rshift fun(self: verilua.utils.LibGMP.mpz_t, n: integer): verilua.utils.LibGMP.mpz_t
---@field andd fun(self: verilua.utils.LibGMP.mpz_t, v: verilua.utils.LibGMP.mpz_t): verilua.utils.LibGMP.mpz_t
---@field and_hex_str fun(self: verilua.utils.LibGMP.mpz_t, hex_str: string): verilua.utils.LibGMP.mpz_t
---@field ior fun(self: verilua.utils.LibGMP.mpz_t, v: verilua.utils.LibGMP.mpz_t): verilua.utils.LibGMP.mpz_t
---@field or_hex_str fun(self: verilua.utils.LibGMP.mpz_t, hex_str: string): verilua.utils.LibGMP.mpz_t
---@field xor fun(self: verilua.utils.LibGMP.mpz_t, v: verilua.utils.LibGMP.mpz_t): verilua.utils.LibGMP.mpz_t
---@field xor_hex_str fun(self: verilua.utils.LibGMP.mpz_t, hex_str: string): verilua.utils.LibGMP.mpz_t
---@field combit fun(self: verilua.utils.LibGMP.mpz_t, n: integer): verilua.utils.LibGMP.mpz_t
---@field clear fun(self: verilua.utils.LibGMP.mpz_t)
---@field dump fun(self: verilua.utils.LibGMP.mpz_t)

---@class (exact) verilua.utils.LibGMP.types
---@field z verilua.utils.LibGMP.mpz_t Multiple Precision Integer
-- TODO: q, f

---@class verilua.utils.LibGMP
---@field init fun(self: verilua.utils.LibGMP, params: verilua.utils.LibGMP.params?): verilua.utils.LibGMP
---@field clib any
---@field types verilua.utils.LibGMP.types
---@field printf fun(format: string, ...: any): verilua.utils.LibGMP.const
local M = {
    clib = nil,
    types = { z = nil --[[@as verilua.utils.LibGMP.mpz_t]] },
}

---@type any
local libgmp_clib
---@type verilua.utils.LibGMP.mpz_t
local libgmp_mpz_t

local function new_class()
    local class = {}
    class.__index = class
    return class
end

function M:init(params)
    if self.clib then
        -- LibGMP already initialized
        return self
    end

    if type(params) == "table" then
        if type(params.name) == "string" then
            if type(params.path) == "string" then
                local lib = package.searchpath(params.name, params.path)
                assert(
                    lib,
                    "[LibGMP.lua] library not found, name: " ..
                    tostring(params.name) .. ", path: " .. tostring(params.path)
                )
                self.clib = ffi.load(package.searchpath(params.name, params.path))
            else
                self.clib = ffi.load(params.name)
            end
        else
            local verilua_home = os.getenv("VERILUA_HOME")
            self.clib = ffi.load(verilua_home .. "/shared/gmp/libgmp.so")
        end
    else
        local verilua_home = os.getenv("VERILUA_HOME")
        self.clib = ffi.load(verilua_home .. "/shared/gmp/libgmp.so")
    end

    libgmp_clib = self.clib

    ffi.cdef [[
        typedef unsigned long int mp_limb_t;

        typedef mp_limb_t*       mp_ptr;
        typedef const mp_limb_t* mp_srcptr;

        typedef unsigned long int mp_bitcnt_t;

        typedef struct
        {
            int _mp_alloc;
            int _mp_size;
            mp_limb_t* _mp_d;
        } __mpz_struct;

        typedef __mpz_struct mpz_t[1];

        typedef const __mpz_struct* mpz_srcptr;
        typedef __mpz_struct*       mpz_ptr;

        void __gmpz_init_set (mpz_ptr, mpz_srcptr);
        int __gmpz_init_set_str (mpz_ptr, const char *, int);
        int __gmpz_set_str (mpz_ptr, const char *, int);
        char *__gmpz_get_str (char *, int, mpz_srcptr);
        mp_bitcnt_t __gmpz_popcount (mpz_srcptr);
        void __gmpz_add (mpz_ptr, mpz_srcptr, mpz_srcptr);
        void __gmpz_sub_ui (mpz_ptr, mpz_srcptr, unsigned long int);
        void __gmpz_mul_2exp (mpz_ptr, mpz_srcptr, mp_bitcnt_t);
        void __gmpz_tdiv_q_2exp (mpz_ptr, mpz_srcptr, mp_bitcnt_t);
        void __gmpz_and (mpz_ptr, mpz_srcptr, mpz_srcptr);
        void __gmpz_ior (mpz_ptr, mpz_srcptr, mpz_srcptr);
        void __gmpz_xor (mpz_ptr, mpz_srcptr, mpz_srcptr);
        void __gmpz_combit (mpz_ptr, mp_bitcnt_t);
        void __gmpz_clear (mpz_ptr);

        int __gmp_printf (const char *, ...);
    ]]

    self.types.z = setmetatable({}, {
        __call = function()
            -- Create the struct directly, not as an array element
            local z = ffi.new("__mpz_struct")
            return z --[[@as verilua.utils.LibGMP.mpz_t]]
        end
    })

    libgmp_mpz_t = self.types.z

    -- TODO: q, f

    do
        ---@type verilua.utils.LibGMP.mpz_t|metatable
        local mpz_mt = new_class()

        -- Table to track cleared objects to prevent double-free
        local cleared_objects = {}

        mpz_mt.init_set_str = function(this, str, base)
            return libgmp_clib.__gmpz_init_set_str(this, str, base)
        end

        mpz_mt.set_str = function(this, str, base)
            return libgmp_clib.__gmpz_set_str(this, str, base)
        end

        mpz_mt.set_hex_str = function(this, hex_str)
            return libgmp_clib.__gmpz_set_str(this, hex_str, 16)
        end

        mpz_mt.get_str = function(this, base)
            return ffi_string(libgmp_clib.__gmpz_get_str(nil, base, this))
        end

        mpz_mt.get_hex_str = function(this)
            return ffi_string(libgmp_clib.__gmpz_get_str(nil, 16, this))
        end

        mpz_mt.get_bin_str = function(this)
            return ffi_string(libgmp_clib.__gmpz_get_str(nil, 2, this))
        end

        local _rop = libgmp_mpz_t()
        local _mask = libgmp_mpz_t()
        mpz_mt.get_bitfield = function(this, s, e)
            if s > e then
                assert(false, "[mpz_t.get_bitfield] s must be less than or equal to e")
            end

            -- Create a new object for the result by copying the original
            libgmp_clib.__gmpz_init_set(_rop, this)

            -- Right-shift to align the bitfield to the LSB
            _rop:rshift(s)

            -- Create the mask (2^length - 1)
            ---@type integer
            local length = e - s + 1
            _mask:init_set_str("1", 10) -- mask = 1
            _mask:lshift(length)        -- mask = 2^length
            _mask:sub_ui(1)             -- mask = 2^length - 1

            -- Apply the _mask using bitwise AND
            _rop:andd(_mask)

            return _rop
        end

        local _val = libgmp_mpz_t()
        mpz_mt.set_bitfield = function(this, s, e, value)
            if s > e then
                assert(false, "[mpz_t.set_bitfield] s must be less than or equal to e")
            end

            local length = e - s + 1
            ---@cast length integer

            -- Create a range mask with 1s in the target range [s, e] and 0s elsewhere.
            -- _mask = ((1 << length) - 1) << s
            _mask:init_set_str("1", 10)
            _mask:lshift(length)
            _mask:sub_ui(1)
            _mask:lshift(s)

            -- Clear the target bitfield in 'this'.
            -- This is done using the bitwise identity `this & ~mask == (this | mask) ^ mask`
            -- to avoid a separate NOT operation.
            this:ior(_mask)
            this:xor(_mask)

            -- Prepare the new value for insertion.
            -- _val = (value & ((1 << length) - 1)) << s

            -- Copy the input 'value' into the temporary variable `_val`.
            libgmp_clib.__gmpz_init_set(_val, value)

            -- Reuse `_mask` as a block mask to trim `_val` to the correct width.
            -- It is shifted back to the LSB, so `_mask` is now `(1 << length) - 1`.
            _mask:rshift(s)
            _val.andd(_val, _mask) -- Trim `_val` to ensure it doesn't exceed the bitfield's length.

            -- Shift the trimmed value to the correct target position.
            _val:lshift(s)

            -- Combine the prepared value into 'this' using a bitwise OR operation.
            this:ior(_val)

            return this
        end

        local _v_set_bitfield = libgmp_mpz_t()
        mpz_mt.set_bitfield_hex_str = function(this, s, e, hex_str)
            _v_set_bitfield:init_set_str(hex_str, 16)
            return this:set_bitfield(s, e, _v_set_bitfield)
        end

        mpz_mt.get_bitfield_hex_str = function(this, s, e)
            return this:get_bitfield(s, e):get_hex_str()
        end

        mpz_mt.popcount = function(this)
            return tonumber(libgmp_clib.__gmpz_popcount(this)) --[[@as integer]]
        end

        mpz_mt.add = function(this, v)
            libgmp_clib.__gmpz_add(this, this, v)
            return this
        end

        mpz_mt.add_hex_str = function(this, hex_str)
            local v = libgmp_mpz_t()
            v:init_set_str(hex_str, 16)
            libgmp_clib.__gmpz_add(this, this, v)
            return this
        end

        mpz_mt.sub_ui = function(this, n)
            libgmp_clib.__gmpz_sub_ui(this, this, n)
            return this
        end

        mpz_mt.lshift = function(this, n)
            libgmp_clib.__gmpz_mul_2exp(this, this, n)
            return this
        end

        mpz_mt.rshift = function(this, n)
            libgmp_clib.__gmpz_tdiv_q_2exp(this, this, n)
            return this
        end

        mpz_mt.andd = function(this, v)
            libgmp_clib.__gmpz_and(this, this, v)
            return this
        end

        local _v_and = libgmp_mpz_t()
        mpz_mt.and_hex_str = function(this, hex_str)
            _v_and:init_set_str(hex_str, 16)
            libgmp_clib.__gmpz_and(this, this, _v_and)
            return this
        end

        mpz_mt.ior = function(this, v)
            libgmp_clib.__gmpz_ior(this, this, v)
            return this
        end

        local _v_or = libgmp_mpz_t()
        mpz_mt.or_hex_str = function(this, hex_str)
            _v_or:init_set_str(hex_str, 16)
            libgmp_clib.__gmpz_ior(this, this, _v_or)
            return this
        end

        mpz_mt.xor = function(this, v)
            libgmp_clib.__gmpz_xor(this, this, v)
            return this
        end

        local _v_xor = libgmp_mpz_t()
        mpz_mt.xor_hex_str = function(this, hex_str)
            _v_xor:init_set_str(hex_str, 16)
            libgmp_clib.__gmpz_xor(this, this, _v_xor)
            return this
        end

        mpz_mt.combit = function(this, n)
            libgmp_clib.__gmpz_combit(this, n)
            return this
        end

        mpz_mt.clear = function(this)
            local id = tostring(this)
            if not cleared_objects[id] then
                cleared_objects[id] = true
                libgmp_clib.__gmpz_clear(this)
            end
        end

        mpz_mt.dump = function(this)
            print("[mpz_t.dump] " .. this:get_hex_str())
        end

        mpz_mt.__gc = function(this)
            local id = tostring(this)
            if not cleared_objects[id] then
                cleared_objects[id] = true
                libgmp_clib.__gmpz_clear(this)
            end
        end

        ffi.metatype("__mpz_struct", mpz_mt)
    end

    return self
end

function M.printf(format, ...)
    return libgmp_clib.__gmp_printf(format, ...)
end

return M
