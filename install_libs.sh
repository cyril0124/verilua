#!/usr/bin/env bash

git clone https://github.com/microsoft/vcpkg
./vcpkg/bootstrap-vcpkg.sh

./vcpkg/vcpkg x-update-baseline --add-initial-baseline

./vcpkg/vcpkg install
