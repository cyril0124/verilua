local CombArbiter = {}

---@class CombArbiterPort
---@field valid verilua.handles.CallableHDL
---@field ready verilua.handles.CallableHDL
---@field data verilua.handles.CallableHDL

--- Evaluate committed inputs and schedule outputs using deferred writes.
---@param input0 CombArbiterPort
---@param input1 CombArbiterPort
---@param output CombArbiterPort
local function evaluate(input0, input1, output)
    local valid0 = input0.valid:is(1)
    local valid1 = input1.valid:is(1)
    local downstream_ready = output.ready:is(1)

    local output_valid = 0
    local output_data = 0

    if valid0 then
        output_valid = 1
        output_data = input0.data:get() --[[@as integer]]
    elseif valid1 then
        output_valid = 1
        output_data = input1.data:get() --[[@as integer]]
    end

    local ready0 = 0
    local ready1 = 0

    if downstream_ready then
        ready0 = 1
        if not valid0 then
            ready1 = 1
        end
    end

    output.valid:set(output_valid)
    output.data:set(output_data)
    input0.ready:set(ready0)
    input1.ready:set(ready1)
end

--- Recompute outputs whenever an input changes, without advancing time.
---@param input0 CombArbiterPort
---@param input1 CombArbiterPort
---@param output CombArbiterPort
function CombArbiter.start(input0, input1, output)
    evaluate(input0, input1, output)

    local inputs = {
        input0.valid,
        input0.data,
        input1.valid,
        input1.data,
        output.ready,
    }

    for _, signal in ipairs(inputs) do
        fork {
            function()
                while true do
                    await_edge_hdl(signal.hdl)
                    evaluate(input0, input1, output)
                end
            end,
        }
    end
end

return CombArbiter
