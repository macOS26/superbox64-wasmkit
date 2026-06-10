#!/bin/bash
# WASM-Cartridge host build. Embedded Swift, SDL3 + wasmtime via C interop.
#   brew install sdl3 wasmtime
set -euo pipefail
cd "$(dirname "$0")"
TC="$(dirname "$(dirname "$(TOOLCHAINS=${SWIFT_TOOLCHAIN:-org.swift.6.3.2-release} xcrun --toolchain swift -f swiftc)")")"
TOOLCHAINS="${SWIFT_TOOLCHAIN:-org.swift.6.3.2-release}" xcrun --toolchain swift swiftc \
  -enable-experimental-feature Embedded -wmo -Osize -parse-as-library \
  -Xcc -fmodule-map-file=Sources/CSDL3/module.modulemap \
  -Xcc -fmodule-map-file=Sources/CWasmtime/module.modulemap \
  -Xcc -I/opt/homebrew/include -I Sources/CSDL3 -I Sources/CWasmtime \
  -L /opt/homebrew/lib -lSDL3 -lwasmtime \
  "$TC/lib/swift/embedded/arm64-apple-macos/libswiftUnicodeDataTables.a" \
  Sources/cartridge.swift -o wasm-cartridge
echo "✓ wasm-cartridge ($(stat -f%z wasm-cartridge) bytes)"
