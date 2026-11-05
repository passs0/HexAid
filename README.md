<p align="center">
  <img src="assets/icon.png" width="160" height="160" alt="HexAid Icon" />
</p>

<h1 align="center">HexAid</h1>

<p align="center">
  <strong>One-click in-place patcher for CrossOver on Apple Silicon macOS</strong><br/>
  Upgrades GStreamer (with FFmpeg / Media Foundation decoding), DXMT, DXVK, Apple Game Porting Toolkit (<code>D3DMetal.framework</code>), and bottle performance settings directly inside <code>/Applications/CrossOver.app</code>.
</p>

---

> [!NOTE]
> **AI-Generated Tool Disclosure**
> **HexAid** (including its SwiftUI source code, patching automation, and Apple Liquid Glass icon design) is an **AI-generated tool** created with **Antigravity** (Google DeepMind) and inspired by the open-source macOS gaming community's work on **CXPatcher** and **Procyon**.

---

## ✨ Why HexAid?

When CodeWeavers CrossOver updates (or ships out of the box), several key components are either stripped down for licensing reasons or lag behind the latest community releases:
- **Broken / Freeze-Prone In-Game Cutscenes:** Stock CrossOver omits the GStreamer `libav` (FFmpeg) plugin (`libgstlibav.dylib`), causing games like *Silent Hill 2 Remake*, *Resident Evil*, and other Unreal Engine 4/5 titles using Windows Media Foundation (`winegstreamer`) to freeze or display a black screen when playing H.264/HEVC/VP9 cutscenes.
- **Duplicate App Clutter (`Crossover_patched.app`) & Missing D3DMetal:** Earlier wrapper tools either required launching CrossOver through a secondary app or duplicated `CrossOver.app` while accidentally stripping `lib64/apple_gptk` (`D3DMetal`).

**HexAid patches `/Applications/CrossOver.app` directly in place:**
- **No duplicate `Crossover_patched.app`**—launch CrossOver normally from your Dock or Applications folder.
- **Preserves and protects Apple Game Porting Toolkit (`D3DMetal.framework`)** from accidental deletion or incompatible beta tampering.
- **Existing (Old) Bottles Automatically Benefit:** Because CrossOver bottles load their graphics backends (`D3DMetal`, `DXMT`, `DXVK`) and media libraries (`winegstreamer.so` + `GStreamer.framework`) dynamically from `/Applications/CrossOver.app` at runtime, **once you run HexAid, all of your existing (old) bottles and already-installed games immediately benefit**—no need to recreate bottles or reinstall games!

---

## 🚀 Features

1. **Full GStreamer + FFmpeg (`libgstlibav.dylib`) Upgrade**
   - Automatically fetches the latest universal `GStreamer.framework` build from [`Sikarugir-App/gstreamer`](https://github.com/Sikarugir-App/gstreamer).
   - Removes conflicting partial `libgst*` / `libglib*` libraries in `CrossOver.app/Contents/SharedSupport/CrossOver/lib64`, links `lib64/gstreamer-1.0` to `GStreamer.framework`, and adds `@loader_path/../../../lib64/GStreamer.framework/Versions/Current/lib` to `winegstreamer.so` via `install_name_tool`.
2. **Latest DXMT (Direct3D 10/11 to Metal)**
   - Automatically queries GitHub Releases for the latest [`3Shain/dxmt`](https://github.com/3Shain/dxmt) release and installs `d3d10core.dll`, `d3d11.dll`, `dxgi.dll`, and `winemetal.dll`/`winemetal.so` into `CrossOver.app`.
3. **Latest DXVK-macOS (Optional Toggle)**
   - Queries [`Gcenx/DXVK-macOS`](https://github.com/Gcenx/DXVK-macOS) and upgrades `lib/dxvk` (`x86_64-windows` and `i386-windows`).
4. **Apple Game Porting Toolkit (`D3DMetal.framework`) Integrity & Protection**
   - Verifies that CrossOver's officially validated `lib64/apple_gptk/external/D3DMetal.framework` is intact and healthy (preventing legacy wrapper bugs that stripped D3DMetal).
   - **Why standalone beta GPTK injection is intentionally avoided:** Apple's newer GPTK betas introduce tight internal ABI dependencies between `D3DMetal.framework` and Wine's PE Direct3D 12 libraries (`d3d12.dll`). Injecting unverified beta frameworks into CrossOver causes severe entry point and ABI mismatches that crash DirectX 12 games. CodeWeavers officially tests and bundles verified D3DMetal builds with CrossOver releases; HexAid safely protects this tested engine.
5. **Existing Bottle Performance Optimizations**
   - Optionally scans all existing bottles in `~/Library/Application Support/CrossOver/Bottles/` and enables `WINEMSYNC=1` (MSync) and `ROSETTA_ADVERTISE_AVX=1` (AVX/AVX2 advertising under Rosetta 2) in `cxbottle.conf`.
6. **GStreamer & D3DMetal Cache Cleaner**
   - Purges stale `gstreamer-1.0-registry.x86_64.bin` and `d3dm` shader caches so updated plugins and shaders load cleanly on your next launch.

---

## 🛠️ Building & Installing

HexAid has **zero external dependencies** and compiles cleanly using the standard macOS Command Line Tools (`swiftc`, `iconutil`, `codesign`).

```zsh
git clone https://github.com/passs0/HexAid.git
cd HexAid
chmod +x build.sh
./build.sh
cp -R build/HexAid.app /Applications/
```

Whenever CrossOver updates via its built-in updater, simply open **HexAid** from `/Applications` and click **Patch CrossOver Now**.

---

## 🙏 Credits & Acknowledgments

**HexAid** is directly based on and inspired by the pioneering work of the macOS CrossOver / Wine gaming community:

- **[CXPatcher](https://github.com/italomandara/CXPatcher)** by **[@italomandara](https://github.com/italomandara)** — The original macOS patcher for CrossOver that pioneered integrating custom DXVK, DXMT, D3DMetal (GPTK), and GStreamer upgrades, as well as bottle configuration tweaks.
- **Procyon** — For demonstrating the GStreamer framework bundle layout and runtime environment ideas for fixing Windows Media Foundation (`winegstreamer`) cutscenes.
- **[3Shain/dxmt](https://github.com/3Shain/dxmt)** by **[@3Shain](https://github.com/3Shain)** — Metal-based Direct3D 10/11 implementation for Wine/CrossOver on macOS.
- **[Sikarugir-App/gstreamer](https://github.com/Sikarugir-App/gstreamer)** & **[Gcenx/DXVK-macOS](https://github.com/Gcenx/DXVK-macOS)** by **[@Gcenx](https://github.com/Gcenx)** — Prebuilt universal `GStreamer.framework` (with full FFmpeg/`libav` support) and macOS DXVK builds.
- **[CodeWeavers CrossOver](https://www.codeweavers.com/crossover)** & **Apple Game Porting Toolkit (`D3DMetal`)**.

---

## 📄 License

Released under the [MIT License](LICENSE).
