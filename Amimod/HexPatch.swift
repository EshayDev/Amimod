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

        var matches = ContiguousArray<UInt64>()
        let patternLength = pattern.count

        if !pattern.contains(where: { $0 == nil }) {
            let patternBytes = pattern.compactMap { $0 }
            return try searchExactPattern(in: data, pattern: patternBytes, offset: offset)
        }

        return data.withUnsafeBytes { buffer -> [UInt64] in
            let ptr = buffer.baseAddress!.assumingMemoryBound(to: UInt8.self)
            var index = 0

            while index <= data.count - patternLength {
                if matches.count >= maxMatchesPerChunk { break }

                var isMatch = true
                for patternIndex in 0..<patternLength {
                    if let expectedByte = pattern[patternIndex],
                        ptr[index + patternIndex] != expectedByte
                    {
                        isMatch = false
                        break
                    }
                }

                if isMatch {
                    matches.append(offset + UInt64(index))
                }
                index += 1
            }

            return Array(matches)
        }
    }

    private func searchExactPattern(in data: Data, pattern: [UInt8], offset: UInt64) throws
        -> [UInt64]
    {
        var matches = ContiguousArray<UInt64>()
        let patternLength = pattern.count

        data.withUnsafeBytes { buffer in
            let ptr = buffer.baseAddress!.assumingMemoryBound(to: UInt8.self)
            let length = buffer.count
            var index = 0

            if patternLength <= 16 {
                while index <= length - patternLength {
                    if matches.count >= maxMatchesPerChunk { break }
                    if memcmp(ptr + index, pattern, patternLength) == 0 {
                        matches.append(offset + UInt64(index))
                    }
                    index += 1
                }
            } else {
                while index <= length - patternLength {
                    if matches.count >= maxMatchesPerChunk { break }
                    if ptr[index] == pattern[0] {
                        var fullMatch = true
                        for j in 1..<patternLength {
                            if ptr[index + j] != pattern[j] {
                                fullMatch = false
                                break
                            }
                        }
                        if fullMatch {
                            matches.append(offset + UInt64(index))
                        }
                    }
                    index += 1
                }
            }
        }

        return Array(matches)
    }

    private func findMatches(in url: URL, pattern: [UInt8?]) throws -> [UInt64] {
        let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as! UInt64
        let chunkSize = UInt64(bufferSize)
        let chunks = Int((fileSize + chunkSize - 1) / chunkSize)

        let group = DispatchGroup()
        let queue = DispatchQueue(label: "team.ediso.amimod.matches", attributes: .concurrent)
        let processorCount = ProcessInfo.processInfo.activeProcessorCount
        let semaphore = DispatchSemaphore(value: processorCount)

        var matches = ContiguousArray<UInt64>()
        let matchLock = NSLock()

        for chunk in 0..<chunks {
            semaphore.wait()
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
                    semaphore.signal()
                    group.leave()
                }
            }
        }

        group.wait()
        return Array(matches)
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
