#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
cd "$DIR"

echo "⚡ Compiling Endvein Turbo native engine..."

OS="$(uname -s)"
if [ "$OS" = "Darwin" ]; then
    TARGET="libendvein_turbo.dylib"
    clang -O3 -flto -shared -fPIC endvein_turbo.c -o "$TARGET"
else
    TARGET="libendvein_turbo.so"
    gcc -O3 -flto -shared -fPIC endvein_turbo.c -o "$TARGET"
fi

echo "✅ Successfully built native/$TARGET"
