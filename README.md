# 💛 Amimod
**A hex patching tool made for crackers, by crackers.**

## Features

- **App Selector:** Choose a `.app` bundle for patching.
- **List Executables:** Displays a list of executable files within the selected `.app` bundle, including files from the `MacOS` and `Frameworks` directories.
- **Patch Hex:** Find and replace hexadecimal strings in the selected executable, with support for multiple patches and confirmation when multiple matches are detected.
- **Hex Notes Import:** Import and apply multiple hex patches from a text file or manual input, simplifying batch patching.
- **Wildcard Support:** Use wildcards (`??`) in your hex patterns to match any byte in the target file.
- **Error Handling:** Provides detailed error messages to assist users in identifying and rectifying any issues, including invalid hex strings or mismatches.
- **Progress Indicator:** Displays a progress indicator while the patching process is in progress, keeping the user informed of the current status.

## Tutorial

This section will guide you through the different ways to use Amimod, including manual hex patching, importing hex notes, and using wildcard bytes.

### Step 1: Selecting an App Bundle

1. Launch **Amimod**.
2. Click the "Select App" button to open a file dialog.
3. Choose the `.app` bundle you want to patch. Amimod will automatically scan the bundle and list all executable files under `Contents/MacOS` and `Contents/Frameworks`.
4. Select the executable you want to patch from the dropdown list.

### Step 2: Manual Hex Find and Replace

Amimod allows you to manually input hex patterns to find and replace within the selected executable.

#### Example:

1. In the "Find Hex" field, enter the hex pattern you want to search for. For example, `48 89 E5`.
2. In the "Replace Hex" field, enter the hex pattern you want to replace it with. For example, `90 90 90` (NOP instructions).
3. Click "Patch Hex" to apply the patch.

#### Wildcard Bytes (`??`):

Amimod supports wildcard bytes (`??`) in the "Find Hex" field. Wildcards allow you to specify a byte that can match **any** value, which is useful if the target pattern contains variable or unknown bytes.

##### Example with Wildcards:

- **Find Hex:** `48 89 ?? 5D`
- **Replace Hex:** `90 90 90 90`

In this case, the `??` will match any byte in the third position, allowing for flexibility in the search pattern.

#### Handling Multiple Matches:

- If Amimod finds multiple matches for the provided hex pattern, it will ask for confirmation before proceeding. You will be notified of the number of matches, and you can choose whether to continue or cancel the patching process.

### Step 3: Importing Hex Notes

Amimod allows you to import multiple hex patches from a text file or manual input. This is useful for applying a series of patches at once.

#### Hex Notes Format:

Hex notes should follow a loose format for Amimod to recognize them:

```
<find hex>
to
<replace hex>
```

Each patch should consist of the hex string you want to find, followed by the keyword `to`, and then the hex string you want to replace it with. As long as the chunk(s) of 3 lines are together, any other text will be ignored and will not cause any errors.

##### Example Hex Notes:

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

#### How to Import Hex Notes:

1. Click the "Import" button (represented by a **square and arrow down** icon in the toolbar).
2. Paste your hex notes into the provided text editor in the import sheet.
3. Click "Import" to load the patches.
4. Amimod will now use the imported patches instead of manual input.
5. Click "Patch Hex" to apply all imported patches to the selected executable.

### Step 4: Applying the Patch

Once you've either manually entered hex patterns or imported hex notes, click the "Patch Hex" button to apply the patch to the selected executable.

- If the patch is successful, Amimod will display a success message.
- If there are any errors (e.g., no matches found, invalid hex string, etc.), Amimod will show a detailed error message to help you troubleshoot.

### Step 5: Monitoring Progress

While the patch is being applied, a progress indicator will appear at the bottom of the window, informing you that the patching process is in progress (often not even noticeable due to the speed of newer Macs). Once completed, you'll receive a success or error n

## Requirements

- A Mac with an Intel or Apple Silicon processor
- macOS 11.0 (Big Sur) or later

## Installation Instructions

### Using the Latest Release

- Grab the latest release from [here](https://github.com/EshayDev/Amimod/releases/latest).
- Mount the DMG.
- Drag `Amimod.app` to the Applications folder.

### Compiling from Source

1. Clone the repository.
2. Open the Xcode project.
3. Build and archive the `Amimod` target.
4. Copy the generated `Amimod.app` to the `/Applications` directory.

## License

- This tool is provided for internal use within **TEAM EDiSO** and their associates.<br>
- This repo can be forked and modified so long as original credit is given. All rights reserved.

## Credits
- **Code:** [eD!](https://github.com/EshayDev/)
- **Graphics:** [eD!](https://github.com/EshayDev/)
- **Music:** [OMICRON](https://0micron.bandcamp.com/)