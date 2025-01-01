
# ===========================================================
# Used in runtime
# ===========================================================
export LD_LIBRARY_PATH=${CONDA_PREFIX}/lib
export LD_LIBRARY_PATH=${CONDA_PREFIX}/share/vcpkg/installed/x64-linux/lib:$LD_LIBRARY_PATH

# ===========================================================
# Used in compilation
# ===========================================================
export LIBRARY_PATH=${CONDA_PREFIX}/lib
export LIBRARY_PATH=${CONDA_PREFIX}/share/vcpkg/installed/x64-linux/lib:$LIBRARY_PATH

# ===========================================================
# Include paths
# ===========================================================
export CPATH=${CONDA_PREFIX}/include
export CPATH=${CONDA_PREFIX}/share/vcpkg/installed/x64-linux/include:$CPATH
export C_INCLUDE_PATH=$CPATH
export C_INCLUDE_PATH=$CPATH:$C_INCLUDE_PATH


export PKG_CONFIG_PATH=${CONDA_PREFIX}/share/pkgconfig:${CONDA_PREFIX}/lib/pkgconfig
export USE_PIX=1