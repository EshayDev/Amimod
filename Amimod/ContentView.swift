import Foundation
import SwiftUI

struct Executable: Identifiable, Hashable {
    var id: String { fullPath }
    let formattedName: String
    let fullPath: String
}

struct BenchmarkResult: Identifiable {
    let id = UUID()
    let patternSize: Int
    let hasWildcards: Bool
    let duration: Double
    let fileSize: Double

    var formattedDuration: String {
        if duration >= 1000 {
            return String(format: "%.1f s", duration / 1000)
        } else {
            return String(format: "%.0f ms", duration)
        }
    }

    var wildcardText: String {
        hasWildcards ? "Yes" : "No"
    }
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
    @State private var isBenchmarking: Bool = false
    @State private var showBenchmarkResults = false
    @State private var benchmarkResults: [BenchmarkResult] = []

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

    private func validateInputs() throws -> (
        selectedExecutable: Executable, patches: [HexPatchOperation]
    ) {
        guard !filePath.isEmpty else {
            throw HexPatch.HexPatchError.invalidInput(description: "File path cannot be empty.")
        }

        guard FileManager.default.fileExists(atPath: filePath) else {
            throw HexPatch.HexPatchError.invalidFilePath(description: "File does not exist.")
        }

        guard let selected = selectedExecutable else {
            throw HexPatch.HexPatchError.invalidInput(
                description: "Please select an executable from the list.")
        }

        if !usingImportedPatches && (findHex.isEmpty || replaceHex.isEmpty) {
            throw HexPatch.HexPatchError.emptyHexStrings
        }

        let patches: [HexPatchOperation] =
            usingImportedPatches
            ? importedPatches : [HexPatchOperation(findHex: findHex, replaceHex: replaceHex)]

        return (selected, patches)
    }

