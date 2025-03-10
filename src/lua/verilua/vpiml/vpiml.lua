if os.getenv("VL_PREBUILD") == "1" then
    return require "VpimlPrebuild"
else
    return require "VpimlNormal"
end