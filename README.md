# Verilua
## Install verilua
`install.sh` will setup verilua env (both Python and Lua) and the `VERILUA_HOME` env variable.

For `bash` user
```
make init
bash install.sh bash
```
For `zsh` user
```
make init
bash install.sh zsh
```

## Using verilua
Before using verilua, you should type `source setvars.sh` in your terminal which will setup basic lua script package path and link library path for `.so` files used in lua.