import Foundation

class HexPatch {
    func findAndReplaceHexStrings(in filePath: String, findHex: String, replaceHex: String) throws {
        guard !findHex.isEmpty, !replaceHex.isEmpty else {
            throw HexPatchError.emptyHexStrings
        }

        guard findHex.count == replaceHex.count else {
            throw HexPatchError.hexStringLengthMismatch
        }

        var fileData = try Data(contentsOf: URL(fileURLWithPath: filePath))
            
        guard let findData = try Data(hex: findHex), let replaceData = try Data(hex: replaceHex) else {
            throw HexPatchError.invalidHexString
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
            throw HexPatchError.hexNotFound
        }

        try fileData.write(to: URL(fileURLWithPath: filePath))
    }

    enum HexPatchError: Error {
        case emptyHexStrings
        case hexStringLengthMismatch
        case invalidHexString
        case hexNotFound
        case invalidInput(description: String)
        case invalidFilePath(description: String)

        var localizedDescription: String {
            switch self {
            case .emptyHexStrings:
                return "Hex fields cannot be empty."
            case .hexStringLengthMismatch:
                return "Hex strings must have the same length for find and replace."
            case .invalidHexString:
                return "One or more hex strings are invalid."
            case .hexNotFound:
                return "Hex string not found in the binary."
            case let .invalidInput(description):
                return description
            case let .invalidFilePath(description):
                return description
            }
        }
    }
}

extension Data {
    init?(hex: String) throws {
        let hex = hex.replacingOccurrences(of: " ", with: "")
        
        guard hex.count % 2 == 0 else {
            throw HexPatch.HexPatchError.invalidInput(description: "Hex string must have an even number of characters.")
        }
        
        self.init()
        var index = hex.startIndex
        while index < hex.endIndex {
            let hexByte = String(hex[index ..< hex.index(index, offsetBy: 2)])
            index = hex.index(index, offsetBy: 2)
            
            guard let byte = UInt8(hexByte, radix: 16) else {
                throw HexPatch.HexPatchError.invalidInput(description: "Unable to convert hex byte '\(hexByte)' to an unsigned 8-bit integer.")
            }
            
            self.append(byte)
        }
    }
}
