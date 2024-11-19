import Foundation
import SwiftUI

struct Executable: Identifiable, Hashable {
    var id: String { fullPath }
    let formattedName: String
    let fullPath: String
}

struct ContentView: View {
    @StateObject var audioManager = AudioManager.audioManager
    @State private var isPaused: Bool = false
    @State private var activeAlert: AlertType?
    @State private var alertMessage = ""
    @State private var titleMessage = ""
    @State private var filePath: String = ""
    @State private var findHex: String = ""
    @State private var replaceHex: String = ""
    @State private var selectedExecutable: Executable?
    @State private var executables: [Executable] = []
    @State private var showImportSheet = false
    @State private var importedPatches: [HexPatchOperation] = []
    @State private var usingImportedPatches: Bool = false
    @State private var isPatching: Bool = false
    @State private var confirmationMessage = ""

    enum AlertType: Identifiable {
        case confirmation
        case message(title: String, message: String)

        var id: Int {
            switch self {
            case .confirmation:
                return 0
            case .message:
                return 1
            }
        }
    }

    private func validateInputs() throws -> (selectedExecutable: Executable, patches: [HexPatchOperation]) {
        guard !filePath.isEmpty else {
            throw HexPatch.HexPatchError.invalidInput(description: "File path cannot be empty.")
        }

        guard FileManager.default.fileExists(atPath: filePath) else {
            throw HexPatch.HexPatchError.invalidFilePath(description: "File does not exist.")
        }

        guard let selected = selectedExecutable else {
            throw HexPatch.HexPatchError.invalidInput(description: "Please select an executable from the list.")
        }

        if !usingImportedPatches && (findHex.isEmpty || replaceHex.isEmpty) {
            throw HexPatch.HexPatchError.emptyHexStrings
        }

        let patches: [HexPatchOperation] = usingImportedPatches ? importedPatches : [HexPatchOperation(findHex: findHex, replaceHex: replaceHex)]

        return (selected, patches)
    }

    private func validateAndPatch() {
        do {
            let (selectedExecutable, patches) = try validateInputs()
            let hexPatcher = HexPatch()

            if usingImportedPatches {
                applyPatch()
            } else {
                let totalMatches = try hexPatcher.countTotalMatches(in: selectedExecutable.fullPath, patches: patches)

                if totalMatches > 1 {
                    confirmationMessage = "\(totalMatches) matches have been found. Are you sure you want to continue with this patch?"
                    activeAlert = .confirmation
                } else if totalMatches == 1 {
                    applyPatch()
                } else {
                    throw HexPatch.HexPatchError.hexNotFound(description: "No matches found for the provided hex pattern.")
                }
            }
        } catch let hexPatchError as HexPatch.HexPatchError {
            activeAlert = .message(title: "Error", message: hexPatchError.localizedDescription)
        } catch {
            activeAlert = .message(title: "Error", message: "An unexpected error occurred.")
        }
    }

