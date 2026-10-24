# Bingus Shared Loader (v21 Continuation)

[![License: 0BSD](https://img.shields.io/badge/License-0BSD-blue.svg)](LICENSE)
[![Target: Helldivers 2](https://img.shields.io/badge/Helldivers%202-Build%2025988413%2B-brightgreen.svg)](https://store.steampowered.com/app/553850/HELLDIVERS_2/)

Community continuation and modernization of **Bingus Shared Loader** following the Helldivers 2 October 2026 engine updates (Steam Builds 25988413 & 26088801+).

The game update deleted `core/wwise/lua/wwise_flow_callbacks` and removed LuaJIT (`lua51.dll` / FFI) in favor of standard PUC-Rio Lua 5.1.4. This release restores mod discovery and startup by anchoring to the primary engine `boot` script in plain Lua 5.1.

---

## Features in v21
- **Engine Boot Anchor:** Hooks directly into `resource 0xF476DF93691895FA` (`boot`) in bundle `9ba626afa44a3aa3`, chaining engine `init`, `shutdown`, `update`, and `render` safely.
- **Pure Lua 5.1 Format:** Emits standard plain-text Lua 5.1 chunks (`u32 len, u32 2, source`) preventing `(binary): bad header in precompiled chunk`.
- **Pure-Lua MurmurHash64A & Bitwise Logic:** Custom 64-bit hashing and bitwise LUT emulation running without FFI or external C libraries.
- **Dynamic Patch Discovery:** Scans `data/9ba626afa44a3aa3.patch_0..255` using standard binary `io.open` and starts declared addons.
- **Win32 & FFI Stubs:** Metatable-aware mocks for `kernel32`, `bcrypt`, and memory routines so legacy mods fail safely without crashing the game.
- **No SHA-256 Binary Lock:** Removed hardcoded executable hash assertions so minor game hotfixes don't disable your mods.

---

## Installation

### Via Mod Manager (Recommended)
1. Download `Bingus-Shared-Loader-v21-Official-Fix.zip` from NexusMods.
2. Import the archive into **HD2 Mod Manager** or **HDArsenal**.
3. Set the load priority to the default base slot (`patch_0`).
4. Click **Deploy / Apply Mods**.

### Manual Installation
Extract the contents of the `data/` folder directly into your Helldivers 2 game directory:
```text
<SteamLibrary>/steamapps/common/Helldivers 2/data/
```
Ensure you have:
- `9ba626afa44a3aa3.patch_0`
- `9ba626afa44a3aa3.patch_0.stream`
- `9ba626afa44a3aa3.patch_0.gpu_resources`

---

## Documentation & FAQ
- See [docs/FAQ.md](docs/FAQ.md) for full answers on mod compatibility, Mod Options Menu UI, crash troubleshooting, and load order.

## Repository Layout
This repository currently contains Bingus Shared Loader at the root, including its source, packaging files, and documentation. Keep those paths unchanged so existing mod-manager manifests and installation instructions continue to work.

Add future, independent mods under `mods/<game>/<mod-name>/`. Give each mod its own README, manifest, source, assets, and documentation as needed. Do not place files for a new mod in this loader's `src/`, `data/`, or `docs/` directories.

---

## License & Credits
- **Original Author:** [CowboyBingus](https://github.com/CowboyBingus/BingusSharedLoader)
- **Continuation Maintainer:** realityzero0 (with AI-assisted research and verification)
- **License:** [Zero-Clause BSD (0BSD)](LICENSE) — 100% free and open source with zero restrictions.
