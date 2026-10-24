# 📌 Bingus Shared Loader (v21 Continuation) — Official Pinned FAQ
> **NexusMods Page:** [Helldivers 2 Mod #17798](https://www.nexusmods.com/helldivers2/mods/17798)  
> **Applies to:** Bingus Shared Loader v21 (Official Lua 5.1 Continuation)  
> **Target Game Build:** 25988413 / 26088801+ (October 2026 Engine Update & Beyond)  
> **License:** Zero-Clause BSD (0BSD) — 100% Free & Open Source  

---

## ⚡ Quick Links
- [1. General & Compatibility](#1-general--compatibility)
- [2. "Do Old Mods Work Automatically?"](#2-do-old-mods-work-automatically)
- [3. "Where is the Mod Options Menu?"](#3-where-is-the-mod-options-menu)
- [4. Download & Installation Guide](#4-download--installation-guide)
- [5. Troubleshooting & Crash Fixes](#5-troubleshooting--crash-fixes)
- [6. Open Source & Source Code Repository](#6-open-source--source-code-repository)

---

## 1. General & Compatibility

### Q1: What is this mod, and why is it called "v21"?
In late October 2026, Arrowhead pushed updates (Steam Builds 25988413 and 26088801+) that overhauled Helldivers 2's underlying engine:
1. They **deleted** the audio script resource (`core/wwise/lua/wwise_flow_callbacks`) that original Bingus Shared Loader (v19/v20) hooked into. Because that resource no longer exists, v19/v20 can never run.
2. They removed `lua51.dll` (LuaJIT) and switched the game to vanilla **PUC-Rio Lua 5.1.4**.

**Bingus Shared Loader v21** is a community continuation that moves the loader anchor to the engine's primary `boot` script (`resource 0xF476DF93691895FA`), runs in standard plain-text Lua 5.1, and restores mod loading so the game can launch properly.

---

### Q2: Will using this mod loader get me banned by Easy Anti-Cheat (EAC)?
**No.**  
This mod loader is strictly pure Lua 5.1:
- **Zero DLL injection / Zero DLL hijacking:** It does not drop modified `.dll` files into your game folder.
- **Zero memory hooking:** It does not attach debuggers, inject threads, or edit game RAM.
- **Zero EAC bypasses:** EAC runs in its normal protected state. The loader works entirely within the game's official archive patch system (`data/9ba626afa44a3aa3.patch_N`), exactly how sound and armor mods function.

---

### Q3: Will this loader break every time Arrowhead pushes a minor hotfix?
**No.**  
Older versions (like v20) contained hardcoded SHA-256 hash checks (`exe_sha256` and `game_sha256`). When Arrowhead released a minor hotfix, the loader saw mismatched hashes and shut down.  
In **v21**, we completely removed the brittle SHA-256 binary gates. As long as Arrowhead does not alter the fundamental engine boot pipeline, this loader will continue working across game updates.

---

## 2. "Do Old Mods Work Automatically?"

### Q4: Do my old favorite mods (First Person, Transmog, Shodan, SEAF Artillery, Smart Turrets) work automatically with v21?
> [!IMPORTANT]
> **No.** The loader itself is fixed, but older gameplay mods that relied on LuaJIT FFI must be updated by their respective mod authors.

Here is why:
1. **LuaJIT FFI is gone:** Arrowhead completely removed LuaJIT from the game executable. Any mod that used FFI to scan raw game memory addresses cannot read memory anymore.
2. **Bytecode rejection:** Many older mods were precompiled into LuaJIT bytecode (`.luac`). Standard Lua 5.1 cannot load LuaJIT bytecode and will throw:  
   `"(binary): bad header in precompiled chunk"`.
3. **What v21 does for you:** It isolates old mods and provides compatibility stubs so they fail safely on Frame 1 **without crashing your game to desktop**. However, their gameplay functionality will remain inactive until their authors port them to Lua 5.1.

---

## 3. "Where is the Mod Options Menu?"

### Q5: I pressed F2 in-game and nothing happens. Where is the Mod Options Menu?
*(Frequently asked in the comments!)*

**Bingus Shared Loader is the backend coordinator, NOT the menu UI itself:**
- The loader manages mod discovery, initialization, and saves your configuration data.
- The visual **Mod Options Menu UI** is a *separate mod* originally created by CowboyBingus.
- If you only install the loader without the Mod Options Menu mod package, pressing `F2` will not display any visual overlay. Once the Mod Options Menu UI mod is updated for Lua 5.1, this loader will communicate with it seamlessly.

---

## 4. Download & Installation Guide

### Q6: Where do I download the mod?
On this NexusMods page, click the **"Files" tab** located at the top (right next to the "Description" tab). Click **Manual Download** or **Mod Manager Download**.

---

### Q7: How do I install with HD2 Mod Manager / HDArsenal / Vortex?
1. Download the `.zip` file from the **Files** tab.
2. Open your mod manager (e.g., HD2 Mod Manager or HDArsenal).
3. Drag and drop the `.zip` file into the manager or click **Import Mod**.
4. Make sure the mod is enabled (checked).
5. Ensure its load priority is set to the **default base layer** (`patch_0`).
6. Click **Deploy / Apply Mods**.

---

### Q8: How do I install manually (without a mod manager)?
1. Open the downloaded `Bingus-Shared-Loader-v21-Official-Fix.zip`.
2. Extract the `data/` folder directly into your Helldivers 2 game directory:
   ```text
   <Steam Library>\steamapps\common\Helldivers 2\data\
   ```
3. You should see these three files in your `data/` folder:
   - `9ba626afa44a3aa3.patch_0`
   - `9ba626afa44a3aa3.patch_0.stream`
   - `9ba626afa44a3aa3.patch_0.gpu_resources`

---

### Q9: What should my load order / patch number be?
The loader should ideally be `patch_0` so its boot override is established first. If you have other mods occupying `patch_0`, ensure the loader's patch is deployed properly through your mod manager so its `boot` script is not overwritten.

---

## 5. Troubleshooting & Crash Fixes

### Q10: My screen is black on startup / game freezes on launch. What do I do?
A black screen occurs when an outdated mod has an uncaught Lua crash before the engine's graphics pipeline initializes.

**How to fix:**
1. Temporarily move all other `.patch_N` files out of `<Helldivers 2>/data/`, leaving only the loader's `9ba626afa44a3aa3.patch_0`.
2. Launch the game to confirm it boots cleanly to your ship.
3. Add your other mods back one by one to determine which outdated mod is crashing the boot process.

---

### Q11: What does `(binary): bad header in precompiled chunk` mean?
This error in your logs indicates an installed mod was compiled with LuaJIT bytecode. Standard Lua 5.1 cannot parse LuaJIT bytecode. Please notify the mod author to rebuild their mod using plain text `.lua` source.

---

### Q12: Where are the log files located?
Logs are written to:
```text
<Helldivers 2>/bin/BingusSharedLoader.log
```
(or `<Helldivers 2>/bin/hd2_loader.log`). Check this file if a mod fails to start.

---

## 6. Open Source & Source Code Repository

### Q13: Is this project open source? Where can I view the code?
**Yes, 100%.**  
In accordance with CowboyBingus's original **Zero-Clause BSD (0BSD)** license, all sources, build tools, and test suites are fully open and unrestricted. You can view and fork the code on GitHub:  
👉 **GitHub Repository:** `https://github.com/realityzero0/Bingus-Shared-Loader-v21`
