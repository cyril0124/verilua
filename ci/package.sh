#!/usr/bin/env bash

set -ex

# Check if `zip-file` is provided
if [ -z "$1" ]; then
    echo -e "Error: zip-file is not provided"
    echo -e "\n\tUsage: $0 <zip-file>\n"
    exit 1
fi

zip_file=$(readlink -m $1)

# Make sure the directory of zip-file exists
zip_file_dir=$(dirname $zip_file)
zip_file_name=$(basename $zip_file)

mkdir -p $zip_file_dir

rm -rf ./dist

mkdir -p ./dist/extern
mkdir -p ./dist/extern/luajit_tcc/tinycc
mkdir -p ./dist/luajit-pro/luajit2.1
mkdir -p ./dist/luajit-pro/tl

cp -r ./VERSION ./dist
cp -r ./xmake.lua ./dist
cp -r ./verilua.sh ./dist
cp -r ./activate_verilua.sh ./dist

echo "${zip_file_name}" > ./dist/DIST_INFO
echo "$(git rev-parse HEAD)" > ./dist/COMMIT_HASH

cp -r ./src ./dist
cp -r ./shared ./dist
cp -r ./tools ./dist
cp -r ./scripts ./dist
cp -r ./tests ./dist
cp -r ./examples ./dist
cp -r ./extern/luafun ./dist/extern
cp -r ./extern/debugger.lua ./dist/extern
cp -r ./extern/luajit_tcc/tcc.lua ./dist/extern/luajit_tcc
cp -r ./extern/luajit_tcc/setvars.sh ./dist/extern/luajit_tcc
cp -r ./extern/luajit_tcc/tinycc/install ./dist/extern/luajit_tcc/tinycc

cp -r ./luajit-pro/src ./dist/luajit-pro
cp -r ./luajit-pro/luajit2.1/bin ./dist/luajit-pro/luajit2.1/bin
cp -r ./luajit-pro/luajit2.1/lib ./dist/luajit-pro/luajit2.1/lib
cp -r ./luajit-pro/luajit2.1/etc ./dist/luajit-pro/luajit2.1/etc
cp -r ./luajit-pro/luajit2.1/share ./dist/luajit-pro/luajit2.1/share
cp -r ./luajit-pro/luajit2.1/include ./dist/luajit-pro/luajit2.1/include
cp -r ./luajit-pro/tl/tl.lua ./dist/luajit-pro/tl
cp -r ./luajit-pro/tl/tl.tl ./dist/luajit-pro/tl

pushd dist
zip -r $zip_file .
popd

echo -e "[package.sh] $zip_file is successfully created!"