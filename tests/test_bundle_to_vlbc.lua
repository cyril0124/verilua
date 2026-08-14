---@diagnostic disable: unnecessary-assert, unresolved-require

local lester = require "lester"
local describe, it, expect = lester.describe, lester.it, lester.expect

lester.parse_args()

local BundleToVlbc = require "verilua.utils.BundleToVlbc"

describe("BundleToVlbc", function()
    it("errors outside Verilua when sealing", function()
        local ok, err = pcall(function()
            BundleToVlbc.seal_bytes("\027LJxxxx")
        end)
        expect.equal(ok, false)
        assert(tostring(err):find("vl_bundle_seal", 1, true) or tostring(err):find("libverilua", 1, true))
    end)
end)
