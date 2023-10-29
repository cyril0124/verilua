#!/bin/bash

curr_dir=$(pwd)
luajit_dir=$(pwd)/luajit2.1
luajit_branch=v2.1-20231006

rm -rf $luajit_dir
git clone https://github.com/openresty/luajit2.git $luajit_dir
cd $luajit_dir
git checkout $luajit_branch
cd $curr_dir

hererocks luajit2.1 -j $luajit_dir -r latest

# Bug fix...
# cp $luajit_dir/lib/libluajit-5.1.so.2 $luajit_dir/lib/libluajit-5.1.so
