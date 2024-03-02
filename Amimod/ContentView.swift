import SwiftUI
import Foundation

struct ContentView: View {
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var titleMessage = ""
    @State private var filePath: String = ""
    @State private var findHex: String = ""
    @State private var replaceHex: String = ""
    
    private func validateAndPatch() throws {
        guard !filePath.isEmpty else {
            throw NSError(domain: "Invalid input", code: 0, userInfo: [NSLocalizedDescriptionKey: "File path cannot be empty."])
        }

        guard FileManager.default.fileExists(atPath: filePath) else {
            throw NSError(domain: "Invalid file path", code: 0, userInfo: [NSLocalizedDescriptionKey: "File does not exist."])
        }

        guard !findHex.isEmpty && !replaceHex.isEmpty else {
            throw NSError(domain: "Invalid input", code: 0, userInfo: [NSLocalizedDescriptionKey: "Hex fields cannot be empty."])
        }

        let hexPatcher = HexPatch()
            do {
                try hexPatcher.findAndReplaceHexStrings(in: filePath, findHex: findHex, replaceHex: replaceHex)
                }
                titleMessage = "Success"
                alertMessage = "The binary was patched successfully."
                showAlert = true
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
            
            TextField("File Path", text: $filePath)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding([.leading, .trailing]) // Add horizontal padding
            
            TextField("Find Hex", text: $findHex)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding([.leading, .trailing]) // Add horizontal padding
            
            TextField("Replace Hex", text: $replaceHex)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding([.leading, .trailing]) // Add horizontal padding
            
            Button("Patch Hex") {
                do {
                    try validateAndPatch()
                } catch let error as NSError {
                    titleMessage = "Error"
                    alertMessage = error.localizedDescription
                    showAlert = true
                } catch {
                    // Handle any other generic errors here
                    titleMessage = "Error"
                    alertMessage = "An unexpected error occurred."
                    showAlert = true
                }
            }
            .padding(.bottom, 8) // Add bottom padding to the button
            
            .padding()
            .alert(isPresented: $showAlert) {
                Alert(title: Text(titleMessage), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
        }
        .frame(minWidth: 500, maxWidth: .infinity, minHeight: 375, maxHeight: .infinity) // Set the frame to allow the window to resize
    }
}