    private func applyPatch() {
        let hexPatcher = HexPatch()
        guard let selected = selectedExecutable else {
            activeAlert = .message(title: "Error", message: "No executable selected.")
            return
        }
        let patches: [HexPatchOperation] = usingImportedPatches ? importedPatches : [HexPatchOperation(findHex: findHex, replaceHex: replaceHex)]

        isPatching = true
        let startTime = DispatchTime.now()

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try hexPatcher.findAndReplaceHexStrings(in: selected.fullPath, patches: patches)
                let endTime = DispatchTime.now()
                let durationNanoseconds = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
                let durationSeconds = Double(durationNanoseconds) / 1_000_000_000

                let formattedDuration: String
                if durationSeconds >= 1.0 {
                    formattedDuration = String(format: "(Operation completed in %.1f seconds)", durationSeconds)
                } else if durationSeconds >= 0.001 {
                    let milliseconds = Double(durationNanoseconds) / 1_000_000
                    formattedDuration = String(format: "(Operation completed in %.0f ms)", milliseconds)
                } else if durationSeconds >= 0.000001 {
                    let microseconds = Double(durationNanoseconds) / 1000
                    formattedDuration = String(format: "(Operation completed in %.0f µs)", microseconds)
                } else {
                    let nanoseconds = durationNanoseconds
                    formattedDuration = "(\(nanoseconds) ns)"
                }
                print("Patch applied successfully \(formattedDuration).")

                DispatchQueue.main.async {
                    activeAlert = .message(title: "Success", message: "The binary was patched successfully.\n\(formattedDuration)")
                    isPatching = false
                }
            } catch let hexPatchError as HexPatch.HexPatchError {
                DispatchQueue.main.async {
                    activeAlert = .message(title: "Error", message: hexPatchError.localizedDescription)
                    isPatching = false
                }
            } catch {
                DispatchQueue.main.async {
                    activeAlert = .message(title: "Error", message: "An unexpected error occurred.")
                    isPatching = false
                }
            }
        }
    }

    var body: some View {
        VStack(alignment: .center, spacing: 20) {
            Image("Logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 480, height: 125)
                .padding(.top, 8)

            Text("Developed by eD! of TEAM EDiSO")
                .font(.system(size: 12))
                .foregroundColor(.gray)

            HStack {
                Button("Select Bundle") {
                    let dialog = NSOpenPanel()
                    dialog.title = "Choose a bundle"
                    dialog.showsResizeIndicator = true
                    dialog.showsHiddenFiles = false
                    dialog.canChooseFiles = true
                    dialog.canChooseDirectories = false
                    dialog.allowedFileTypes = ["app", "vst", "vst3", "component", "audiounit", "framework", "plugin", "kext", "bundle", "appex"]

                    if dialog.runModal() == .OK {
                        if let result = dialog.url {
                            filePath = result.path
                            refreshExecutables()
                            if let firstExecutable = executables.first {
                                selectedExecutable = firstExecutable
                            }
                        }
                    }
                }
                .padding([.leading, .trailing])

                if !filePath.isEmpty, let selectedAppPath = URL(string: filePath) {
                    let appIcon = NSWorkspace.shared.icon(forFile: filePath)
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)

                    Text("\(selectedAppPath.lastPathComponent)")
                        .foregroundColor(.primary)
                        .font(.system(size: 12))
                        .padding(.trailing)
                }
            }

            Picker("", selection: $selectedExecutable) {
                ForEach(executables, id: \.self) { executable in
                    Text(executable.formattedName).tag(executable as Executable?)
                }

                if executables.isEmpty {
                    Text("N/A").tag(nil as Executable?)
                }
            }
            .padding(.leading, 8)
            .padding(.trailing)
            .disabled(executables.isEmpty)
            .onChange(of: executables) { newExecutables in
                if newExecutables.isEmpty && selectedExecutable != nil {
                    selectedExecutable = nil
                } else if selectedExecutable == nil, let first = newExecutables.first {
                    selectedExecutable = first
                }
            }

            HStack {
                TextField(usingImportedPatches ? "ⓘ Using imported hex notes." : "Find Hex", text: $findHex)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.leading)
                    .disabled(usingImportedPatches)

                Button(action: {
                    findHex = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
                .padding([.leading, .trailing])
                .contentShape(Rectangle())
                .disabled(usingImportedPatches)
            }

            HStack {
                TextField(usingImportedPatches ? "ⓘ Using imported hex notes." : "Replace Hex", text: $replaceHex)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.leading)
                    .disabled(usingImportedPatches)

                Button(action: {
                    replaceHex = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
                .padding([.leading, .trailing])
                .contentShape(Rectangle())
                .disabled(usingImportedPatches)
            }

            if isPatching {
                HStack {
                    ZStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.5)
                            .opacity(isPatching ? 1 : 0)
                    }
                    .frame(width: 20, height: 20)

                    Text("Patching...")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
                .padding(.bottom, 16)
            } else {
                Button("Patch Hex") {
                    validateAndPatch()
                }
                .padding(.bottom, 16)
                .disabled(executables.isEmpty || selectedExecutable == nil || (usingImportedPatches && importedPatches.isEmpty))
            }
        }
        .frame(minWidth: 500, idealWidth: 500, maxWidth: .infinity, minHeight: 400, idealHeight: 400, maxHeight: .infinity)
        .onAppear {
            refreshExecutables()
        }
        .sheet(isPresented: $showImportSheet) {
            ImportSheetView(
                importedPatches: $importedPatches,
                usingImportedPatches: $usingImportedPatches,
                onImport: { text in
                    do {
                        try importHexNotes(from: text)
                        showImportSheet = false
                    } catch let error as HexPatch.HexPatchError {
                        activeAlert = .message(title: "Import Error", message: error.localizedDescription)
                    } catch {
                        activeAlert = .message(title: "Import Error", message: "An unexpected error occurred during import.")
                    }
                },
                onCancel: {
                    showImportSheet = false
                }
            )
        }
        .environmentObject(audioManager)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack {
                    Button(action: {
                        audioManager.togglePause()
                    }) {
                        Image(systemName: audioManager.isPaused ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    }

                    Button(action: {
                        if usingImportedPatches {
                            importedPatches = []
                            usingImportedPatches = false
                        } else {
                            showImportSheet = true
                        }
                    }) {
                        Image(systemName: usingImportedPatches ? "xmark.circle.fill" : "square.and.arrow.down")
                    }
                    .help(usingImportedPatches ? "Clear Imported Hex Notes" : "Import Hex Notes")
                    .disabled(filePath.isEmpty)
                }
            }
        }
        .alert(item: $activeAlert) { alertType in
            switch alertType {
            case .confirmation:
                return Alert(
                    title: Text("Confirm Patch"),
                    message: Text(confirmationMessage),
                    primaryButton: .destructive(Text("Continue")) {
                        applyPatch()
                    },
                    secondaryButton: .cancel()
                )
            case let .message(title, message):
                return Alert(
                    title: Text(title),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private func importHexNotes(from text: String) throws {
        let lines = text.components(separatedBy: .newlines)
        var patches: [HexPatchOperation] = []

        for (index, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

            if trimmedLine == "TO" {
                guard index > 0, index < lines.count - 1 else {
                    throw HexPatch.HexPatchError.invalidInput(description: "'TO' found without surrounding hex strings at line \(index + 1).")
                }

                let findHexLine = lines[index - 1].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                let replaceHexLine = lines[index + 1].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

                guard !findHexLine.isEmpty else {
                    throw HexPatch.HexPatchError.invalidInput(description: "Empty find hex string found around 'TO' at line \(index + 1).")
                }

                guard !replaceHexLine.isEmpty else {
                    throw HexPatch.HexPatchError.invalidInput(description: "Empty replace hex string found around 'TO' at line \(index + 1).")
                }

                let validFindHexCharacterSet = CharacterSet(charactersIn: "0123456789ABCDEF ?")
                guard findHexLine.allSatisfy({ validFindHexCharacterSet.contains(UnicodeScalar(String($0))!) }) else {
                    throw HexPatch.HexPatchError.invalidHexString(description: "Invalid characters in find hex string at line \(index + 1).")
                }

                let validReplaceHexCharacterSet = CharacterSet(charactersIn: "0123456789ABCDEF ?")
                guard replaceHexLine.allSatisfy({ validReplaceHexCharacterSet.contains(UnicodeScalar(String($0))!) }) else {
                    throw HexPatch.HexPatchError.invalidHexString(description: "Invalid characters or wildcards (??) found in replace hex string at line \(index + 1).")
                }

                let patch = HexPatchOperation(findHex: findHexLine, replaceHex: replaceHexLine)
                patches.append(patch)
            }
        }

        guard !patches.isEmpty else {
            throw HexPatch.HexPatchError.invalidInput(description: "No valid hex patches found in the imported text.")
        }

        importedPatches = patches
        usingImportedPatches = true
    }

    private func listExecutables(in appBundlePath: String) -> [Executable] {
        let appBundleURL = URL(fileURLWithPath: appBundlePath)
        var executables: [Executable] = []

        let macosURL = appBundleURL.appendingPathComponent("Contents/MacOS")
        let frameworksURL = appBundleURL.appendingPathComponent("Contents/Frameworks")

        listExecutablesRecursively(in: macosURL, executables: &executables, rootFolder: "[MacOS]")
        listExecutablesRecursively(in: frameworksURL, executables: &executables, rootFolder: "[Frameworks]")

        return executables
    }

    private func listExecutablesRecursively(in directoryURL: URL, executables: inout [Executable], rootFolder: String) {
        let fileManager = FileManager.default

        do {
            let contents = try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: [URLResourceKey.typeIdentifierKey], options: [])

            for url in contents {
                do {
                    var isDirectory: ObjCBool = false
                    if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                        if isDirectory.boolValue {
                            let lastPathComponent = url.lastPathComponent
                            if lastPathComponent != "Resources" && lastPathComponent != "__MACOSX" && lastPathComponent != "Current" {
                                listExecutablesRecursively(in: url, executables: &executables, rootFolder: rootFolder)
                            }
                        } else {
                            if let typeIdentifier = try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier {
                                if typeIdentifier == "public.unix-executable" || typeIdentifier == "com.apple.mach-o-dylib" {
                                    let formattedName = "\(rootFolder) \(url.lastPathComponent)"
                                    let executable = Executable(formattedName: formattedName, fullPath: url.path)
                                    executables.append(executable)
                                }
                            }
                        }
                    }
                }
            }
        } catch {
            print("Error listing contents of \(directoryURL.path): \(error.localizedDescription)")
        }
    }

    private func refreshExecutables() {
        executables = listExecutables(in: filePath)
    }

    struct ImportSheetView: View {
        @Environment(\.presentationMode) var presentationMode
        @Binding var importedPatches: [HexPatchOperation]
        @Binding var usingImportedPatches: Bool
        @State private var pasteText: String = ""
        var onImport: (String) -> Void
        var onCancel: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 20) {
                Text("Paste the hex notes below:")
                    .font(.headline)

                TextEditor(text: $pasteText)
                    .font(.system(.body, design: .monospaced))
                    .padding(.vertical, 8)
                    .frame(height: 300)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.gray, lineWidth: 1)
                    )
                    .padding(.horizontal)

                HStack {
                    Spacer()
                    Button("Cancel") {
                        onCancel()
                    }
                    .padding(.trailing)

                    Button("Import") {
                        onImport(pasteText)
                    }
                    .disabled(pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding()
            .frame(width: 500, height: 400)
        }
    }
}
