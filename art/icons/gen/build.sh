#!/bin/sh
# usage: build.sh <sheet name> <names>
cat gen.js icons_*.js > all.js && node all.js out && node render.js out out "$1" "$2"
