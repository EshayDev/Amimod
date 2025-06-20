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
- Intelligent executable discovery that recursively scans MacOS, Frameworks, and LaunchServices directories
- Clean dropdown interface showing all available executables

### Advanced Patching Capabilities
- Multi-pattern patching - apply multiple hex patches in sequence
- Intelligent wildcard support using `??` - perfect for version-resilient patches across app updates
- Batch hex notes import in standard MSJ format
- Multiple match handling with confirmation prompts (up to 50,000 matches per pattern)

### Performance & Reliability
- SIMD-optimized Boyer-Moore-Horspool algorithm for lightning-fast searching
- Multi-threading with parallel chunk processing
- Can patch a 250MB binary in ~25ms while using max 50MB memory
- Built-in benchmarking tools with visual results
- Comprehensive error handling with detailed context

### User Experience
- Real-time progress tracking with timing information
- Intuitive interface designed for both beginners and experts
- Extensive validation to prevent data corruption

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
2. Click **"Select Bundle"** to choose a target file
3. Supported formats: `.app`, `.component`, `.audiounit`, `.vst`, `.vst3`, `.framework`, `.bundle`, `.kext`, `.appex`
4. Select an executable from the dropdown list

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
- Limits to 50,000 matches per pattern to prevent performance issues

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

## Benchmarking

The built-in benchmark tests patching performance across different scenarios:

1. Click the Speedometer icon (⏱️) in the toolbar
2. Tests pattern sizes from 8 to 256 bytes
3. Tests with and without wildcards
4. View results as charts or tables

## Performance Features

- **SIMD Instructions:** Uses 16-bit and 32-bit SIMD for faster searching
- **Boyer-Moore-Horspool:** Optimized string searching algorithm
- **Multi-threading:** Parallel processing across CPU cores
- **Chunk Management:** Dynamic sizing based on file size
- **Memory Efficiency:** Handles large files without excessive RAM usage

## System Requirements

| Component | Requirement |
|-----------|-------------|
| OS | macOS 11.0 (Big Sur) or later |
| Architecture | Intel x86_64 or Apple Silicon |
| Memory | 4GB RAM minimum |
| Storage | 30MB free space |

## Important Notes

- Amimod focuses purely on hex patching - it doesn't handle codesigning
- For codesigning after patching, consider using [Sentinel](https://itsalin.com/appInfo/?id=sentinel) or standard terminal commands
- The tool is provided free of charge under MIT license

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

**Graphics (App Icon & Logo):** 
- [EshayDev](https://github.com/EshayDev/)

**Music:**

- [Andromeda](https://demozoo.org/sceners/187/)
- [bboll](https://modarchive.org/module.php?134772)
- [Dubmood](https://demozoo.org/sceners/520/)
- [Dualtrax](https://demozoo.org/sceners/5763/)
- [Quazar](https://demozoo.org/sceners/17375/)
- [tj technoiZ](https://demozoo.org/sceners/17215/)
- [wasp](https://demozoo.org/sceners/11697/)
- [Zaiko](https://demozoo.org/sceners/38408/)

**App Testing:**
- [EshayDev](https://github.com/EshayDev/)
- [Antibiotics](https://github.com/Antibioticss/)
- [Sneethan](https://github.com/Sneethan/)
- [BruhgDev](https://github.com/BruhgDev/)

---
*This tool is provided free of charge. If you paid for this, you were scammed.*