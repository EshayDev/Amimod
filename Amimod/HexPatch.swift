import Foundation

struct HexPatchOperation: Identifiable {
    let id = UUID()
    let findHex: String
    let replaceHex: String
}

class HexPatch {
    private let chunkSize = 100 * 1024 * 1024

    func findAndReplaceHexStrings(in filePath: String, patches: [HexPatchOperation]) throws {
        let fileURL = URL(fileURLWithPath: filePath)
        let fileSize = try FileManager.default.attributesOfItem(atPath: filePath)[.size] as! UInt64
        let fileHandle = try FileHandle(forUpdating: fileURL)
        defer { try? fileHandle.close() }

        let maxPatternLength = try patches.compactMap { try parseHexPattern($0.findHex).count }.max() ?? 0

        var allReplacements: [(offset: UInt64, replacement: [UInt8?])] = []
        var processedBytes: UInt64 = 0

        while processedBytes < fileSize {
            let remainingBytes = fileSize - processedBytes
            let currentChunkSize = UInt64(min(chunkSize, Int(remainingBytes)))

            try fileHandle.seek(toOffset: processedBytes)

            let overlapSize = UInt64(maxPatternLength - 1)
            let readSize = min(currentChunkSize + overlapSize, fileSize - processedBytes)
            guard let chunkData = try fileHandle.read(upToCount: Int(readSize)) else {
                throw HexPatchError.invalidInput(description: "Failed to read chunk from file")
            }

            var chunkBytes = [UInt8](chunkData)

            for patch in patches {
                let pattern = try parseHexPattern(patch.findHex)
                let replacement = try parseReplacementHex(patch.replaceHex, pattern: pattern)

                let searchEndIndex = Int(currentChunkSize)
                let matches = findPatternMatches(in: chunkBytes, pattern: pattern, endIndex: searchEndIndex)

                if matches.isEmpty, processedBytes == 0 {
                    throw HexPatchError.hexNotFound(description: "Pattern not found: \(patch.findHex)")
                }

                for matchRange in matches {
                    let fileOffset = processedBytes + UInt64(matchRange.lowerBound)
                    allReplacements.append((offset: fileOffset, replacement: replacement))
                }
            }

            processedBytes += currentChunkSize
        }

        allReplacements.sort { $0.offset > $1.offset }

        for (offset, replacement) in allReplacements {
            try fileHandle.seek(toOffset: offset)

            var bytesToWrite: [UInt8] = []
            for (index, repByte) in replacement.enumerated() {
                if let byte = repByte {
                    bytesToWrite.append(byte)
                } else {
                    try fileHandle.seek(toOffset: offset + UInt64(index))
                    guard let originalByte = try fileHandle.read(upToCount: 1)?.first else {
                        throw HexPatchError.invalidInput(description: "Failed to read original byte for wildcard")
                    }
                    bytesToWrite.append(originalByte)
                }
            }

            try fileHandle.seek(toOffset: offset)
            try fileHandle.write(contentsOf: bytesToWrite)
        }

        try fileHandle.synchronize()
    }

    func countTotalMatches(in filePath: String, patches: [HexPatchOperation]) throws -> Int {
        let fileURL = URL(fileURLWithPath: filePath)
        let fileSize = try FileManager.default.attributesOfItem(atPath: filePath)[.size] as! UInt64
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? fileHandle.close() }

        let maxPatternLength = try patches.compactMap { try parseHexPattern($0.findHex).count }.max() ?? 0
        var totalMatches = 0
        var processedBytes: UInt64 = 0

        while processedBytes < fileSize {
            let remainingBytes = fileSize - processedBytes
            let currentChunkSize = UInt64(min(chunkSize, Int(remainingBytes)))

            try fileHandle.seek(toOffset: processedBytes)

            let overlapSize = UInt64(maxPatternLength - 1)
            let readSize = min(currentChunkSize + overlapSize, fileSize - processedBytes)
            guard let chunkData = try fileHandle.read(upToCount: Int(readSize)) else {
                throw HexPatchError.invalidInput(description: "Failed to read chunk from file")
            }

            let chunkBytes = [UInt8](chunkData)

            for patch in patches {
                let pattern = try parseHexPattern(patch.findHex)
                let searchEndIndex = Int(currentChunkSize)
                let matches = findPatternMatches(in: chunkBytes, pattern: pattern, endIndex: searchEndIndex)
                totalMatches += matches.count
            }

            processedBytes += currentChunkSize
        }

        return totalMatches
    }

    private func findPatternMatches(in data: [UInt8], pattern: [UInt8?], endIndex: Int? = nil) -> [Range<Int>] {
        var matches: [Range<Int>] = []
        let patternLength = pattern.count
        let searchEndIndex = endIndex ?? data.count

        guard patternLength > 0, searchEndIndex >= patternLength else {
            return matches
        }

        let fixedByteIndices = pattern.indices.filter { pattern[$0] != nil }
        if fixedByteIndices.isEmpty {
            for index in 0 ... (searchEndIndex - patternLength) {
                matches.append(index ..< (index + patternLength))
            }
            return matches
        }

        let firstFixed = fixedByteIndices.first!
        let firstByteValue = pattern[firstFixed]!

        for index in 0 ... (searchEndIndex - patternLength) {
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
                matches.append(index ..< (index + patternLength))
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

            let byteRange = index ..< nextIndex
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

            let byteRange = index ..< nextIndex
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
            case let .hexStringLengthMismatch(description):
                return description
            case let .invalidHexString(description):
                return description
            case let .hexNotFound(description):
                return description
            case let .userCancelled(description):
                return description
            case let .invalidInput(description):
                return description
            case let .invalidFilePath(description):
                return description
            }
        }
    }
}
