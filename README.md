# 💜 Amimod
#### *A hex patching tool made for crackers, by crackers.*

Amimod is a hex patching tool for macOS. It scans app bundles, finds Mach‑O executables, and lets you patch them directly.

![macOS 11.0+](https://img.shields.io/badge/macOS-11.0+-blue?style=flat-square&logo=apple)
![Architecture](https://img.shields.io/badge/architecture-Intel%20%7C%20Apple%20Silicon-red?style=flat-square)
![MIT License](https://img.shields.io/badge/license-MIT-yellow?style=flat-square)
![Downloads](https://img.shields.io/github/downloads/EshayDev/Amimod/total?style=flat-square)

## What it does

- Works with `.app`, `.vst`, `.audiounit`, `.framework`, `.bundle`, `.kext`, and `.appex`
- Finds all Mach‑O executables inside a bundle and lists them in a dropdown
- Lets you patch bytes manually or import a batch of patches
- Supports wildcards (`??`) so your hex notes survive version bumps
- Handles multiple matches safely (asks before applying)
- Has a built‑in benchmarking tool if you care about speed
- Optional chiptune music (controls in the toolbar)

## Install

**Option 1: Download release**
1. Grab the latest DMG from [Releases](https://github.com/EshayDev/Amimod/releases/latest)  
2. Mount it  
3. Drag `Amimod.app` to Applications  

**Option 2: Build it yourself**
```bash
git clone https://github.com/EshayDev/Amimod.git
cd Amimod
# open Amimod.xcodeproj in Xcode
# build the target and copy Amimod.app to /Applications
```

## Usage

### Regular Patches

**Pick a bundle**
1. Open Amimod  
2. Click *Select Bundle*  
3. Choose your `.app` / `.component` / `.vst` / etc.  
4. Pick an executable from the dropdown  

**Start patching**
1. Enter the hex to find (e.g. `48 89 E5 41 57`)  
2. Enter the replacement (e.g. `90 90 90 90 90`)  
3. Hit *Patch Hex*  

---

### Wildcard Patches (`??`)

Wildcards let you write patches that still work when the app updates and some bytes shift around.  

**Scenario 1: App updated but you know the target pattern**  
```
Find:    48 89 ?? 5D C3
Replace: 90 90 90 90 90
```
The middle byte might change between versions, but your patch still lands.  

**Scenario 2: Keep variable data, change surrounding code**  
```
Find:    48 8B ?? ?? ?? ?? 89
Replace: 48 8B ?? ?? ?? ?? 90
```
Here the `??` placeholders keep the 4 unknown bytes intact, and you only change the last instruction.

---

### Batch Patches
Import MSJ‑style notes:
```
<find pattern>
to
<replace pattern>
```

Example:
```
x86_64:

31 C0 ?? ?? C3
to
31 C0 90 90 C3

ARM64:

?? ?? 80 52 C0 03 5F D6
to
20 00 80 52 C0 03 5F D6
```

---

### Benchmarking
- Toolbar → Speedometer → runs search tests with different pattern sizes  
- Results shown as table or chart  

## Safety notes

- Always patch a copy — Amimod writes in place  
- Doesn’t handle code signing. If you need to run patched apps, you’ll have to re‑sign them yourself.  
  - Use the usual `codesign` / `xattr` terminal commands  
  - Or try [Sentinel](https://github.com/alienator88/Sentinel) for a friendlier workflow  
- Find/replace patterns must be the same length  
- Won’t apply if there are more than 50k matches (safety check)  
- Only scans standard bundle paths  

## Requirements

| | |
|---|---|
| macOS | 11.0 (Big Sur) or later |
| CPU | Intel or Apple Silicon |
| RAM | 4GB+ recommended |
| Disk | ~10MB |

## Bugs / Suggestions

Open an issue here on GitHub if something’s broken or you’ve got an idea.

## Credits

**Code:**  
- [EshayDev](https://github.com/EshayDev/)  
- [Antibiotics](https://github.com/Antibioticss/)  

**Graphics:**  
- [EshayDev](https://github.com/EshayDev/)  

**Music:**  
- [Accel](https://demozoo.org/sceners/56884/)  
- [Andromeda](https://demozoo.org/sceners/187/)  
- [bboll](https://modarchive.org/module.php?134772)  
- [Dubmood](https://demozoo.org/sceners/520/)  
- [Dualtrax](https://demozoo.org/sceners/5763/)  
- [Estrayk](https://demozoo.org/sceners/10035/)  
- [Evelred](https://demozoo.org/sceners/428/)  
- [Graff](https://demozoo.org/sceners/12166/)  
- [LHS](https://demozoo.org/sceners/11387/)  
- [Mantronix](https://demozoo.org/sceners/791/)  
- [Quazar](https://demozoo.org/sceners/17375/)  
- [tj technoiZ](https://demozoo.org/sceners/17215/)  
- [wasp](https://demozoo.org/sceners/11697/)  
- [Zaiko](https://demozoo.org/sceners/38408/)  

**Testing:**  
- [EshayDev](https://github.com/EshayDev/)  
- [Antibiotics](https://github.com/Antibioticss/)  
- [Sneethan](https://github.com/Sneethan/)  
- [BruhgDev](https://github.com/BruhgDev/)  
- [√(noham)²](https://github.com/NohamR)  
- [piratx](https://github.com/piratx)  
- ThePhantomMac  
- skizzolfs  

---

*This tool is provided free of charge. If you paid for this, you were scammed.*  