import AppKit
import Foundation
import SwiftUI

struct Executable: Identifiable, Hashable {
    var id: String { fullPath }
    let formattedName: String
    let fullPath: String
}

struct ContentView: View {
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var titleMessage = ""
    @State private var filePath: String = ""
    @State private var findHex: String = ""
    @State private var replaceHex: String = ""
    @State private var selectedExecutable: Executable?
    @State private var executables: [Executable] = []

    private func validateAndPatch() throws {
        guard !filePath.isEmpty else {
            throw HexPatch.HexPatchError.invalidInput(description: "File path cannot be empty.")
        }

        guard FileManager.default.fileExists(atPath: filePath) else {
            throw HexPatch.HexPatchError.invalidFilePath(description: "File does not exist.")
        }

        guard !findHex.isEmpty && !replaceHex.isEmpty else {
            throw HexPatch.HexPatchError.emptyHexStrings
        }

        // Add code to list executables in the .app bundle
        executables = listExecutables(in: filePath)

        // Show a list of executables and let the user select one
        guard let selected = selectedExecutable else {
            throw HexPatch.HexPatchError.invalidInput(description: "Please select an executable from the list.")
        }

        let hexPatcher = HexPatch()
        do {
            try hexPatcher.findAndReplaceHexStrings(in: selected.fullPath, findHex: findHex, replaceHex: replaceHex)
            titleMessage = "Success"
            alertMessage = "The binary was patched successfully."
            showAlert = true
        } catch let hexPatchError as HexPatch.HexPatchError {
            titleMessage = "Error"
            alertMessage = hexPatchError.localizedDescription
            showAlert = true
        } catch {
            titleMessage = "Error"
            alertMessage = "An unexpected error occurred."
            showAlert = true
        }
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
                            // Exclude certain directories
                            let lastPathComponent = url.lastPathComponent
                            if lastPathComponent != "Resources" && lastPathComponent != "__MACOSX" && lastPathComponent != "Current" {
                                listExecutablesRecursively(in: url, executables: &executables, rootFolder: rootFolder)
                            }
                        } else {
                            // Check if it's an executable file based on UTI
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
            // Handle errors related to listing directory contents
            print("Error listing contents of \(directoryURL.path): \(error.localizedDescription)")
        }
    }

    private func isExecutableFile(atPath path: String) -> Bool {
        let fileManager = FileManager.default
        return fileManager.isExecutableFile(atPath: path)
    }

    private func refreshExecutables() {
        do {
            executables = listExecutables(in: filePath)
        }
    }

    var body: some View {
        @EnvironmentObject var audioManager: AudioManager
        VStack(alignment: .center, spacing: 20) {
            Image("Logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 480, height: 125)
                .padding(.top, 8)

            Text("Developed by EshayDev of TEAM EDiSO")
                .font(.system(size: 12))
                .foregroundColor(.gray)

            HStack {
                Button("Select App") {
                    let dialog = NSOpenPanel()
                    dialog.title = "Choose a .app bundle"
                    dialog.showsResizeIndicator = true
                    dialog.showsHiddenFiles = false
                    dialog.canChooseFiles = true // Allow selecting files
                    dialog.canChooseDirectories = true
                    dialog.allowedFileTypes = ["app"]

                    if dialog.runModal() == .OK {
                        if let result = dialog.url {
                            filePath = result.path
                            refreshExecutables() // Call the function to update the executables list
                            if let firstExecutable = executables.first {
                                selectedExecutable = firstExecutable
                            }
                        }
                    }
                }

                .padding([.leading, .trailing]) // Add horizontal padding

                if let selectedAppPath = filePath.isEmpty ? nil : URL(fileURLWithPath: filePath) {
                    let appIcon = NSWorkspace.shared.icon(forFile: selectedAppPath.path)
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)

                    // Display the selected app path and the app icon
                    Text("\(selectedAppPath.lastPathComponent)")
                        .foregroundColor(.primary)
                        .font(.system(size: 12))
                        .padding(.trailing) // Add horizontal padding
                }
            }

            // Add a Picker to select the executable from the list
            Picker("", selection: $selectedExecutable) {
                ForEach(executables, id: \.self) { executable in
                    Text(executable.formattedName).tag(executable as Executable?)
                }

                // Add a default option only if executables are empty
                if executables.isEmpty {
                    Text("N/A").tag(nil as Executable?)
                }
            }
            .padding(.leading, 8) // Add horizontal padding
            .padding(.trailing) // Add horizontal padding
            .disabled(executables.isEmpty) // Disable the Picker if no executables are available
            .onChange(of: executables) { newExecutables in
                if newExecutables.isEmpty && selectedExecutable != nil {
                    selectedExecutable = nil
                }
            }

            HStack {
                TextField("Find Hex", text: $findHex)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.leading) // Add horizontal padding

                Button(action: {
                    findHex = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
                .padding([.leading, .trailing]) // Add horizontal padding
                .contentShape(Rectangle())
            }

            HStack {
                TextField("Replace Hex", text: $replaceHex)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.leading) // Add horizontal padding

                Button(action: {
                    replaceHex = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
                .padding([.leading, .trailing]) // Add horizontal padding
                .contentShape(Rectangle())
            }

            Button("Patch Hex") {
                do {
                    try validateAndPatch()
                } catch let hexPatchError as HexPatch.HexPatchError {
                    titleMessage = "Error"
                    alertMessage = hexPatchError.localizedDescription
                } catch {
                    titleMessage = "Error"
                    alertMessage = "An unexpected error occurred."
                }
                showAlert = true
            }
            .padding(.bottom, 16) // Add bottom padding to the button
            .disabled(executables.isEmpty || selectedExecutable == nil) // Disable the button if no executables are available or none is selected
            .alert(isPresented: $showAlert) {
                Alert(title: Text(titleMessage), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
        }
        .frame(minWidth: 500, maxWidth: .infinity, minHeight: 450, maxHeight: .infinity) // Set the frame to allow the window to resize
        .onAppear {
            refreshExecutables() // Call the function when the view appears initially
        }
    }
}
