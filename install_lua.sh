#!/bin/bash

luajit_dir=$(pwd)/luajit2.1

rm -rf $luajit_dir
hererocks luajit2.1 -j 2.1 -r latest

# Bug fix...
cp $luajit_dir/lib/libluajit-5.1.so.2 $luajit_dir/lib/libluajit-5.1.so
