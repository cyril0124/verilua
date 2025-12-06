#!/usr/bin/env bash

pixi init .
pixi add sysroot_linux-64=2.39
pixi add gcc=14.3.0
pixi add gxx=14.3.0
pixi add compilers=1.11.0
pixi add libstdcxx-ng=14.3.0

eval "$(pixi shell-hook)"

mkdir -p ./libc/
cp $CONDA_PREFIX/x86_64-conda-linux-gnu/sysroot/lib/* ./libc/ -Lr
rm -rf ./libc/gconf ./libc/locale ./libc/audit
cp $CONDA_PREFIX/lib/libstdc++* ./libc/ -Lr
cp $CONDA_PREFIX/lib/libgcc* ./libc/ -Lr
