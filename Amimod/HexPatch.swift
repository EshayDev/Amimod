import Foundation

struct HexPatchOperation: Identifiable {
    let id = UUID()
    let findHex: String
    let replaceHex: String
}

class HexPatch {
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

    private func wideWindowBMH(in data: Data, pattern: [UInt8], offset: UInt64) -> [UInt64] {
        var matches = ContiguousArray<UInt64>()
        let patternLength = pattern.count
        let dataLength = data.count

        guard patternLength > 0, dataLength >= patternLength else {
            return []
        }

        let badCharTable: [UInt16] = {
            var table = [UInt16](repeating: UInt16(patternLength), count: 256)
            for i in 0..<(patternLength - 1) {
                table[Int(pattern[i])] = UInt16(patternLength - 1 - i)
            }
            return table
        }()

        data.withUnsafeBytes { buffer in
            let ptr = buffer.bindMemory(to: UInt8.self).baseAddress!
            var searchIndex = 0
            let searchBound = dataLength - patternLength

            let lastPatternByte = pattern[patternLength - 1]
            let secondLastPatternByte = patternLength > 1 ? pattern[patternLength - 2] : 0

            let simdPattern =
                patternLength >= 16 ? SIMD16<UInt8>(pattern[0..<min(16, patternLength)]) : nil

            while searchIndex <= searchBound {
                let lastDataByte = ptr[searchIndex + patternLength - 1]

                if lastDataByte == lastPatternByte
                    && (patternLength == 1
                        || ptr[searchIndex + patternLength - 2] == secondLastPatternByte)
                {

                    var matched = true
                    if patternLength >= 16 {
                        let dataChunk = UnsafeRawPointer(ptr + searchIndex).assumingMemoryBound(
                            to: SIMD16<UInt8>.self
                        ).pointee
                        if dataChunk != simdPattern! {
                            matched = false
                        } else {
                            let remainingStart = 16
                            if remainingStart < patternLength {
                                for i in stride(from: remainingStart, to: patternLength - 2, by: 8)
                                {
                                    let end = min(i + 8, patternLength - 2)
                                    for j in i..<end {
                                        if pattern[j] != ptr[searchIndex + j] {
                                            matched = false
                                            break
                                        }
                                    }
                                    if !matched { break }
                                }
                            }
                        }
                    } else {
                        var i = 0
                        while i < patternLength - 2 {
                            if i + 4 <= patternLength - 2 {
                                if pattern[i] != ptr[searchIndex + i]
                                    || pattern[i + 1] != ptr[searchIndex + i + 1]
                                    || pattern[i + 2] != ptr[searchIndex + i + 2]
                                    || pattern[i + 3] != ptr[searchIndex + i + 3]
                                {
                                    matched = false
                                    break
                                }
                                i += 4
                            } else {
                                if pattern[i] != ptr[searchIndex + i] {
                                    matched = false
                                    break
                                }
                                i += 1
                            }
                        }
                    }

                    if matched {
                        matches.append(offset + UInt64(searchIndex))
                        if matches.count >= maxMatchesPerChunk {
                            break
                        }
                        searchIndex += patternLength
                        continue
                    }
                }

                searchIndex += Int(badCharTable[Int(lastDataByte)])
            }
        }

        return Array(matches)
    }

    private func createBadCharTable(pattern: [UInt8?]) -> [Int] {
        var badChar = [Int](repeating: pattern.count, count: 256)

        for i in 0..<pattern.count {
            if let byte = pattern[i] {
                badChar[Int(byte)] = pattern.count - 1 - i
            }
        }

        return badChar
    }

    private func wildcardBoyerMoore(in data: Data, pattern: [UInt8?], offset: UInt64) -> [UInt64] {
        var matches = ContiguousArray<UInt64>()
        let m = pattern.count
        let n = data.count

        guard m > 0, n >= m else { return [] }

        var anchorPoints = [(index: Int, byte: UInt8)]()
        for (index, byte) in pattern.enumerated() {
            if let nonWildcard = byte {
                anchorPoints.append((index, nonWildcard))
                if anchorPoints.count >= 10 { break }
            }
        }

        guard !anchorPoints.isEmpty else { return [] }

        let primaryAnchor = anchorPoints[0]
        let badChar = createBadCharTable(pattern: pattern)

        return data.withUnsafeBytes { buffer -> [UInt64] in
            let ptr = buffer.baseAddress!.assumingMemoryBound(to: UInt8.self)
            var shift = 0

            while shift <= (n - m) {
                if matches.count >= maxMatchesPerChunk { break }

                if ptr[shift + primaryAnchor.index] != primaryAnchor.byte {
                    shift += 1
                    continue
                }

                var shouldContinue = false
                for anchor in anchorPoints.dropFirst() {
                    if ptr[shift + anchor.index] != anchor.byte {
                        shouldContinue = true
                        break
                    }
                }
                if shouldContinue {
                    shift += 1
                    continue
                }

                var matched = true
                var i = 0
                while i < m {
                    if let patternByte = pattern[i] {
                        if patternByte != ptr[shift + i] {
                            matched = false
                            break
                        }
                    }
                    i += 1
                }

                if matched {
                    matches.append(offset + UInt64(shift))
                    shift += m / 4
                } else {
                    shift += max(1, min(badChar[Int(ptr[shift + m - 1])], m / 8))
                }
            }

            return Array(matches)
        }
    }

