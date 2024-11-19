import Foundation

struct HexPatchOperation: Identifiable {
    let id = UUID()
    let findHex: String
    let replaceHex: String
}

class HexPatch {
    private let BUFFER_SIZE = 64 * 1024
    private let ASIZE = 256

    private class Node {
        var value: Int
        var next: Int

        init(value: Int, next: Int) {
            self.value = value
            self.next = next
        }
    }

    private func skipSearch(fileHandle: FileHandle, pattern: [UInt8?], startOffset: UInt64 = 0) throws -> [UInt64] {
        var matches: [UInt64] = []
        let byteLen = pattern.count

        var bucket = Array(repeating: 0, count: ASIZE)
        var skipBuf: [Node] = []
        skipBuf.append(Node(value: 0, next: 0))

        var bufIdx = 1
        for (i, byte) in pattern.enumerated() {
            if let byte = byte {
                skipBuf.append(Node(value: i, next: bucket[Int(byte)]))
                bucket[Int(byte)] = bufIdx
                bufIdx += 1
            }
        }

        let fixedByteIndices = pattern.enumerated().filter { $0.element != nil }
        guard let firstFixed = fixedByteIndices.first else {
            return matches
        }
        let firstFixedIndex = firstFixed.offset
        let firstFixedByte = pattern[firstFixedIndex]!

        try fileHandle.seek(toOffset: startOffset)
        let fileSize = try fileHandle.seekToEnd()
        try fileHandle.seek(toOffset: startOffset)

        var processedBytes: UInt64 = startOffset
        let overlap = byteLen - 1
        var previousBuffer: [UInt8] = []
        var bufferBaseOffset: UInt64 = startOffset

        while processedBytes < fileSize {
            let remainingBytes = fileSize - processedBytes
            let readSize = min(UInt64(BUFFER_SIZE), remainingBytes + UInt64(overlap))

            guard let data = try fileHandle.read(upToCount: Int(readSize)) else { break }
            var buffer = [UInt8](data)

            if !previousBuffer.isEmpty {
                buffer = previousBuffer + buffer
            }

            previousBuffer = Array(buffer.suffix(min(overlap, buffer.count)))

            var i = 0
            let searchEnd = buffer.count - byteLen + 1

            while i < searchEnd {
                let currentPosition = i + firstFixedIndex
                if currentPosition < buffer.count, buffer[currentPosition] == firstFixedByte {
                    for j in bucket[Int(firstFixedByte)] ..< skipBuf.count {
                        let skipNode = skipBuf[j]
                        let potentialMatchStart = i + firstFixedIndex - skipNode.value

                        if potentialMatchStart >= 0, potentialMatchStart <= buffer.count - byteLen {
                            var isMatch = true
                            for (patternIndex, patternByte) in pattern.enumerated() {
                                if let expectedByte = patternByte {
                                    if potentialMatchStart + patternIndex >= buffer.count || buffer[potentialMatchStart + patternIndex] != expectedByte {
                                        isMatch = false
                                        break
                                    }
                                }
                            }

                            if isMatch {
                                let matchOffset = bufferBaseOffset + UInt64(potentialMatchStart)
                                if !matches.contains(matchOffset) {
                                    matches.append(matchOffset)
                                }
                            }
                        }
                    }
                }
                i += 1
            }

            let advance = buffer.count - previousBuffer.count
            bufferBaseOffset += UInt64(advance)
            processedBytes += UInt64(data.count)
            try fileHandle.seek(toOffset: processedBytes)
        }

        return matches.sorted()
    }

    private func validateHexPatterns(_ patches: [HexPatchOperation]) throws -> [(pattern: [UInt8?], replacement: [UInt8?])] {
        var validatedPatterns: [(pattern: [UInt8?], replacement: [UInt8?])] = []

        for patch in patches {
            let pattern = try parseHexPattern(patch.findHex)
            let replacement = try parseReplacementHex(patch.replaceHex, pattern: pattern)

            validatedPatterns.append((pattern: pattern, replacement: replacement))
        }

        return validatedPatterns
    }

    func findAndReplaceHexStrings(in filePath: String, patches: [HexPatchOperation]) throws {
        let validatedPatterns = try validateHexPatterns(patches)

        let fileURL = URL(fileURLWithPath: filePath)
        let fileHandle = try FileHandle(forUpdating: fileURL)
        defer { try? fileHandle.close() }

        for (index, validated) in validatedPatterns.enumerated() {
            let matches = try skipSearch(fileHandle: fileHandle, pattern: validated.pattern)

            if matches.isEmpty {
                throw HexPatchError.hexNotFound(description: "Pattern not found: \(patches[index].findHex)")
            }

            for offset in matches.reversed() {
                try fileHandle.seek(toOffset: offset)

                var bytesToWrite: [UInt8] = []
                for (index, repByte) in validated.replacement.enumerated() {
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
        }

        try fileHandle.synchronize()
    }

    func countTotalMatches(in filePath: String, patches: [HexPatchOperation]) throws -> Int {
        let validatedPatterns = try validateHexPatterns(patches)

        let fileURL = URL(fileURLWithPath: filePath)
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? fileHandle.close() }

        var totalMatches = 0

        for validated in validatedPatterns {
            let matches = try skipSearch(fileHandle: fileHandle, pattern: validated.pattern)
            totalMatches += matches.count
        }

        return totalMatches
    }

    private func parseHexPattern(_ hex: String) throws -> [UInt8?] {
        let cleanHex = preprocessHexString(hex)

        if cleanHex.isEmpty {
            throw HexPatchError.emptyHexStrings
        }

        if cleanHex.count % 2 != 0 {
            throw HexPatchError.invalidHexString(description: "Hex string must have an even number of characters")
        }

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

        return pattern
    }

    private func parseReplacementHex(_ hex: String, pattern: [UInt8?]) throws -> [UInt8?] {
        let cleanHex = preprocessHexString(hex)

        if cleanHex.isEmpty {
            throw HexPatchError.emptyHexStrings
        }

        if cleanHex.count % 2 != 0 {
            throw HexPatchError.invalidHexString(description: "Replace hex string must have an even number of characters")
        }

        if cleanHex.count > pattern.count * 2 {
            throw HexPatchError.hexStringLengthMismatch(description: "Replace hex cannot have more bytes than find hex")
        }

        var replacement: [UInt8?] = []

        var index = cleanHex.startIndex
        while index < cleanHex.endIndex {
            guard let nextIndex = cleanHex.index(index, offsetBy: 2, limitedBy: cleanHex.endIndex) else {
                break
            }

            let byteRange = index ..< nextIndex
            let byteString = String(cleanHex[byteRange])

            let patternIndex = replacement.count

            if byteString == "??" {
                if patternIndex < pattern.count, pattern[patternIndex] != nil {
                    throw HexPatchError.invalidHexString(description: "Replace hex contains wildcard '??' at position \(patternIndex + 1), but find hex does not")
                }
                replacement.append(nil)
            } else {
                guard let byte = UInt8(byteString, radix: 16) else {
                    throw HexPatchError.invalidHexString(description: "Invalid hex byte: \(byteString)")
                }
                replacement.append(byte)
            }

            index = nextIndex
        }

        if replacement.count != pattern.count {
            throw HexPatchError.hexStringLengthMismatch(description: "Replace hex must have the same number of bytes as find hex.")
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
