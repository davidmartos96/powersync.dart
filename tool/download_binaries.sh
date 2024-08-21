#!/bin/bash

if [ -z "$1" ]; then
    echo "Core version is not set";
    exit 2;
fi

github="https://github.com/powersync-ja/powersync-sqlite-core/releases/download/$1"

curl "${github}/libpowersync_aarch64.so" -o packages/powersync_flutter_libs/linux/libpowersync_aarch64.so --create-dirs -L -f
curl "${github}/libpowersync_x64.so" -o packages/powersync_flutter_libs/linux/libpowersync_x64.so --create-dirs -L -f
curl "${github}/powersync_x64.dll" -o packages/powersync_flutter_libs/windows/powersync_x64.dll --create-dirs -L -f