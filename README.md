# 💜 Amimod
#### *A hex patching tool made for crackers, by crackers.*

Amimod is a powerful, modern hex patching application designed specifically for macOS. Built with performance and ease of use in mind, it's the perfect tool for anyone who needs reliable binary patching capabilities.

![macOS 11.0+](https://img.shields.io/badge/macOS-11.0+-blue?style=flat-square&logo=apple)
![Architecture](https://img.shields.io/badge/architecture-Intel%20%7C%20Apple%20Silicon-red?style=flat-square)
![MIT License](https://img.shields.io/badge/license-MIT-yellow?style=flat-square)
![Downloads](https://img.shields.io/github/downloads/EshayDev/Amimod/total?style=flat-square)

## Features

### Bundle Support & Discovery
- Support for apps, VSTs, AudioUnits, frameworks, system extensions, and more
- Recursively scans `Contents/MacOS`, `Contents/Frameworks`, and `Contents/Library/LaunchServices`
- Dropdown interface listing all discovered Mach-O executables

### Advanced Patching Capabilities
- Multi-pattern patching - apply multiple hex patches in sequence
- Intelligent wildcard support using `??` - perfect for version-resilient patches across app updates
- Batch hex notes import in standard MSJ format
- Multiple match handling with confirmation prompts (up to 50,000 matches per pattern)

### Performance & Reliability
- Parallel chunk processing across CPU cores
- Efficient byte searching using libc primitives (memchr/memcmp) with anchored checks
- Dynamic chunk sizing and overlap management to avoid missed matches
- Built-in benchmarking UI with chart and table views
- Clear error messages and input validation

### Polished UX
- Real-time status for patching/benchmarking
- Toolbar actions for music toggle, import hex notes, and benchmarking
- Optional background music (toggle via the speaker icon)

## Installation

### Using the Latest Release

1. Download the latest release from [here](https://github.com/EshayDev/Amimod/releases/latest)
2. Mount the DMG file
3. Drag `Amimod.app` to your Applications folder

### Compiling from Source

```bash
git clone https://github.com/EshayDev/Amimod.git
cd Amimod
# Open Amimod.xcodeproj in Xcode
# Build and archive the Amimod target
# Copy Amimod.app to /Applications
```

## Usage

### Selecting a Bundle

1. Launch Amimod
2. Click "Select Bundle" and choose a target bundle
3. Supported: `.app`, `.component`, `.audiounit`, `.vst`, `.vst3`, `.framework`, `.bundle`, `.kext`, `.appex`
4. Pick an executable from the dropdown

### Manual Hex Patching

1. **Find Hex:** Enter the pattern to search for (eg. `48 89 E5 41 57`)
2. **Replace Hex:** Enter the replacement pattern (eg. `90 90 90 90 90`)
3. Click **"Patch Hex"** to apply

### Wildcard Usage

Amimod's wildcard system is designed for creating patches that survive app updates:

**Scenario 1: App updated but you know the target pattern**
```
Find:    48 89 ?? 5D C3    // Middle byte might have changed between versions
Replace: 90 90 90 90 90    // But we know exactly what we want to patch it to
```

**Scenario 2: Preserving variable data while modifying surrounding code**
```
Find:    48 8B ?? ?? ?? ?? 89    // Keep the middle 4 bytes intact
Replace: 48 8B ?? ?? ?? ?? 90    // Only change the last instruction
```

This makes it easy to create generic patches that work across multiple app versions, automatically adapting to slight changes in assembly code while preserving critical variable data.

### Multiple Matches

When multiple matches are found:
- Shows match count before applying
- Asks for confirmation

### Batch Hex Notes

Import multiple patches using this format:

```
<find hex pattern>
to
<replace hex pattern>
```

**Example:**
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

**To import:**
1. Click the Import button (📥) in the toolbar
2. Paste hex notes into the editor
3. Click "Import" to load and validate patches
4. Click "Patch Hex" to apply all patches

### Benchmarking
- Toolbar → Speedometer → runs tests across pattern sizes (8–256 bytes) with/without wildcards
- Results can be viewed as a table or chart

## Safety & Limitations
- Patching is in-place. Always work on a copy and keep backups
- Code signing is not handled by Amimod. Re-sign externally if needed
- Replace and Find patterns must be the same length
- Too many matches (> 50,000 per pattern) are rejected for safety and performance
- Executable discovery only scans the bundle locations listed above

## System Requirements

| Component | Requirement |
|-----------|-------------|
| OS | macOS 11.0 (Big Sur) or later |
| Architecture | Intel (x86_64) or Apple Silicon (ARM64)|
| Memory | 4GB RAM recommended |
| Storage | 10MB free space |

## Bug Reports & Suggestions

Found a bug or have a feature request? Open an issue here on the GitHub repository. This project is actively maintained and community feedback is always welcome.

## License

**MIT License**

Copyright (c) 2025 TEAM EDiSO & Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

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