import Foundation
import simd

public struct HexPatchOperation: Identifiable {
    public let id = UUID()
    public let findHex: String
    public let replaceHex: String
}

public class HexPatch {
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

    private func optimizedBMH(in data: Data, pattern: [UInt8], offset: UInt64) -> [UInt64] {
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

        return data.withUnsafeBytes { buffer -> [UInt64] in
            let ptr = buffer.bindMemory(to: UInt8.self).baseAddress!
            var searchIndex = 0
            let searchBound = dataLength - patternLength

            let lastPatternByte = pattern[patternLength - 1]
            let secondLastPatternByte = patternLength > 1 ? pattern[patternLength - 2] : 0

            if patternLength >= 32 && dataLength >= 32 {
                let simdPattern32 = SIMD32<UInt8>(pattern[0..<min(32, patternLength)])

                while searchIndex <= searchBound {
                    let lastDataByte = ptr[searchIndex + patternLength - 1]

                    if lastDataByte == lastPatternByte
                        && (patternLength == 1
                            || ptr[searchIndex + patternLength - 2] == secondLastPatternByte)
                    {

                        var matched = true

                        if searchIndex + 32 <= dataLength {
                            let dataChunk32 = UnsafeRawPointer(ptr + searchIndex)
                                .assumingMemoryBound(to: SIMD32<UInt8>.self).pointee
                            if dataChunk32 != simdPattern32 {
                                matched = false
                            } else if patternLength > 32 {
                                let remainingPattern = Array(pattern.dropFirst(32))
                                matched =
                                    memcmp(
                                        remainingPattern, ptr + searchIndex + 32, patternLength - 32
                                    ) == 0
                            }
                        } else {
                            matched = memcmp(pattern, ptr + searchIndex, patternLength) == 0
                        }

                        if matched {
                            matches.append(offset + UInt64(searchIndex))
                            if matches.count >= maxMatchesPerChunk { break }
                            searchIndex += patternLength
                            continue
                        }
                    }

                    searchIndex += Int(badCharTable[Int(lastDataByte)])
                }
            } else if patternLength >= 16 && dataLength >= 16 {
                let simdPattern16 = SIMD16<UInt8>(pattern[0..<min(16, patternLength)])

                while searchIndex <= searchBound {
                    let lastDataByte = ptr[searchIndex + patternLength - 1]

                    if lastDataByte == lastPatternByte
                        && (patternLength == 1
                            || ptr[searchIndex + patternLength - 2] == secondLastPatternByte)
                    {

                        var matched = true

                        if searchIndex + 16 <= dataLength {
                            let dataChunk16 = UnsafeRawPointer(ptr + searchIndex)
                                .assumingMemoryBound(to: SIMD16<UInt8>.self).pointee
                            if dataChunk16 != simdPattern16 {
                                matched = false
                            } else if patternLength > 16 {
                                let remainingPattern = Array(pattern.dropFirst(16))
                                matched =
                                    memcmp(
                                        remainingPattern, ptr + searchIndex + 16, patternLength - 16
                                    ) == 0
                            }
                        } else {
                            matched = memcmp(pattern, ptr + searchIndex, patternLength) == 0
                        }

                        if matched {
                            matches.append(offset + UInt64(searchIndex))
                            if matches.count >= maxMatchesPerChunk { break }
                            searchIndex += patternLength
                            continue
                        }
                    }

                    searchIndex += Int(badCharTable[Int(lastDataByte)])
                }
            } else if patternLength >= 8 {
                while searchIndex <= searchBound {
                    let lastDataByte = ptr[searchIndex + patternLength - 1]

                    if lastDataByte == lastPatternByte
                        && (patternLength == 1
                            || ptr[searchIndex + patternLength - 2] == secondLastPatternByte)
                    {

                        let matched = memcmp(pattern, ptr + searchIndex, patternLength) == 0

                        if matched {
                            matches.append(offset + UInt64(searchIndex))
                            if matches.count >= maxMatchesPerChunk { break }
                            searchIndex += patternLength
                            continue
                        }
                    }

                    searchIndex += Int(badCharTable[Int(lastDataByte)])
                }
            } else {
                while searchIndex <= searchBound {
                    let lastDataByte = ptr[searchIndex + patternLength - 1]

                    if lastDataByte == lastPatternByte {
                        var matched = true
                        for i in 0..<(patternLength - 1) {
                            if pattern[i] != ptr[searchIndex + i] {
                                matched = false
                                break
                            }
                        }

                        if matched {
                            matches.append(offset + UInt64(searchIndex))
                            if matches.count >= maxMatchesPerChunk { break }
                            searchIndex += patternLength
                            continue
                        }
                    }

                    searchIndex += Int(badCharTable[Int(lastDataByte)])
                }
            }

            return Array(matches)
        }
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

    private func optimizedWildcardSearch(in data: Data, pattern: [UInt8?], offset: UInt64)
        -> [UInt64]
    {
        let m = pattern.count
        let n = data.count

        guard m > 0, n >= m else { return [] }

        if m <= 32 {
            return simpleWildcardSearch(in: data, pattern: pattern, offset: offset)
        } else if m <= 128 {
            return mediumWildcardSearch(in: data, pattern: pattern, offset: offset)
        } else {
            return advancedWildcardSearch(in: data, pattern: pattern, offset: offset)
        }
    }

    private func simpleWildcardSearch(in data: Data, pattern: [UInt8?], offset: UInt64) -> [UInt64]
    {
        var matches = ContiguousArray<UInt64>()
        let m = pattern.count
        let n = data.count

        var firstAnchor: (index: Int, byte: UInt8)?
        var lastAnchor: (index: Int, byte: UInt8)?

        for (index, byte) in pattern.enumerated() {
            if let nonWildcard = byte {
                if firstAnchor == nil {
                    firstAnchor = (index, nonWildcard)
                }
                lastAnchor = (index, nonWildcard)
            }
        }

        guard let first = firstAnchor, let last = lastAnchor else { return [] }

        return data.withUnsafeBytes { buffer -> [UInt64] in
            let ptr = buffer.baseAddress!.assumingMemoryBound(to: UInt8.self)
            var shift = 0
            let searchBound = n - m
            let firstByte = first.byte
            let lastByte = last.byte
            let firstIndex = first.index
            let lastIndex = last.index

            while shift <= searchBound {
                if matches.count >= maxMatchesPerChunk { break }

                if ptr[shift + firstIndex] == firstByte && ptr[shift + lastIndex] == lastByte {
                    var matched = true
                    var i = 0
                    
                    while i + 4 <= m {
                        if let p0 = pattern[i], p0 != ptr[shift + i] { matched = false; break }
                        if let p1 = pattern[i + 1], p1 != ptr[shift + i + 1] { matched = false; break }
                        if let p2 = pattern[i + 2], p2 != ptr[shift + i + 2] { matched = false; break }
                        if let p3 = pattern[i + 3], p3 != ptr[shift + i + 3] { matched = false; break }
                        i += 4
                    }
                    
                    while i < m && matched {
                        if let patternByte = pattern[i], patternByte != ptr[shift + i] {
                            matched = false
                            break
                        }
                        i += 1
                    }

                    if matched {
                        matches.append(offset + UInt64(shift))
                        shift += max(1, m / 2)
                    } else {
                        shift += 1
                    }
                } else {
                    shift += 1
                }
            }

            return Array(matches)
        }
    }

    private func mediumWildcardSearch(in data: Data, pattern: [UInt8?], offset: UInt64) -> [UInt64]
    {
        var matches = ContiguousArray<UInt64>()
        let m = pattern.count
        let n = data.count

        var anchorPoints = [(index: Int, byte: UInt8)]()
        let step = max(1, m / 4)

        for i in stride(from: 0, to: m, by: step) {
            if let byte = pattern[i] {
                anchorPoints.append((i, byte))
                if anchorPoints.count >= 4 { break }
            }
        }

        if anchorPoints.count < 3 {
            for i in stride(from: m - 1, through: 0, by: -1) {
                if let byte = pattern[i] {
                    let alreadyExists = anchorPoints.contains { $0.index == i }
                    if !alreadyExists {
                        anchorPoints.append((i, byte))
                        break
                    }
                }
            }
        }

        guard !anchorPoints.isEmpty else { return [] }

        return data.withUnsafeBytes { buffer -> [UInt64] in
            let ptr = buffer.baseAddress!.assumingMemoryBound(to: UInt8.self)
            var shift = 0
            let searchBound = n - m

            while shift <= searchBound {
                if matches.count >= maxMatchesPerChunk { break }

                var allAnchorsMatch = true
                for anchor in anchorPoints {
                    if ptr[shift + anchor.index] != anchor.byte {
                        allAnchorsMatch = false
                        break
                    }
                }

                if allAnchorsMatch {
                    var matched = true
                    var i = 0
                    
                    while i + 4 <= m && matched {
                        if let p0 = pattern[i], p0 != ptr[shift + i] { matched = false; break }
                        if let p1 = pattern[i + 1], p1 != ptr[shift + i + 1] { matched = false; break }
                        if let p2 = pattern[i + 2], p2 != ptr[shift + i + 2] { matched = false; break }
                        if let p3 = pattern[i + 3], p3 != ptr[shift + i + 3] { matched = false; break }
                        i += 4
                    }
                    
                    while i < m && matched {
                        if let patternByte = pattern[i], patternByte != ptr[shift + i] {
                            matched = false
                            break
                        }
                        i += 1
                    }

                    if matched {
                        matches.append(offset + UInt64(shift))
                        shift += max(1, m / 3)
                    } else {
                        shift += 1
                    }
                } else {
                    shift += 1
                }
            }

            return Array(matches)
        }
    }

    private func advancedWildcardSearch(in data: Data, pattern: [UInt8?], offset: UInt64)
        -> [UInt64]
    {
        var matches = ContiguousArray<UInt64>()
        let m = pattern.count
        let n = data.count

        var anchorPoints = [(index: Int, byte: UInt8)]()
        var byteFrequency = [UInt8: Int]()

        for byte in pattern.compactMap({ $0 }) {
            byteFrequency[byte, default: 0] += 1
        }

        var candidateAnchors = [(index: Int, byte: UInt8, frequency: Int)]()
        for (index, byte) in pattern.enumerated() {
            if let nonWildcard = byte {
                candidateAnchors.append((index, nonWildcard, byteFrequency[nonWildcard] ?? 1))
            }
        }

        candidateAnchors.sort { $0.frequency < $1.frequency }

        var selectedIndices = Set<Int>()
        for candidate in candidateAnchors {
            if anchorPoints.count >= 8 { break }

            let tooClose = selectedIndices.contains { abs($0 - candidate.index) < max(1, m / 10) }
            if !tooClose {
                anchorPoints.append((candidate.index, candidate.byte))
                selectedIndices.insert(candidate.index)
            }
        }

        guard !anchorPoints.isEmpty else { return [] }

        let badChar = createBadCharTable(pattern: pattern)

        return data.withUnsafeBytes { buffer -> [UInt64] in
            let ptr = buffer.baseAddress!.assumingMemoryBound(to: UInt8.self)
            var shift = 0
            let searchBound = n - m

            while shift <= searchBound {
                if matches.count >= maxMatchesPerChunk { break }

                var anchorsMatched = 0
                let maxAnchorsToCheck = min(4, anchorPoints.count)
                for i in 0..<maxAnchorsToCheck {
                    let anchor = anchorPoints[i]
                    if ptr[shift + anchor.index] == anchor.byte {
                        anchorsMatched += 1
                    } else {
                        break
                    }
                }

                if anchorsMatched < maxAnchorsToCheck {
                    shift += 1
                    continue
                }

                var allAnchorsMatch = true
                for i in anchorsMatched..<anchorPoints.count {
                    let anchor = anchorPoints[i]
                    if ptr[shift + anchor.index] != anchor.byte {
                        allAnchorsMatch = false
                        break
                    }
                }

                if !allAnchorsMatch {
                    shift += 1
                    continue
                }

                var matched = true
                var i = 0

                while i + 16 <= m && matched {
                    for j in 0..<16 {
                        if let patternByte = pattern[i + j], patternByte != ptr[shift + i + j] {
                            matched = false
                            break
                        }
                    }
                    if matched { i += 16 }
                }

                while i + 8 <= m && matched {
                    for j in 0..<8 {
                        if let patternByte = pattern[i + j], patternByte != ptr[shift + i + j] {
                            matched = false
                            break
                        }
                    }
                    if matched { i += 8 }
                }

                while i < m && matched {
                    if let patternByte = pattern[i], patternByte != ptr[shift + i] {
                        matched = false
                        break
                    }
                    i += 1
                }

                if matched {
                    matches.append(offset + UInt64(shift))
                    shift += max(1, m / 4)
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

        let minChunkSize: UInt64 = 2 * 1024 * 1024
        let maxChunkSize: UInt64 = 16 * 1024 * 1024
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
            return optimizedBMH(in: data, pattern: patternBytes, offset: offset)
        } else {
            return optimizedWildcardSearch(in: data, pattern: pattern, offset: offset)
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

    public enum HexPatchError: Error {
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
