import Foundation

struct HexPatchOperation: Identifiable {
    let id = UUID()
    let findHex: String
    let replaceHex: String
}

class HexPatch {
    private let bufferSize = 4 * 1024 * 1024
    private let maxMatchesPerChunk = 1000

    private func parseHexPattern(
        _ hex: String, isReplacement: Bool = false, originalPattern: [UInt8?]? = nil
    ) throws -> [UInt8?] {
        let cleanHex = hex.replacingOccurrences(of: " ", with: "").uppercased()

        guard !cleanHex.isEmpty else { throw HexPatchError.emptyHexStrings }
        guard cleanHex.count % 2 == 0 else {
            throw HexPatchError.invalidHexString(description: "Hex string must have even length")
        }

        var result: [UInt8?] = []
        var index = cleanHex.startIndex

        while index < cleanHex.endIndex {
            let nextIndex = cleanHex.index(index, offsetBy: 2)
            let byteString = String(cleanHex[index..<nextIndex])

            if byteString == "??" {
                if isReplacement {
                    guard let pattern = originalPattern,
                        result.count < pattern.count,
                        pattern[result.count] == nil
                    else {
                        throw HexPatchError.invalidHexString(
                            description: "Invalid wildcard usage in replace pattern")
                    }
                }
                result.append(nil)
            } else {
                guard let byte = UInt8(byteString, radix: 16) else {
                    throw HexPatchError.invalidHexString(
                        description: "Invalid hex byte: \(byteString)")
                }
                result.append(byte)
            }

            index = nextIndex
        }

        return result
    }

    private func searchChunk(url: URL, offset: UInt64, length: UInt64, pattern: [UInt8?]) throws
        -> [UInt64]
    {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        try handle.seek(toOffset: offset)
        guard let data = try handle.read(upToCount: Int(length)) else { return [] }

        if !pattern.contains(where: { $0 == nil }) {
            let patternBytes = pattern.compactMap { $0 }
            return try searchExactPattern(in: data, pattern: patternBytes, offset: offset)
        }

        var matches = ContiguousArray<UInt64>()
        let patternLength = pattern.count

        guard let firstAnchorIndex = pattern.firstIndex(where: { $0 != nil }),
            let firstAnchorByte = pattern[firstAnchorIndex]
        else {
            return []
        }

        return data.withUnsafeBytes { buffer -> [UInt64] in
            let ptr = buffer.baseAddress!.assumingMemoryBound(to: UInt8.self)
            var index = 0

            while index <= data.count - patternLength {
                if matches.count >= maxMatchesPerChunk { break }

                if ptr[index + firstAnchorIndex] != firstAnchorByte {
                    index += 1
                    continue
                }

                var isMatch = true
                for j in 0..<patternLength {
                    if let expectedByte = pattern[j] {
                        if ptr[index + j] != expectedByte {
                            isMatch = false
                            break
                        }
                    }
                }

                if isMatch {
                    matches.append(offset + UInt64(index))
                    index += patternLength
                } else {
                    index += 1
                }
            }

            return Array(matches)
        }
    }

    private func searchExactPattern(in data: Data, pattern: [UInt8], offset: UInt64) throws
        -> [UInt64]
    {
        var matches = ContiguousArray<UInt64>()
        let patternLength = pattern.count

        if patternLength <= 4 {
            return try simpleSkipSearch(in: data, pattern: pattern, offset: offset)
        }

        var skipTable = [UInt8: Int](minimumCapacity: 256)
        for i in 0..<256 {
            skipTable[UInt8(i)] = patternLength
        }
        for i in 0..<patternLength - 1 {
            skipTable[pattern[i]] = patternLength - 1 - i
        }

        return data.withUnsafeBytes { buffer -> [UInt64] in
            let ptr = buffer.baseAddress!.assumingMemoryBound(to: UInt8.self)
            let length = buffer.count
            var index = patternLength - 1

            while index < length {
                if matches.count >= maxMatchesPerChunk { break }

                let currentByte = ptr[index]
                if currentByte == pattern[patternLength - 1] {
                    if memcmp(ptr + index - (patternLength - 1), pattern, patternLength) == 0 {
                        matches.append(offset + UInt64(index - (patternLength - 1)))
                        index += 1
                        continue
                    }
                }

                index += skipTable[currentByte]!
            }

            return Array(matches)
        }
    }

    private func simpleSkipSearch(in data: Data, pattern: [UInt8], offset: UInt64) throws
        -> [UInt64]
    {
        var matches = ContiguousArray<UInt64>()
        let patternLength = pattern.count
        let lastByte = pattern[patternLength - 1]

        return data.withUnsafeBytes { buffer -> [UInt64] in
            let ptr = buffer.baseAddress!.assumingMemoryBound(to: UInt8.self)
            let length = buffer.count
            var index = patternLength - 1

            while index < length {
                if matches.count >= maxMatchesPerChunk { break }

                if ptr[index] == lastByte {
                    if memcmp(ptr + index - (patternLength - 1), pattern, patternLength) == 0 {
                        matches.append(offset + UInt64(index - (patternLength - 1)))
                    }
                }

                index += patternLength
            }

            return Array(matches)
        }
    }

