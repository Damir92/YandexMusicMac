import Foundation

/// A single timestamped line in synchronized karaoke lyrics.
public struct SyncedLyricLine: Identifiable, Sendable, Hashable {
    public let id: Int
    public let time: TimeInterval
    public let text: String

    public init(id: Int, time: TimeInterval, text: String) {
        self.id = id
        self.time = time
        self.text = text
    }

    public var formattedTimestamp: String {
        let total = Int(time)
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}

/// Structured synchronized LRC lyrics container with fast active-line lookup and parsing.
public struct YMSyncedLyrics: Sendable, Hashable {
    public let lines: [SyncedLyricLine]

    public init(lines: [SyncedLyricLine]) {
        self.lines = lines
    }

    public var isEmpty: Bool {
        lines.isEmpty
    }

    /// Finds the index of the active lyric line for the given playback time in seconds.
    public func activeLineIndex(for currentTime: TimeInterval) -> Int? {
        guard !lines.isEmpty, currentTime.isFinite else { return nil }

        // Before first line
        if currentTime < lines[0].time {
            return nil
        }

        // Binary search for highest index where line.time <= currentTime
        var low = 0
        var high = lines.count - 1
        var result = 0

        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= currentTime {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        return result
    }

    private static let leadingTagRegex = try? NSRegularExpression(pattern: "^\\s*\\[(\\d{1,3}):(\\d{2})(?:[.:](\\d{1,3}))?\\]")
    private static let inlineTagRegex = try? NSRegularExpression(pattern: "[\\[<]\\d{1,3}:\\d{2}(?:[.:]\\d{1,3})?[\\]>]")
    private static let offsetRegex = try? NSRegularExpression(pattern: "^\\[offset:\\s*([+-]?\\d+)\\s*\\]$", options: [.caseInsensitive])

    /// Parses standard LRC format text into chronological SyncedLyricLine array.
    /// Handles multiple timestamp tags per line (e.g. `[00:12.30][00:24.50] Refrain`),
    /// enhanced inline tags (`<00:12.50>`), millisecond fractions (`.xx` or `.xxx`),
    /// and [offset:±ms] shift directives.
    public static func parse(lrcContent: String) -> YMSyncedLyrics {
        var content = lrcContent
        if content.hasPrefix("\u{FEFF}") {
            content = String(content.dropFirst())
        }

        var offsetSeconds: TimeInterval = 0.0
        var parsed: [(time: TimeInterval, text: String)] = []

        let rawLines = content.components(separatedBy: .newlines)

        for rawLine in rawLines {
            var trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let lower = trimmed.lowercased()

            // Check for [offset:±ms]
            if let offsetRegex = offsetRegex {
                let nsStr = trimmed as NSString
                if let match = offsetRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: nsStr.length)),
                   match.numberOfRanges >= 2 {
                    let msStr = nsStr.substring(with: match.range(at: 1))
                    if let ms = Double(msStr) {
                        offsetSeconds = ms / 1000.0
                    }
                    continue
                }
            }

            // Skip ID3/LRC metadata header tags
            if lower.hasPrefix("[ti:") || lower.hasPrefix("[ar:") ||
               lower.hasPrefix("[al:") || lower.hasPrefix("[by:") ||
               lower.hasPrefix("[offset:") || lower.hasPrefix("[length:") ||
               lower.hasPrefix("[re:") || lower.hasPrefix("[ve:") ||
               lower.hasPrefix("[id:") {
                continue
            }

            guard let leadingRegex = leadingTagRegex else { continue }

            var lineTimestamps: [TimeInterval] = []

            // Extract only leading consecutive tags
            while true {
                let nsCurrent = trimmed as NSString
                guard let match = leadingRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: nsCurrent.length)) else {
                    break
                }

                if match.numberOfRanges >= 3 {
                    let minStr = nsCurrent.substring(with: match.range(at: 1))
                    let secStr = nsCurrent.substring(with: match.range(at: 2))
                    let minutes = Double(minStr) ?? 0.0
                    let seconds = Double(secStr) ?? 0.0
                    var fraction = 0.0

                    if match.numberOfRanges >= 4 && match.range(at: 3).location != NSNotFound {
                        let fracStr = nsCurrent.substring(with: match.range(at: 3))
                        if let f = Double("0.\(fracStr)") {
                            fraction = f
                        }
                    }

                    let totalSeconds = (minutes * 60.0) + seconds + fraction
                    lineTimestamps.append(totalSeconds)
                }

                let matchEnd = match.range.location + match.range.length
                trimmed = nsCurrent.substring(from: matchEnd)
            }

            guard !lineTimestamps.isEmpty else { continue }

            // Strip inline/enhanced/trailing tags from remaining line text
            var cleanedText = trimmed
            if let inlineRegex = inlineTagRegex {
                let nsClean = cleanedText as NSString
                cleanedText = inlineRegex.stringByReplacingMatches(
                    in: cleanedText,
                    range: NSRange(location: 0, length: nsClean.length),
                    withTemplate: ""
                )
            }
            cleanedText = cleanedText.trimmingCharacters(in: .whitespaces)

            for t in lineTimestamps {
                parsed.append((time: t, text: cleanedText))
            }
        }

        guard !parsed.isEmpty else {
            return YMSyncedLyrics(lines: [])
        }

        // Apply offset: positive offset moves text earlier -> max(0, time - offsetSeconds)
        if offsetSeconds != 0.0 {
            parsed = parsed.map { (time: max(0.0, $0.time - offsetSeconds), text: $0.text) }
        }

        // Sort chronologically
        parsed.sort { $0.time < $1.time }

        var result: [SyncedLyricLine] = []
        var idCounter = 0

        for item in parsed {
            let text = item.text.isEmpty ? "•••" : item.text
            // Collapse consecutive "•••"
            if text == "•••" && result.last?.text == "•••" {
                continue
            }
            result.append(SyncedLyricLine(id: idCounter, time: item.time, text: text))
            idCounter += 1
        }

        // Avoid trailing "•••" at the end of lyrics if there is no subsequent text
        while let last = result.last, last.text == "•••" {
            result.removeLast()
        }

        return YMSyncedLyrics(lines: result)
    }
}
