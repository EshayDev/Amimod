import Darwin
import Foundation

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

    private func standardSearch(in data: Data, pattern: [UInt8], offset: UInt64) -> [UInt64] {
        let patternLength = pattern.count
        let dataLength = data.count

        guard patternLength > 0, dataLength >= patternLength else {
            return []
        }

        let searchBound = dataLength - patternLength

        var out: [UInt64] = []
        data.withUnsafeBytes { (dataBuffer: UnsafeRawBufferPointer) in
            let basePtr = dataBuffer.bindMemory(to: UInt8.self).baseAddress!
            pattern.withUnsafeBufferPointer { (patBuffer: UnsafeBufferPointer<UInt8>) in
                let patPtr = patBuffer.baseAddress!
                let lastIndex = patternLength - 1
                let lastByte = patPtr[lastIndex]
                let secondLastByte: UInt8 = patternLength > 1 ? patPtr[lastIndex - 1] : 0

                var scanPtr = basePtr.advanced(by: lastIndex)
                let endPtr = basePtr.advanced(by: searchBound + lastIndex + 1)

                var collectedMatches = ContiguousArray<UInt64>()
                while scanPtr < endPtr {
                    if collectedMatches.count >= maxMatchesPerChunk { break }

                    let remainingCount: Int = scanPtr.distance(to: endPtr)
                    guard
                        let foundRaw = memchr(
                            UnsafeRawPointer(scanPtr), Int32(lastByte), remainingCount)
                    else {
                        break
                    }
                    let found = foundRaw.assumingMemoryBound(to: UInt8.self)

                    let candidateStart = found.advanced(by: -lastIndex)
                    let startIndex = basePtr.distance(to: UnsafePointer(candidateStart))

                    if patternLength == 1 {
                        collectedMatches.append(offset + UInt64(startIndex))
                    } else {
                        let secondLastAddr = candidateStart.advanced(by: patternLength - 2)
                        if secondLastAddr.pointee == secondLastByte {
                            if memcmp(patPtr, UnsafePointer(candidateStart), patternLength) == 0 {
                                collectedMatches.append(offset + UInt64(startIndex))
                            }
                        }
                    }

                    scanPtr = UnsafePointer(found).advanced(by: 1)
                }

                out = Array(collectedMatches)
            }
        }
        return out
    }

    private func wildcardSearch(in data: Data, pattern: [UInt8?], offset: UInt64) -> [UInt64] {
        let m = pattern.count
        let n = data.count
        guard m > 0, n >= m else { return [] }

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

        let fixedChecks: [(index: Int, byte: UInt8)] = pattern.enumerated().compactMap { (i, b) in
            guard let value = b else { return nil }
            return (i, value)
        }.filter { $0.index != first.index && $0.index != last.index }

        var matches = ContiguousArray<UInt64>()
        matches.reserveCapacity(64)
        let searchBound = n - m

        return data.withUnsafeBytes { buffer -> [UInt64] in
            let basePtr = buffer.bindMemory(to: UInt8.self).baseAddress!

            let firstByte = first.byte
            let lastByte = last.byte
            let firstIndex = first.index
            let lastIndex = last.index

            var scanPtr = basePtr + lastIndex
            let endPtr = basePtr + (searchBound + lastIndex + 1)

            while scanPtr < endPtr {
                if matches.count >= maxMatchesPerChunk { break }

                let remainingCount: Int = endPtr - scanPtr
                guard
                    let foundRaw = memchr(
                        UnsafeRawPointer(scanPtr), Int32(lastByte), remainingCount)
                else {
                    break
                }
                let foundMutable = foundRaw.assumingMemoryBound(to: UInt8.self)
                let foundConst = UnsafePointer<UInt8>(foundMutable)

                let candidateShift = (foundConst - basePtr) - lastIndex

                if basePtr[candidateShift + firstIndex] == firstByte {
                    var matched = true

                    for (i, b) in fixedChecks {
                        if basePtr[candidateShift + i] != b {
                            matched = false
                            break
                        }
                    }

                    if matched {
                        matches.append(offset + UInt64(candidateShift))
                    }
                }

                scanPtr = foundConst + 1
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
            return standardSearch(in: data, pattern: patternBytes, offset: offset)
        } else {
            return wildcardSearch(in: data, pattern: pattern, offset: offset)
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
