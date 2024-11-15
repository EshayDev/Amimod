import Foundation

struct HexPatchOperation: Identifiable {
    let id = UUID()
    let findHex: String
    let replaceHex: String
}

class HexPatch {
    let chunkSize: Int
    var overlap: Int
    
    init(chunkSize: Int = 100 * 1024 * 1024) {
        self.chunkSize = chunkSize
        self.overlap = 0
    }
    
    func findAndReplaceHexStringsInPlace(
        in filePath: String,
        patches: [HexPatchOperation]
    ) throws {
        guard !patches.isEmpty else { return }
        
        let maxPatternLength = patches.compactMap { try? parseHexPattern($0.findHex).count }.max() ?? 4
        let overlap = maxPatternLength - 1
        self.overlap = overlap
        
        let fileURL = URL(fileURLWithPath: filePath)
        guard let fileHandle = try? FileHandle(forUpdating: fileURL) else {
            throw HexPatchError.invalidFilePath(description: "Unable to open file for updating.")
        }
        defer { fileHandle.closeFile() }
        
        let fileSize = try FileManager.default.attributesOfItem(atPath: filePath)[.size] as? UInt64 ?? 0
        var fileOffset: UInt64 = 0
        var previousBufferSuffix = Data()
        
        let parsedPatches = try patches.map { try ParsedPatch(patch: $0) }
        
        while fileOffset < fileSize {
            let readSize = min(UInt64(chunkSize), fileSize - fileOffset)
            fileHandle.seek(toFileOffset: fileOffset)
            let currentData = fileHandle.readData(ofLength: Int(readSize))
            
            var buffer = previousBufferSuffix + currentData
            
            let isLastChunk = (fileOffset + UInt64(chunkSize)) >= fileSize
            if !isLastChunk {
                let retainRange = buffer.count - overlap..<buffer.count
                previousBufferSuffix = buffer.subdata(in: retainRange)
                buffer = buffer.subdata(in: 0..<(buffer.count - overlap))
            } else {
                previousBufferSuffix = Data()
            }
            
            let byteArray = [UInt8](buffer)
            var modifiedBytes = byteArray
            
            for parsedPatch in parsedPatches {
                let matches = findPatternMatches(in: byteArray, pattern: parsedPatch.pattern)
                for matchRange in matches {
                    for (offset, repByte) in parsedPatch.replacement.enumerated() {
                        let index = matchRange.lowerBound + offset
                        if let byte = repByte, index < modifiedBytes.count {
                            modifiedBytes[index] = byte
                        }
                    }
                }
            }
            
            if modifiedBytes != byteArray {
                fileHandle.seek(toFileOffset: fileOffset)
                try fileHandle.write(contentsOf: Data(modifiedBytes))
            }
            
            fileOffset += UInt64(chunkSize)
        }
    }
    
    func countTotalMatchesInPlace(
        in filePath: String,
        patches: [HexPatchOperation]
    ) throws -> Int {
        guard !patches.isEmpty else { return 0 }
        
        let maxPatternLength = patches.compactMap { try? parseHexPattern($0.findHex).count }.max() ?? 4
        let overlap = maxPatternLength - 1
        
        let fileURL = URL(fileURLWithPath: filePath)
        guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else {
            throw HexPatchError.invalidFilePath(description: "Unable to open file for reading.")
        }
        defer { fileHandle.closeFile() }
        
        let fileSize = try FileManager.default.attributesOfItem(atPath: filePath)[.size] as? UInt64 ?? 0
        var fileOffset: UInt64 = 0
        var previousBufferSuffix = Data()
        var totalMatches = 0
        
        let parsedPatches = try patches.map { try ParsedPatch(patch: $0) }
        
        while fileOffset < fileSize {
            let readSize = min(UInt64(chunkSize), fileSize - fileOffset)
            fileHandle.seek(toFileOffset: fileOffset)
            let currentData = fileHandle.readData(ofLength: Int(readSize))
            
            var buffer = previousBufferSuffix + currentData
            
            let isLastChunk = (fileOffset + UInt64(chunkSize)) >= fileSize
            if !isLastChunk {
                let retainRange = buffer.count - overlap..<buffer.count
                previousBufferSuffix = buffer.subdata(in: retainRange)
                buffer = buffer.subdata(in: 0..<(buffer.count - overlap))
            } else {
                previousBufferSuffix = Data()
            }
            
            let byteArray = [UInt8](buffer)
            
            for parsedPatch in parsedPatches {
                let matches = findPatternMatches(in: byteArray, pattern: parsedPatch.pattern)
                totalMatches += matches.count
            }
            
            fileOffset += UInt64(chunkSize)
        }
        
        return totalMatches
    }
    
    private struct ParsedPatch {
        let pattern: [UInt8?]
        let replacement: [UInt8?]
        
        init(patch: HexPatchOperation) throws {
            self.pattern = try HexPatch().parseHexPattern(patch.findHex)
            self.replacement = try HexPatch().parseReplacementHex(patch.replaceHex, pattern: pattern)
        }
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
        guard let firstByteValue = pattern[firstFixed] else { return matches }

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
    
    private func parseReplacementHex(_ hex: String, pattern: [UInt8?]) throws -> [UInt8?] {
        let cleanHex = preprocessHexString(hex)
        var replacement: [UInt8?] = []
        
        var index = cleanHex.startIndex
        var patternIndex = 0
        
        while index < cleanHex.endIndex {
            guard let nextIndex = cleanHex.index(index, offsetBy: 2, limitedBy: cleanHex.endIndex) else {
                break
            }
            
            let byteRange = index..<nextIndex
            let byteString = String(cleanHex[byteRange])
            
            index = nextIndex
            
            if byteString == "??" {
                if patternIndex >= pattern.count {
                    throw HexPatchError.hexStringLengthMismatch(description: "Replace hex has more bytes than find hex.")
                }
                if pattern[patternIndex] != nil {
                    throw HexPatchError.invalidHexString(description: "Replace hex contains wildcard '??' at position \(patternIndex + 1), but find hex does not.")
                }
                replacement.append(nil)
            } else {
                guard let byte = UInt8(byteString, radix: 16) else {
                    throw HexPatchError.invalidHexString(description: "Invalid hex byte in replacement: \(byteString)")
                }
                replacement.append(byte)
            }
            patternIndex += 1
        }
        
        if patternIndex != pattern.count {
            throw HexPatchError.hexStringLengthMismatch(description: "Replace hex must have the same number of bytes as find hex.")
        }
        
        if index != cleanHex.endIndex {
            throw HexPatchError.invalidInput(description: "Hex string has an odd number of characters.")
        }
        
        return replacement
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