    private func quickSearchWithWildcards(in data: Data, pattern: [UInt8?], offset: UInt64)
        -> [UInt64]
    {
        var matches = ContiguousArray<UInt64>()
        let patternLength = pattern.count

        var shift = [UInt8: Int](minimumCapacity: 256)
        for i in 0..<256 {
            shift[UInt8(i)] = patternLength + 1
        }

        for i in 0..<patternLength {
            if let byte = pattern[i] {
                shift[byte] = patternLength - i
            }
        }

        return data.withUnsafeBytes { buffer -> [UInt64] in
            let ptr = buffer.baseAddress!.assumingMemoryBound(to: UInt8.self)
            let length = buffer.count
            var index = 0

            while index <= length - patternLength {
                if matches.count >= maxMatchesPerChunk { break }

                var isMatch = true
                for j in 0..<patternLength {
                    if let expectedByte = pattern[j], ptr[index + j] != expectedByte {
                        isMatch = false
                        break
                    }
                }

                if isMatch {
                    matches.append(offset + UInt64(index))
                }

                let shiftIndex = index + patternLength
                if shiftIndex < length {
                    index += shift[ptr[shiftIndex]] ?? patternLength + 1
                } else {
                    break
                }
            }

            return Array(matches)
        }
    }

    private func bitParallelWildcardSearch(in data: Data, pattern: [UInt8?], offset: UInt64)
        -> [UInt64]
    {
        guard pattern.count <= 64 else { return [] }

        var matches = ContiguousArray<UInt64>()
        let patternLength = pattern.count

        var byteMatch = [UInt64](repeating: 0, count: 256)
        var wildcardMask: UInt64 = 0

        for (i, byte) in pattern.enumerated() {
            if let b = byte {
                byteMatch[Int(b)] |= (1 << i)
            } else {
                wildcardMask |= (1 << i)
            }
        }

        let matchMask = (1 << patternLength) - 1

        return data.withUnsafeBytes { buffer -> [UInt64] in
            let ptr = buffer.baseAddress!.assumingMemoryBound(to: UInt8.self)
            var state: UInt64 = 0

            for i in 0..<buffer.count {
                if matches.count >= maxMatchesPerChunk { break }

                state = ((state << 1) | 1) & (byteMatch[Int(ptr[i])] | wildcardMask)

                if (Int(state) & matchMask) == matchMask {
                    matches.append(offset + UInt64(i - patternLength + 1))
                }
            }

            return Array(matches)
        }
    }

    private func findMatches(in url: URL, pattern: [UInt8?]) throws -> [UInt64] {
        return try autoreleasepool {
            let fileSize =
                try FileManager.default.attributesOfItem(atPath: url.path)[.size] as! UInt64
            let chunkSize = UInt64(bufferSize)
            let chunks = Int((fileSize + chunkSize - 1) / chunkSize)

            let queue = DispatchQueue(label: "team.ediso.amimod.matches", attributes: .concurrent)
            let group = DispatchGroup()

            let processorCount = ProcessInfo.processInfo.activeProcessorCount
            let chunkQueue = OperationQueue()
            chunkQueue.maxConcurrentOperationCount = processorCount

            var matches = ContiguousArray<UInt64>()
            let matchLock = NSLock()

            for chunk in 0..<chunks {
                group.enter()
                queue.async {
                    autoreleasepool {
                        let offset = UInt64(chunk) * chunkSize
                        if let chunkMatches = try? self.searchChunk(
                            url: url,
                            offset: offset,
                            length: min(chunkSize, fileSize - offset),
                            pattern: pattern
                        ) {
                            matchLock.lock()
                            matches.append(contentsOf: chunkMatches)
                            matchLock.unlock()
                        }
                        group.leave()
                    }
                }
            }

            group.wait()
            return Array(matches)
        }
    }

    private func applyPatches(to filePath: String, matches: [UInt64], replacement: [UInt8?]) throws
    {
        let fileHandle = try FileHandle(forUpdating: URL(fileURLWithPath: filePath))
        defer { try? fileHandle.close() }

        for offset in matches.reversed() {
            try fileHandle.seek(toOffset: offset)
            var bytesToWrite = [UInt8]()

            for (index, repByte) in replacement.enumerated() {
                if let byte = repByte {
                    bytesToWrite.append(byte)
                } else {
                    try fileHandle.seek(toOffset: offset + UInt64(index))
                    guard let originalByte = try fileHandle.read(upToCount: 1)?.first else {
                        throw HexPatchError.invalidInput(
                            description: "Failed to read original byte")
                    }
                    bytesToWrite.append(originalByte)
                }
            }

            try fileHandle.seek(toOffset: offset)
            try fileHandle.write(contentsOf: bytesToWrite)
        }

        try fileHandle.synchronize()
    }

    func findAndReplaceHexStrings(in filePath: String, patches: [HexPatchOperation]) throws {
        for patch in patches {
            let pattern = try parseHexPattern(patch.findHex)
            let replacement = try parseHexPattern(
                patch.replaceHex, isReplacement: true, originalPattern: pattern)

            let matches = try findMatches(in: URL(fileURLWithPath: filePath), pattern: pattern)

            if matches.isEmpty {
                throw HexPatchError.hexNotFound(description: "Pattern not found: \(patch.findHex)")
            }

            try applyPatches(to: filePath, matches: matches, replacement: replacement)
        }
    }

    func countTotalMatches(in filePath: String, patches: [HexPatchOperation]) throws -> Int {
        var totalMatches = 0
        let maxMatchesPerPatch = 50000

        for patch in patches {
            let pattern = try parseHexPattern(patch.findHex)
            let replacement = try parseHexPattern(
                patch.replaceHex, isReplacement: true, originalPattern: pattern)

            guard pattern.count == replacement.count else {
                throw HexPatchError.hexStringLengthMismatch(
                    description: "Find and replace hex strings must have the same amount of bytes.")
            }

            let matches = try findMatches(in: URL(fileURLWithPath: filePath), pattern: pattern)

            if matches.count > maxMatchesPerPatch {
                throw HexPatchError.invalidInput(
                    description:
                        "Too many matches found (\(matches.count)). This could cause performance issues. Please refine your search pattern."
                )
            }

            totalMatches += matches.count
        }
        return totalMatches
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
