#!/usr/bin/env bash

mv ./tools/nosim ./tools/nosim_1
cat <<'EOF' > ./tools/nosim
#!/usr/bin/env bash
HERE="$(dirname "$(readlink -f "$0")")"
ROOT="$HERE/.."
MY_LOADER="$ROOT/libc/ld-linux-x86-64.so.2"
MY_LIBS="$ROOT/libc:$ROOT/shared:$ROOT/luajit-pro/luajit2.1/lib"
exec "$MY_LOADER" --library-path "$MY_LIBS" "$HERE/nosim_1" "$@"
EOF
chmod +x ./tools/nosim

mv ./tools/wave_vpi_main ./tools/wave_vpi_main_1
cat <<'EOF' > ./tools/wave_vpi_main
#!/usr/bin/env bash
HERE="$(dirname "$(readlink -f "$0")")"
ROOT="$HERE/.."
MY_LOADER="$ROOT/libc/ld-linux-x86-64.so.2"
MY_LIBS="$ROOT/libc:$ROOT/shared:$ROOT/luajit-pro/luajit2.1/lib"
exec "$MY_LOADER" --library-path "$MY_LIBS" "$HERE/wave_vpi_main_1" "$@"
EOF
chmod +x ./tools/wave_vpi_main