    private func validateAndPatch() {
        do {
            let (selectedExecutable, patches) = try validateInputs()
            let hexPatcher = HexPatch()

            if usingImportedPatches {
                applyPatch()
            } else {
                let totalMatches = try hexPatcher.countTotalMatches(
                    in: selectedExecutable.fullPath, patches: patches)

                if totalMatches > 1 {
                    confirmationMessage =
                        "\(totalMatches) matches have been found. Are you sure you want to continue with this patch?"
                    activeAlert = .confirmation
                } else if totalMatches == 1 {
                    applyPatch()
                } else {
                    throw HexPatch.HexPatchError.hexNotFound(
                        description: "No matches found for the provided hex pattern.")
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
        let patches: [HexPatchOperation] =
            usingImportedPatches
            ? importedPatches : [HexPatchOperation(findHex: findHex, replaceHex: replaceHex)]

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
                    formattedDuration = String(
                        format: "(Operation completed in %.1f seconds)", durationSeconds)
                } else if durationSeconds >= 0.001 {
                    let milliseconds = Double(durationNanoseconds) / 1_000_000
                    formattedDuration = String(
                        format: "(Operation completed in %.0f ms)", milliseconds)
                } else if durationSeconds >= 0.000001 {
                    let microseconds = Double(durationNanoseconds) / 1000
                    formattedDuration = String(
                        format: "(Operation completed in %.0f µs)", microseconds)
                } else {
                    let nanoseconds = durationNanoseconds
                    formattedDuration = "(\(nanoseconds) ns)"
                }
                print("Patch applied successfully \(formattedDuration).")

                DispatchQueue.main.async {
                    activeAlert = .message(
                        title: "Success",
                        message: "The binary was patched successfully.\n\(formattedDuration)")
                    isPatching = false
                }
            } catch let hexPatchError as HexPatch.HexPatchError {
                DispatchQueue.main.async {
                    activeAlert = .message(
                        title: "Error", message: hexPatchError.localizedDescription)
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

            Text("Developed with ♥ by TEAM EDiSO")
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
                    dialog.allowedFileTypes = [
                        "app", "vst", "vst3", "component", "audiounit", "framework", "plugin",
                        "kext", "bundle", "appex",
                    ]

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
                TextField(
                    usingImportedPatches ? "ⓘ Using imported hex notes." : "Find Hex",
                    text: $findHex
                )
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.leading)
                .disabled(usingImportedPatches)
                .onChange(of: findHex) { newValue in
                    findHex = newValue.components(separatedBy: .newlines).joined()
                }

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
                TextField(
                    usingImportedPatches ? "ⓘ Using imported hex notes." : "Replace Hex",
                    text: $replaceHex
                )
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.leading)
                .disabled(usingImportedPatches)
                .onChange(of: replaceHex) { newValue in
                    replaceHex = newValue.components(separatedBy: .newlines).joined()
                }

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

            if isPatching || isBenchmarking {
                HStack {
                    ZStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.5)
                            .opacity((isPatching || isBenchmarking) ? 1 : 0)
                    }
                    .frame(width: 20, height: 20)

                    Text(isPatching ? "Patching..." : "Benchmarking...")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
                .padding(.bottom, 16)
            } else {
                Button("Patch Hex") {
                    validateAndPatch()
                }
                .padding(.bottom, 16)
                .disabled(
                    executables.isEmpty || selectedExecutable == nil
                        || (usingImportedPatches && importedPatches.isEmpty))
            }
        }
        .frame(width: 500, height: 400)
        .fixedSize()
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
                        activeAlert = .message(
                            title: "Import Error", message: error.localizedDescription)
                    } catch {
                        activeAlert = .message(
                            title: "Import Error",
                            message: "An unexpected error occurred during import.")
                    }
                },
                onCancel: {
                    showImportSheet = false
                }
            )
        }
        .sheet(isPresented: $showBenchmarkResults) {
            BenchmarkResultsView(results: benchmarkResults)
        }
        .environmentObject(audioManager)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack {
                    Button(action: {
                        audioManager.togglePause()
                    }) {
                        Image(
                            systemName: audioManager.isPaused
                                ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    }
                    .help(audioManager.isPaused ? "Play Music" : "Pause Music")

                    Button(action: {
                        if usingImportedPatches {
                            importedPatches = []
                            usingImportedPatches = false
                        } else {
                            showImportSheet = true
                        }
                    }) {
                        Image(
                            systemName: usingImportedPatches
                                ? "xmark.circle.fill" : "square.and.arrow.down")
                    }
                    .help(usingImportedPatches ? "Clear Imported Hex Notes" : "Import Hex Notes")
                    .disabled(filePath.isEmpty)

                    Button(action: {
                        runBenchmark()
                    }) {
                        Image(systemName: "speedometer")
                    }
                    .help("Run Benchmark")
                    .disabled(isPatching || isBenchmarking)
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
                    throw HexPatch.HexPatchError.invalidInput(
                        description:
                            "'TO' found without surrounding hex strings at line \(index + 1).")
                }

                let findHexLine = lines[index - 1].trimmingCharacters(in: .whitespacesAndNewlines)
                    .uppercased()
                let replaceHexLine = lines[index + 1].trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).uppercased()

                guard !findHexLine.isEmpty else {
                    throw HexPatch.HexPatchError.invalidInput(
                        description: "Empty find hex string found around 'TO' at line \(index + 1)."
                    )
                }

                guard !replaceHexLine.isEmpty else {
                    throw HexPatch.HexPatchError.invalidInput(
                        description:
                            "Empty replace hex string found around 'TO' at line \(index + 1).")
                }

                let validFindHexCharacterSet = CharacterSet(charactersIn: "0123456789ABCDEF ?")
                guard
                    findHexLine.allSatisfy({
                        validFindHexCharacterSet.contains(UnicodeScalar(String($0))!)
                    })
                else {
                    throw HexPatch.HexPatchError.invalidHexString(
                        description: "Invalid characters in find hex string at line \(index + 1).")
                }

                let validReplaceHexCharacterSet = CharacterSet(charactersIn: "0123456789ABCDEF ?")
                guard
                    replaceHexLine.allSatisfy({
                        validReplaceHexCharacterSet.contains(UnicodeScalar(String($0))!)
                    })
                else {
                    throw HexPatch.HexPatchError.invalidHexString(
                        description:
                            "Invalid characters or wildcards (??) found in replace hex string at line \(index + 1)."
                    )
                }

                let patch = HexPatchOperation(findHex: findHexLine, replaceHex: replaceHexLine)
                patches.append(patch)
            }
        }

        guard !patches.isEmpty else {
            throw HexPatch.HexPatchError.invalidInput(
                description: "No valid hex patches found in the imported text.")
        }

        importedPatches = patches
        usingImportedPatches = true
    }

    private func isExecutableFile(_ url: URL) -> Bool {
        let path = url.path
        let fileManager = FileManager.default

        guard fileManager.isExecutableFile(atPath: path) else {
            return false
        }

        let pathExtension = url.pathExtension.lowercased()
        let nonExecutableExtensions = [
            "h", "hpp", "c", "cpp", "m", "mm", "swift", "plist", "strings",
            "txt", "md", "json", "xml", "nib", "xib", "storyboard",
            "png", "jpg", "jpeg", "gif", "ico", "icns", "tiff",
            "mp3", "wav", "aiff", "m4a", "mp4", "mov", "avi",
            "pdf", "rtf", "html", "css", "js", "py", "rb", "pl",
            "log", "conf", "cfg", "ini", "pem", "key", "cert",
            "swiftmodule", "swiftdoc", "swiftsourceinfo",
        ]

        if nonExecutableExtensions.contains(pathExtension) {
            return false
        }

        let fileName = url.lastPathComponent.lowercased()
        if fileName.hasPrefix(".") || fileName.contains("readme") || fileName.contains("license") {
            return false
        }

        if let fileHandle = try? FileHandle(forReadingFrom: url) {
            defer { try? fileHandle.close() }

            if let magicBytes = try? fileHandle.read(upToCount: 4) {
                if magicBytes.count >= 4 {
                    let magic = magicBytes.withUnsafeBytes { $0.load(as: UInt32.self) }
                    let machOMagics: [UInt32] = [
                        0xfeed_face,
                        0xfeed_facf,
                        0xcefa_edfe,
                        0xcffa_edfe,
                        0xcafe_babe,
                        0xbeba_feca,
                    ]
                    return machOMagics.contains(magic)
                }
            }
        }

        return false
    }

    private func listExecutables(in appBundlePath: String) -> [Executable] {
        let appBundleURL = URL(fileURLWithPath: appBundlePath)
        var executables: [Executable] = []

        let macosURL = appBundleURL.appendingPathComponent("Contents/MacOS")
        let frameworksURL = appBundleURL.appendingPathComponent("Contents/Frameworks")
        let launchServicesURL = appBundleURL.appendingPathComponent(
            "Contents/Library/LaunchServices")

        listExecutablesRecursively(in: macosURL, executables: &executables, rootFolder: "[MacOS]")
        listExecutablesRecursively(
            in: frameworksURL, executables: &executables, rootFolder: "[Frameworks]")
        listExecutablesRecursively(
            in: launchServicesURL, executables: &executables, rootFolder: "[LaunchServices]")

        return executables
    }

    private func listExecutablesRecursively(
        in directoryURL: URL, executables: inout [Executable], rootFolder: String
    ) {
        let fileManager = FileManager.default

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [URLResourceKey.typeIdentifierKey],
                options: []
            )

            for url in contents {
                do {
                    var isDirectory: ObjCBool = false
                    if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                        if isDirectory.boolValue {
                            let lastPathComponent = url.lastPathComponent
                            if lastPathComponent != "Resources" && lastPathComponent != "__MACOSX"
                                && lastPathComponent != "Current"
                                && lastPathComponent != "_CodeSignature"
                                && lastPathComponent != "CodeResources"
                                && lastPathComponent != "Headers"
                                && lastPathComponent != "Modules"
                                && lastPathComponent != "private"
                            {
                                listExecutablesRecursively(
                                    in: url,
                                    executables: &executables,
                                    rootFolder: rootFolder
                                )
                            }
                        } else {
                            if isExecutableFile(url) {
                                let formattedName = "\(rootFolder) \(url.lastPathComponent)"
                                let executable = Executable(
                                    formattedName: formattedName,
                                    fullPath: url.path
                                )
                                executables.append(executable)
                            }
                        }
                    }
                }
            }
        } catch {
            print("Error listing contents of \(directoryURL.path): \(error.localizedDescription)")
        }
    }

    private func createTempCopy(of url: URL) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "benchmark_\(UUID().uuidString)_\(url.lastPathComponent)"
        let tempURL = tempDir.appendingPathComponent(fileName)

        try FileManager.default.copyItem(at: url, to: tempURL)
        return tempURL
    }

    func runBenchmark() {
        isBenchmarking = true

        let patternLengths = [8, 16, 32, 64, 128, 256]
        let wildcardTests = [false, true]
        let numberOfRuns = 5

        DispatchQueue.global(qos: .userInitiated).async {
            var results: [BenchmarkResult] = []

            guard let selectedExecutablePath = selectedExecutable?.fullPath else {
                DispatchQueue.main.async {
                    activeAlert = .message(title: "Error", message: "No executable selected.")
                    isBenchmarking = false
                }
                return
            }

            let executableURL = URL(fileURLWithPath: selectedExecutablePath)

            do {
                let fileData = try Data(contentsOf: executableURL)
                let fileSizeInMB = Double(fileData.count) / (1024.0 * 1024.0)
                let hexPatcher = HexPatch()

                let tempURL = try createTempCopy(of: executableURL)
                defer { try? FileManager.default.removeItem(at: tempURL) }

                for patternLength in patternLengths {
                    for useWildcards in wildcardTests {
                        var durations: [Double] = []

                        for _ in 0..<numberOfRuns {
                            try fileData.write(to: tempURL)

                            let patternResult = getRandomHexPattern(
                                from: fileData,
                                length: patternLength,
                                withWildcards: useWildcards
                            )

                            guard let (findHex, replaceHex) = patternResult else {
                                print(
                                    "Skipping test: \(patternLength) bytes, wildcards \(useWildcards) - not enough data."
                                )
                                continue
                            }

                            let patch = HexPatchOperation(findHex: findHex, replaceHex: replaceHex)

                            let startTime = DispatchTime.now()
                            try hexPatcher.findAndReplaceHexStrings(
                                in: tempURL.path,
                                patches: [patch]
                            )
                            let endTime = DispatchTime.now()

                            let durationNanoseconds =
                                endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
                            let durationSeconds = Double(durationNanoseconds) / 1_000_000_000
                            durations.append(durationSeconds)
                        }

                        if !durations.isEmpty {
                            let averageDuration = durations.reduce(0, +) / Double(durations.count)

                            let durationInMs = averageDuration * 1000
                            let result = BenchmarkResult(
                                patternSize: patternLength,
                                hasWildcards: useWildcards,
                                duration: durationInMs,
                                fileSize: fileSizeInMB
                            )
                            results.append(result)
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    isBenchmarking = false
                    activeAlert = .message(
                        title: "Benchmark Error",
                        message: "Error during benchmark: \(error.localizedDescription)"
                    )
                }
                return
            }

            DispatchQueue.main.async {
                isBenchmarking = false
                benchmarkResults = results
                showBenchmarkResults = true
            }
        }
    }

    func getRandomHexPattern(from data: Data, length: Int, withWildcards: Bool = false) -> (
        findHex: String, replaceHex: String
    )? {
        guard data.count >= length else { return nil }

        let startIndex = Int.random(in: 0...(data.count - length))
        let endIndex = startIndex + length
        let subdata = data.subdata(in: startIndex..<endIndex)

        var findHex = ""
        var replaceHex = ""

        subdata.forEach { byte in
            findHex += String(format: "%02X ", byte)
            replaceHex += "00 "
        }

        if withWildcards {
            var findHexArray = findHex.components(separatedBy: " ")
            findHexArray.removeLast()
            let numWildcards = length / 4
            var wildcardIndices: [Int] = []
            if length > 2 {
                wildcardIndices = Array((1...(length - 2)).shuffled().prefix(numWildcards))
            }

            for index in wildcardIndices {
                findHexArray[index] = "??"
            }

            findHex = findHexArray.joined(separator: " ")
        }

        return (
            findHex, String(repeating: "00 ", count: length).trimmingCharacters(in: .whitespaces)
        )
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

struct BenchmarkResultsView: View {
    let results: [BenchmarkResult]
    @State private var showChart = false
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Benchmark Results")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button("Close") {
                    presentationMode.wrappedValue.dismiss()
                }
                .keyboardShortcut(.escape)
            }
            .padding()
            .background(Color.gray.opacity(0.1))

            Picker("", selection: $showChart) {
                Text("Table").tag(false)
                Text("Chart").tag(true)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()

            if showChart {
                chartView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                tableView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 800, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
    }

    private var tableView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Pattern Size")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Without Wildcards")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)
                Text("With Wildcards")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.2))

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    let groupedResults = Dictionary(grouping: results) { $0.patternSize }
                    let sortedSizes = groupedResults.keys.sorted()

                    ForEach(Array(sortedSizes.enumerated()), id: \.element) { index, patternSize in
                        let sizeResults = groupedResults[patternSize] ?? []
                        let withoutWildcards = sizeResults.first { !$0.hasWildcards }
                        let withWildcards = sizeResults.first { $0.hasWildcards }

                        HStack {
                            Text("\(patternSize) bytes")
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(withoutWildcards?.formattedDuration ?? "—")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.pink)
                                .frame(maxWidth: .infinity, alignment: .center)

                            Text(withWildcards?.formattedDuration ?? "—")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.purple)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(index % 2 == 0 ? Color.clear : Color.gray.opacity(0.05))

                        Divider()
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chartView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Performance Comparison")
                .font(.headline)
                .padding(.horizontal)

            GeometryReader { geometry in
                let maxDuration = results.map { $0.duration }.max() ?? 100
                let minDuration = results.map { $0.duration }.min() ?? 0
                let range = maxDuration - minDuration
                let width = geometry.size.width - 80
                let height = geometry.size.height - 80

                let gridInterval: Double = {
                    if range <= 6 {
                        return 0.5
                    } else if range <= 15 {
                        return 1.0
                    } else if range <= 50 {
                        return 5.0
                    } else if range <= 100 {
                        return 10.0
                    } else if range <= 250 {
                        return 25.0
                    } else if range <= 500 {
                        return 50.0
                    } else if range <= 1000 {
                        return 100.0
                    } else if range <= 2500 {
                        return 250.0
                    } else if range <= 5000 {
                        return 500.0
                    } else {
                        return 1000.0
                    }
                }()

                let gridStart: Double = 0
                let gridEnd = (maxDuration / gridInterval).rounded(.up) * gridInterval
                let gridCount = Int((gridEnd - gridStart) / gridInterval) + 1

                let totalSpacing = CGFloat(results.count - 1) * 6
                let availableWidth = width - totalSpacing
                let barWidth = availableWidth / CGFloat(results.count)

                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 8) {
                        ZStack(alignment: .bottomLeading) {
                            VStack(spacing: 0) {
                                ForEach(0..<gridCount, id: \.self) { i in
                                    let value = gridEnd - Double(i) * gridInterval
                                    HStack {
                                        Text(
                                            String(
                                                format: gridInterval < 1.0 ? "%.1f" : "%.0f", value)
                                        )
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                        .frame(width: 60, alignment: .trailing)
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.2))
                                            .frame(height: 1)
                                    }
                                    if i < gridCount - 1 {
                                        Spacer()
                                    }
                                }
                            }
                            .frame(height: height)

                            HStack(alignment: .bottom, spacing: 6) {
                                ForEach(results) { result in
                                    let barHeight = (result.duration / gridEnd) * height

                                    VStack(spacing: 2) {
                                        Text(result.formattedDuration)
                                            .font(.caption2)
                                            .foregroundColor(.primary)
                                            .fontWeight(.medium)

                                        Rectangle()
                                            .fill(result.hasWildcards ? Color.purple : Color.pink)
                                            .frame(width: barWidth, height: max(barHeight, 1))
                                            .animation(.easeInOut(duration: 0.5), value: barHeight)
                                    }
                                    .frame(width: barWidth, alignment: .center)
                                }
                            }
                            .padding(.leading, 70)
                        }
                        .frame(height: height)

                        HStack(spacing: 6) {
                            ForEach(results) { result in
                                VStack(spacing: 0) {
                                    Text("\(result.patternSize)")
                                        .font(.caption2)
                                        .foregroundColor(.primary)
                                    Text(result.hasWildcards ? "W" : "N")
                                        .font(.caption2)
                                        .foregroundColor(result.hasWildcards ? .purple : .pink)
                                        .fontWeight(.semibold)
                                }
                                .frame(width: barWidth, alignment: .center)
                            }
                        }
                        .padding(.leading, 60)
                    }

                    HStack(spacing: 20) {
                        HStack(spacing: 4) {
                            Rectangle()
                                .fill(Color.pink)
                                .frame(width: 12, height: 12)
                            Text("No Wildcards")
                                .font(.caption)
                        }
                        HStack(spacing: 4) {
                            Rectangle()
                                .fill(Color.purple)
                                .frame(width: 12, height: 12)
                            Text("With Wildcards")
                                .font(.caption)
                        }
                    }
                    .padding(.horizontal, 70)
                    .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
