# WASM-Cartridge · a native console for wasm-web-kit games

The same `.wasm` a website serves is a complete game with zero platform
assumptions: it draws, plays sound, reads input, and persists ONLY through
the KitABI `env` import surface. That makes it a cartridge. This host is
the console.

```
wasm-cartridge bossman-embedded.wasm
wasm-cartridge asteroidz-embedded.wasm
CARTRIDGE_WASM=game.wasm ./wasm-cartridge
```

One ~190 KB Embedded Swift binary (no Swift stdlib, no Foundation) that
opens an SDL3 window, runs the module under wasmtime with WASI Preview 1,
and fills the env surface natively: Canvas2D compatible matrix stack, thick
strokes via SDL_RenderGeometry, SFML vocabulary events, WAV voices mixed on
one audio device, store as a tsv file. Functions a game never imports are
bound as zero stubs straight from the module's own import table, so new
games keep working without host changes.

## The cartridge model

Ship a `WASM-Cartridge.zip`: this host (per platform) + any number of game
wasms + their assets. Games update by replacing a wasm file. One host build
per platform plays the whole catalog, the binaries never know the
difference, and the SAME wasm keeps running on the website. Distribution
becomes: web page, cartridge zip, or app store wrapper, all from one build.

Controls: arrows/WASD + Space, C for coin, F toggles fullscreen.
