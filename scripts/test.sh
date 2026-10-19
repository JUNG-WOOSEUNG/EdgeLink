#!/bin/sh
# Xcode 없이 Command Line Tools만 있을 때 Swift Testing 경로를 넘겨서 테스트를 돌린다.
set -e
cd "$(dirname "$0")/.."
DEV=$(xcode-select -p)
FW="$DEV/Library/Developer/Frameworks"
LIB="$DEV/Library/Developer/usr/lib"
if [ -d "$FW/Testing.framework" ] && [ ! -d "$DEV/Platforms" ]; then
  exec swift test -Xswiftc -F"$FW" -Xlinker -F"$FW" -Xlinker -rpath -Xlinker "$FW" -Xlinker -rpath -Xlinker "$LIB" "$@"
fi
exec swift test "$@"
