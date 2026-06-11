# superbox64-wasmkit

Run a game in the browser as WebAssembly, without Emscripten.

The JavaScript runtime in this repo drives the game loop, renders on Canvas2D (display-p3 wide color on supporting browsers), mixes audio on Web Audio API, handles input from DOM events and the Web Gamepad API, and persists state to localStorage. No watermarks. No loading screens. No third-party branding.

**Live demo:** [boss-man.us/play](https://boss-man.us/play)

**Swift SpriteKit package:** [superbox64-spritekit](https://github.com/macOS26/superbox64-spritekit)

**Reference game:** [Boss-Man](https://github.com/macOS26/Boss-Man)

lots note planned taking WebAssembly, Wasmtime, and native binaries to a whole new level.

---

## What Is in This Repo

| Path | What it is |
|---|---|
| `runtime.js` | The entire JavaScript runtime (Canvas2D renderer, Web Audio mixer, DOM input, asset preloader, gamepad, localStorage) |
| `runtime-embedded.js` | The runtime variant reserved for Embedded Swift builds (same contract; tweaks land here first) |
| `runtime-embedded-min.js` | Terser-minified embedded runtime (96 KB → 42 KB); what boss-man.us and the WebView apps ship |
| `shell.html` | Minimal host page — configure `window.WASMWEB`, serve `runtime.js` next to it |
| `build.sh` | Build helper for C/C++ games via the WASI SDK |
| `include/abi.h` | C ABI the WASM binary uses to call the runtime (`gfx_*`, `snd_*`, `key_*`, `evt_*`, `win_*`, `store_*`) |
| `include/SFML/` | Header-only SFML 2.6 shim so existing C++ SFML games compile unchanged |
| `scripts/bundle.py` | Packages a finished wasm + assets into a single offline `local.html` (all assets inlined as data: URLs) |

---

## Host Page

Copy `shell.html`, configure `window.WASMWEB`, and serve `runtime.js` next to it:

```html
<!DOCTYPE html>
<html lang="en"><head>
  <meta charset="utf-8"/>
  <style>
    html,body{margin:0;background:#000;}
    #game{width:100vw;aspect-ratio:1184/666;display:block;}
  </style>
</head><body>
  <canvas id="game"></canvas>
  <script>
    window.WASMWEB = {
      logicalWidth:  1184,
      logicalHeight: 666,
      wasmUrl:       'game.wasm',
      assetRoot:     'assets',
      title:         'My Game'
    };
  </script>
  <script src="runtime.js"></script>
</body></html>
```

The runtime preloads every asset listed in `manifest.json` (fonts via `FontFace`, images via `ImageBitmap`, audio via `AudioBuffer`, JSON as strings) before calling `boot()`, then runs the frame loop via `requestAnimationFrame`.

---

## Reactor Contract

The WASM binary is a WASI Preview 1 reactor exporting exactly three symbols:

| Export | When called | What it does |
|---|---|---|
| `_initialize` | Once, first | wasi-libc init and global constructors (works for C, C++ and Embedded Swift reactors alike) |
| `boot()` | Once, after assets preload | Create the game scene |
| `frame(dtMs: f64)` | Every `requestAnimationFrame` | Advance and render one frame |

Everything else (drawing, audio, input, persistence) is imported from the `env` module via `include/abi.h`.

---

## Building a C/C++ Game

```bash
# In your game's build script:
WASMWEB_OUT=web/game.wasm
WASMWEB_SRC_DIRS=(src)
WASMWEB_INCLUDES=(include)
WASMWEB_SFML=on          # link the sf:: SFML shim
source ../superbox64-wasmkit/build.sh
wasmweb_build
```

`build.sh` variables:

| Variable | Default | Description |
|---|---|---|
| `WASMWEB_OUT` | required | Output `.wasm` path |
| `WASMWEB_SRC_DIRS` | `(src)` | Directories scanned for `*.cpp` / `*.c` |
| `WASMWEB_EXTRA_SRCS` | `()` | Explicit extra source files |
| `WASMWEB_INCLUDES` | `()` | Extra `-I` directories |
| `WASMWEB_DEFINES` | `()` | Extra `-D` defines |
| `WASMWEB_SFML` | `off` | `on` to link the `sf::` SFML compatibility shim |
| `WASMWEB_EXCEPTIONS` | `off` | `on` to enable C++ exceptions (increases binary size) |
| `WASMWEB_ASSETS` | | Assets directory to scan for `manifest.json` |

---

## Building a Swift SpriteKit Game

Use [superbox64-spritekit](https://github.com/macOS26/superbox64-spritekit) as a SwiftPM dependency, then build with the wasm SDK:

```bash
xcrun --toolchain swift swift build \
    --swift-sdk swift-6.3.2-RELEASE_wasm \
    -c release
```

The output `.wasm` is served with this runtime exactly like a C++ game.

---

## Under the Hood

What one frame looks like from the runtime's side:

1. **Instantiate.** `runtime.js` fetches the wasm (WASI Preview 1 or Embedded
   Swift reactor; both export the same three symbols), provides every `env`
   import, and calls `_initialize`.
2. **Preload.** `manifest.json` drives the asset pipeline: images decode to
   handles, audio decodes to Web Audio buffers, fonts register through
   `FontFace` (fetched as bytes, so `file://` works too).
3. **Boot.** `boot()` runs once; the game builds its first scene.
4. **Loop.** Every `requestAnimationFrame`, gamepads are polled into the
   event queue, then `frame(dt)` runs. The wasm replies with a stream of
   `gfx_*` calls the runtime replays onto Canvas2D — sprites and atlas
   sub-rects via `drawImage`, shapes and text natively, offscreen canvases
   for bake/crop/effect work, and a hidden WebGL2 canvas for `gfx_shader_*`
   GLSL effects blitted back into the 2D scene.
5. **Audio** plays on a Web Audio graph (`snd_*` voices with volume, pan and
   rate; `eng_*` exposes an AVAudioEngine-shaped player/mixer graph;
   `tts_*` is the browser's speech synthesis).
6. **Input** (keyboard, mouse, multi-touch, Web Gamepad) lands in a queue the
   wasm drains via `evt_poll`; visibility changes pause audio and the loop in
   background tabs.

There is no Emscripten anywhere in this pipeline, and nothing injected
between the game and the player: no ads, no watermarks, no logo overlays.
The wasm and this runtime are the entire stack.

## ABI Reference (`include/abi.h`)

### Graphics

| Function | Description |
|---|---|
| `gfx_clear(rgba)` | Clear the canvas |
| `gfx_fill_rect(x, y, w, h, rgba)` | Filled rectangle |
| `gfx_stroke_rect(x, y, w, h, rgba, lw)` | Stroked rectangle |
| `gfx_fill_circle(cx, cy, r, rgba)` | Filled circle |
| `gfx_stroke_circle(cx, cy, r, rgba, lw)` | Stroked circle |
| `gfx_fill_path(pts, n, rgba)` | Filled polygon |
| `gfx_stroke_path(pts, n, rgba, lw)` | Stroked polyline |
| `gfx_draw_image(id, x, y, w, h, alpha)` | Draw a preloaded image |
| `gfx_draw_image_ex(id, sx,sy,sw,sh, dx,dy,dw,dh, alpha)` | Draw image with source crop |
| `gfx_set_transform(a,b,c,d,tx,ty)` | Set canvas 2D transform |
| `gfx_reset_transform()` | Reset to identity |
| `gfx_offscreen_begin(id, w, h, alpha)` | Start rendering to offscreen canvas |
| `gfx_offscreen_end()` | Return to main canvas |
| `gfx_offscreen_draw(id, x, y, w, h, alpha)` | Draw offscreen canvas to main |

### Text

| Function | Description |
|---|---|
| `txt_measure(ptr, len, font_ptr, font_len, size) → width` | Measure text width |
| `txt_draw(ptr, len, x, y, font_ptr, font_len, size, rgba, align)` | Draw text |

### Sound

| Function | Description |
|---|---|
| `snd_play(id, volume, loop)` | Play a preloaded sound |
| `snd_stop(id)` | Stop a sound |
| `snd_set_volume(id, volume)` | Set playback volume |
| `snd_is_playing(id) → bool` | Query playback state |
| `snd_tts(ptr, len, rate, pitch, volume)` | Text-to-speech via Web Speech API |

### Input

| Function | Description |
|---|---|
| `key_pressed(keycode) → bool` | Is a keyboard key currently held |
| `key_just_pressed(keycode) → bool` | Was a key pressed this frame |
| `key_just_released(keycode) → bool` | Was a key released this frame |
| `mouse_x() → f64` | Mouse X in logical coordinates |
| `mouse_y() → f64` | Mouse Y in logical coordinates |
| `mouse_button(btn) → bool` | Is a mouse button held |
| `pad_axis(pad, axis) → f64` | Gamepad axis value |
| `pad_button(pad, btn) → bool` | Gamepad button state |

### Events

| Function | Description |
|---|---|
| `evt_poll(out_ptr) → type` | Poll the next input event off the queue |

### Window

| Function | Description |
|---|---|
| `win_width() → f64` | Logical canvas width |
| `win_height() → f64` | Logical canvas height |
| `win_dpr() → f64` | Device pixel ratio |
| `win_fullscreen_enter()` | Request fullscreen |
| `win_fullscreen_exit()` | Exit fullscreen |

### Persistence

| Function | Description |
|---|---|
| `store_set(key_ptr, key_len, val_ptr, val_len)` | Write to localStorage |
| `store_get(key_ptr, key_len, out_ptr, max_len) → len` | Read from localStorage |
| `store_del(key_ptr, key_len)` | Delete a localStorage entry |

---

## Display-P3 Wide Color

On Safari, Chrome 104+, and WebKit-based WebViews the runtime negotiates a display-p3 Canvas2D context automatically. Color values passed through the ABI are treated as P3 coordinates, producing more vivid colors on wide-gamut displays. No game-side changes needed.

---

## Bundling for Offline Use

```bash
python3 scripts/bundle.py web/game.wasm web/assets web/index.html local.html
```

Produces a single `local.html` with every asset inlined as a `data:` URL. Opens from `file:///` with no server.

---

## Related

- [superbox64-spritekit](https://github.com/macOS26/superbox64-spritekit) — Swift SpriteKit package that compiles to WASM
- [Boss-Man](https://github.com/macOS26/Boss-Man) — full arcade game built with this kit, shipping on 6 platforms from one Swift source

---

## License

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE). Apache 2.0 grants an explicit patent license and terminates it on patent litigation, protecting contributors and users from patent ambush.
