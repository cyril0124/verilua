-- Use `inst` to match a spcific module instance
add_signals {
    module = "A",
    inst = "b_inst.a_inst_0",
    signals = "i_value_.*"
}

-- Three groups of signals has only one senstive trigger
do
    local n = add_pattern {
        name = "i_signals",
        module = "B",
        sensitive_signals = ".*valid",
        signals = "(i_.*)|(.*valid)"
    }
    assert(n == "i_signals")

    local n1 = add_pattern {
        name = "o_signals",
        module = "B",
        sensitive_signals = ".*valid1",
        signals = "(o_.*)|(.*valid1)"
    }
    assert(n1 == "o_signals")

    local n2 = add_pattern {
        module = "B",
        sensitive_signals = "(signal1|signal2)",
        signals = "signal.*"
    }

    add_senstive_trigger {
        name = "test",
        group_names = { n, n1, n2 }
    }
end

-- `add_signals` is the alias name of `add_pattern`
do
    local n2 = add_signals {
        name = "n2",
        module = "top",
        sensitive_signals = "i_value_0",
        signals = "i_.*"
    }

    local n3 = add_signals {
        name = "n3",
        module = "top",
        sensitive_signals = "o_value_0",
        signals = "o_.*"
    }

    add_senstive_trigger {
        name = "test1",
        group_names = { n2, n3 }
    }
end

add_signals {
    name = "C_writable",
    module = "C",
    writable_signals = "w_value.*"
}

add_signals {
    name = "C_writable_with_inst",
    module = "C",
    inst = "b_inst.a_inst_0.*",
    writable_signals = "w_value.*"
}

add_signals {
    module = "D",
    signals = "value.*",
    disable_signals = ".*test.*"
}