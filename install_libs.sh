#!/usr/bin/env bash

git clone https://github.com/microsoft/vcpkg
./vcpkg/bootstrap-vcpkg.sh

./vcpkg/vcpkg install fmt
./vcpkg/vcpkg install argparse
./vcpkg/vcpkg install sol2
