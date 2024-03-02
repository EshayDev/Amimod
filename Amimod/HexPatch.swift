import Foundation

class HexPatch {
    func findAndReplaceHexStrings(in filePath: String, findHex: String, replaceHex: String) throws {
        var fileData = try Data(contentsOf: URL(fileURLWithPath: filePath))
        
        guard let findData = try Data(hex: findHex), let replaceData = try Data(hex: replaceHex) else {
            throw NSError(domain: "Invalid input", code: 0, userInfo: [NSLocalizedDescriptionKey: "Hex string is invalid."])
        }
        
        // Ensure that findData and replaceData have the same length
        guard findData.count == replaceData.count else {
            throw NSError(domain: "Invalid input", code: 0, userInfo: [NSLocalizedDescriptionKey: "Hex strings must have the same length for find and replace."])
        }
        
        var index = fileData.startIndex
        var found = false
        
        while index < fileData.endIndex {
            // Find the range of the pattern in the remaining data
            if let range = fileData[index...].range(of: findData) {
                // Replace the pattern with the replacement data
                fileData.replaceSubrange(range, with: replaceData)
                
                // Move the index to the end of the replacement data
                index = range.lowerBound + replaceData.count
                found = true
            } else {
                // No more occurrences found, exit the loop
                break
            }
        }
        
        if !found {
            throw NSError(domain: "Hex not found", code: 0, userInfo: [NSLocalizedDescriptionKey: "Hex string not found in the binary."])
        }
        
        try fileData.write(to: URL(fileURLWithPath: filePath))
    }
}

extension Data {
    init?(hex: String) throws {
        let hex = hex.replacingOccurrences(of: " ", with: "") // Remove spaces
        
        guard hex.count % 2 == 0 else {
            throw NSError(domain: "Invalid input", code: 0, userInfo: [NSLocalizedDescriptionKey: "Hex string must have an even number of characters."])
        }
        
        self.init()
        var index = hex.startIndex
        while index < hex.endIndex {
            let hexByte = String(hex[index ..< hex.index(index, offsetBy: 2)])
            index = hex.index(index, offsetBy: 2)
            
            guard let byte = UInt8(hexByte, radix: 16) else {
                throw NSError(domain: "Invalid input", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unable to convert hex byte '\(hexByte)' to an unsigned 8-bit integer."])
            }
            
            self.append(byte)
        }
    }
}
