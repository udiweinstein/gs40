#!/bin/bash
# Build GS40.app from source. Run from anywhere: ./build.sh  (or ./build.sh clean)
set -e
cd "$(dirname "$0")/src"
if [ "$1" = "clean" ]; then make clean; rm -rf ../GS40.app; exit 0; fi
make -j"$(sysctl -n hw.ncpu)"
echo
echo "Built: $(cd .. && pwd)/GS40.app"
echo "Run:   open \"$(cd .. && pwd)/GS40.app\""
