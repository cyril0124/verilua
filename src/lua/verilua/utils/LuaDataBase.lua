--- LuaDataBase is an alias of LuaDataBaseV2, which is a strict superset: same
--- constructor params, same `save`/`commit` semantics, same `__type`
--- ("LuaDataBase"). The LuaCATS types (`verilua.utils.LuaDataBase.*`) are
--- declared in LuaDataBaseV2.lua. Prefer requiring LuaDataBaseV2 directly in
--- new code.
---
--- Differences from the old lsqlite3-based implementation:
--- - libsqlite3 is loaded lazily via FFI instead of `require "lsqlite3"`
---   (RTLD_NOW), so `require` no longer hard-fails when an ancient libsqlite3
---   shadows the modern one on LD_LIBRARY_PATH (e.g. VCS ships sqlite 3.7.13).
--- - All LuaDataBaseV2 backends and params are available, e.g.
---   `backend = "duckdb" | "turso" | "auto"` and `no_check_bind_value`.
--- - The private `db` handle is the FFI wrapper object, not an lsqlite3 object.

return require "verilua.utils.LuaDataBaseV2"