    private func findMatches(in url: URL, pattern: [UInt8?]) throws -> [UInt64] {
        let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as! UInt64
        let processorCount = ProcessInfo.processInfo.activeProcessorCount

        let patternLength = UInt64(pattern.count)
        let minChunkSize: UInt64 = 4 * 1024 * 1024
        let maxChunkSize: UInt64 = 32 * 1024 * 1024
        let idealChunkSize = max(min(fileSize / UInt64(processorCount), maxChunkSize), minChunkSize)

        let overlap = patternLength - 1
        let totalChunks = Int((fileSize + idealChunkSize - 1) / idealChunkSize)

        let chunkQueue = OperationQueue()
        chunkQueue.maxConcurrentOperationCount = processorCount

        var matches = [UInt64]()
        var results = Array(repeating: [UInt64](), count: totalChunks)
        let resultsLock = NSLock()

        for chunkIndex in 0..<totalChunks {
            chunkQueue.addOperation {
                autoreleasepool {
                    let chunkStart = UInt64(chunkIndex) * idealChunkSize
                    let isLastChunk = chunkIndex == totalChunks - 1

                    let baseLength = min(idealChunkSize, fileSize - chunkStart)
                    let overlapLength = isLastChunk ? 0 : overlap
                    let totalLength = min(baseLength + overlapLength, fileSize - chunkStart)

                    do {
                        let chunkMatches = try self.searchChunk(
                            url: url,
                            offset: chunkStart,
                            length: totalLength,
                            pattern: pattern
                        )

                        let validMatches = chunkMatches.filter { matchOffset in
                            if isLastChunk {
                                return true
                            }
                            return matchOffset < chunkStart + idealChunkSize
                        }

                        resultsLock.lock()
                        results[chunkIndex] = validMatches
                        resultsLock.unlock()
                    } catch {
                        print("Error processing chunk \(chunkIndex): \(error)")
                    }
                }
            }
        }

        chunkQueue.waitUntilAllOperationsAreFinished()

        for chunkMatches in results {
            matches.append(contentsOf: chunkMatches)
        }

        return matches.sorted()
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
            return wideWindowBMH(in: data, pattern: patternBytes, offset: offset)
        } else {
            return wildcardBoyerMoore(in: data, pattern: pattern, offset: offset)
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
        let dynamicHexPatch = HexPatch()

        for patch in patches {
            let pattern = try dynamicHexPatch.parseHexPattern(patch.findHex)
            let replacement = try dynamicHexPatch.parseHexPattern(
                patch.replaceHex, isReplacement: true, originalPattern: pattern)

            let matches = try dynamicHexPatch.findMatches(
                in: URL(fileURLWithPath: filePath), pattern: pattern)

            if matches.isEmpty {
                throw HexPatchError.hexNotFound(description: "Pattern not found: \(patch.findHex)")
            }

            try dynamicHexPatch.applyPatches(
                to: filePath, matches: matches, replacement: replacement)
        }
    }

    func countTotalMatches(in filePath: String, patches: [HexPatchOperation]) throws -> Int {
        var totalMatches = 0
        let maxMatchesPerPatch = 50000
        let dynamicHexPatch = HexPatch()

        for patch in patches {
            let pattern = try dynamicHexPatch.parseHexPattern(patch.findHex)
            let replacement = try dynamicHexPatch.parseHexPattern(
                patch.replaceHex, isReplacement: true, originalPattern: pattern)

            guard pattern.count == replacement.count else {
                throw HexPatchError.hexStringLengthMismatch(
                    description: "Find and replace hex strings must have the same amount of bytes.")
            }

            let matches = try dynamicHexPatch.findMatches(
                in: URL(fileURLWithPath: filePath), pattern: pattern)

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
