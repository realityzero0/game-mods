# Bingus Shared Loader v21 — FAQ

### Does this work with the latest Helldivers 2 update?
Yes. The October update removed the old audio hook and switched the game from LuaJIT to Lua 5.1. v21 hooks into `boot.lua` directly so the game launches and mods can load again.

### Do my old mods work automatically?
No. This loader fixes the startup crash, but old mods that used LuaJIT memory hacks (FFI) or precompiled bytecode will stay disabled until their authors update them for Lua 5.1. They won't crash your game, but their features won't work yet.

### Where is the Mod Options Menu? (F2 does nothing)
This loader is the backend that handles settings and mod discovery. The actual in-game menu UI is a separate mod made by CowboyBingus. You need that mod installed to see the visual menu.

### How do I install this?
1. Click the **Files** tab above.
2. Download the zip and import it into your mod manager (HD2 Mod Manager / HDArsenal / Vortex), set it to patch_0, and deploy.
3. If installing manually: extract the 3 files from `data/` (`9ba626afa44a3aa3.patch_0`, `.stream`, `.gpu_resources`) directly into `Helldivers 2/data/`.

### The game black screens or freezes on startup. What do I do?
That means another mod you have installed is crashing during startup. Remove your other mods from the `data/` folder, leave only `patch_0` (this loader), and boot the game. If it reaches the ship, add your mods back one by one to find the broken one.

### Can I get banned by Easy Anti-Cheat?
No. It's pure Lua running inside the engine's normal patch files. No DLL injection, no executable edits, no memory hacking. EAC is untouched.

### Does this work with Chef Shared Loader?
Yes. v21 has built-in handoff support for Chef Shared Loader 1.2.0+. If both are installed, they detect each other and run together without double-loading mods.

### Source code / License
Open source under the Zero-Clause BSD (0BSD) license:
https://github.com/realityzero0/Bingus-Shared-Loader-v21
