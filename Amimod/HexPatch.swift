import Foundation

struct HexPatchOperation: Identifiable {
    let id = UUID()
    let findHex: String
    let replaceHex: String
}

class HexPatch {
    func findAndReplaceHexStrings(in filePath: String, patches: [HexPatchOperation]) throws {
        var fileBytes = try [UInt8](Data(contentsOf: URL(fileURLWithPath: filePath)))

        var replacementRanges: [(Range<Int>, [UInt8])] = []
        
        for patch in patches {
            let pattern = try parseHexPattern(patch.findHex)
            let replacement = try parseReplacementHex(patch.replaceHex, pattern: pattern)
            let matches = findPatternMatches(in: fileBytes, pattern: pattern)
            
            if matches.isEmpty {
                throw HexPatchError.hexNotFound(description: "Pattern not found: \(patch.findHex)")
            }
            
            for matchRange in matches {
                replacementRanges.append((matchRange, replacement))
            }
        }
        
        for (range, replacement) in replacementRanges.sorted(by: { $0.0.lowerBound > $1.0.lowerBound }) {
            fileBytes.replaceSubrange(range, with: replacement)
        }
        
        try Data(fileBytes).write(to: URL(fileURLWithPath: filePath))
    }
    
    func countTotalMatches(in filePath: String, patches: [HexPatchOperation]) throws -> Int {
        let fileBytes = try [UInt8](Data(contentsOf: URL(fileURLWithPath: filePath)))
        var totalMatches = 0
        
        for patch in patches {
            let pattern = try parseHexPattern(patch.findHex)
            let matches = findPatternMatches(in: fileBytes, pattern: pattern)
            
            totalMatches += matches.count
        }
        
        return totalMatches
    }
    
    private func parseHexPattern(_ hex: String) throws -> [UInt8?] {
        let cleanHex = preprocessHexString(hex)
        var pattern: [UInt8?] = []
        
        var index = cleanHex.startIndex
        while index < cleanHex.endIndex {
            guard let nextIndex = cleanHex.index(index, offsetBy: 2, limitedBy: cleanHex.endIndex) else {
                break
            }
            
            let byteRange = index..<nextIndex
            let byteString = String(cleanHex[byteRange])
            
            index = nextIndex
            
            if byteString == "??" {
                pattern.append(nil)
            } else {
                guard let byte = UInt8(byteString, radix: 16) else {
                    throw HexPatchError.invalidHexString(description: "Invalid hex byte: \(byteString)")
                }
                pattern.append(byte)
            }
        }
        
        if index != cleanHex.endIndex {
            throw HexPatchError.invalidInput(description: "Hex string has an odd number of characters.")
        }
        
        return pattern
    }
    
    private func parseReplacementHex(_ hex: String, pattern: [UInt8?]) throws -> [UInt8] {
        let cleanHex = preprocessHexString(hex)
        var replacement: [UInt8] = []
        
        var index = cleanHex.startIndex
        while index < cleanHex.endIndex {
            guard let nextIndex = cleanHex.index(index, offsetBy: 2, limitedBy: cleanHex.endIndex) else {
                break
            }
            
            let byteRange = index..<nextIndex
            let byteString = String(cleanHex[byteRange])
            
            index = nextIndex
            
            if byteString == "??" {
                throw HexPatchError.invalidHexString(description: "Replace hex cannot contain wildcards (??).")
            }
            
            guard let byte = UInt8(byteString, radix: 16) else {
                throw HexPatchError.invalidHexString(description: "Invalid hex byte in replacement: \(byteString)")
            }
            replacement.append(byte)
        }
        
        if replacement.count != pattern.count {
            throw HexPatchError.hexStringLengthMismatch(description: "Replace hex must have the same number of bytes as find hex.")
        }
        
        if index != cleanHex.endIndex {
            throw HexPatchError.invalidInput(description: "Hex string has an odd number of characters.")
        }
        
        return replacement
    }
    
    private func findPatternMatches(in data: [UInt8], pattern: [UInt8?]) -> [Range<Int>] {
        var matches: [Range<Int>] = []
        let patternLength = pattern.count
        let dataCount = data.count

        guard patternLength > 0, dataCount >= patternLength else {
            return matches
        }

        let fixedByteIndices = pattern.indices.filter { pattern[$0] != nil }
        if fixedByteIndices.isEmpty {
            for index in 0...(dataCount - patternLength) {
                matches.append(index..<(index + patternLength))
            }
            return matches
        }

        let firstFixed = fixedByteIndices.first!
        let firstByteValue = pattern[firstFixed]!

        for index in 0...(dataCount - patternLength) {
            if data[index + firstFixed] != firstByteValue {
                continue
            }

            var isMatch = true
            for offset in fixedByteIndices.dropFirst() {
                if data[index + offset] != pattern[offset]! {
                    isMatch = false
                    break
                }
            }

            if isMatch {
                matches.append(index..<(index + patternLength))
            }
        }

        return matches
    }
    
    private func preprocessHexString(_ hex: String) -> String {
        return hex.replacingOccurrences(of: " ", with: "").uppercased()
    }
    
    enum HexPatchError: Error {
        case emptyHexStrings
        case hexStringLengthMismatch(description: String)
        case invalidHexString(description: String)
        case hexNotFound(description: String)
        case userCancelled(description: String)
        case invalidInput(description: String)
        case invalidFilePath(description: String)
        
        var localizedDescription: String {
            switch self {
            case .emptyHexStrings:
                return "Hex fields cannot be empty."
            case .hexStringLengthMismatch(let description):
                return description
            case .invalidHexString(let description):
                return description
            case .hexNotFound(let description):
                return description
            case .userCancelled(let description):
                return description
            case .invalidInput(let description):
                return description
            case .invalidFilePath(let description):
                return description
            }
        }
    }
}
