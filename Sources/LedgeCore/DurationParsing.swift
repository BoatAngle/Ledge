import Foundation

/// Parsing for human-written durations.
///
/// Lives in Core so the CLI, the app's timer module, and the Shortcuts action
/// all agree on what `1h30m` means. It was briefly duplicated between the CLI
/// and the timer provider, which is exactly the sort of thing that drifts.
public enum LedgeDuration {
    /// Accepts `25m`, `90s`, `1h30m`, `1:30`, `1:30:00`, or a bare number of
    /// seconds. Returns `nil` for anything it can't read, so callers can print
    /// a useful error instead of silently starting a zero-second timer.
    public static func parse(_ raw: String) -> TimeInterval? {
        let input = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !input.isEmpty else { return nil }

        if input.contains(":") {
            let components = input.split(separator: ":", omittingEmptySubsequences: false)
            let values = components.compactMap { Double($0) }
            // Every component must be a number — "1:ab" is not a duration.
            guard values.count == components.count else { return nil }
            switch values.count {
            case 2: return values[0] * 60 + values[1]
            case 3: return values[0] * 3600 + values[1] * 60 + values[2]
            default: return nil
            }
        }

        if let bare = Double(input) { return bare }

        var total: TimeInterval = 0
        var number = ""
        var sawUnit = false
        for character in input {
            if character.isNumber || character == "." {
                number.append(character)
                continue
            }
            guard let value = Double(number) else { return nil }
            switch character {
            case "h": total += value * 3600
            case "m": total += value * 60
            case "s": total += value
            default: return nil
            }
            sawUnit = true
            number = ""
        }
        // A trailing number with no unit, as in "1h30", reads as minutes.
        if !number.isEmpty {
            guard let leftover = Double(number) else { return nil }
            total += leftover * 60
        }
        return sawUnit && total > 0 ? total : nil
    }

    /// A default label for a timer of a given length.
    ///
    /// The bare duration, without the word "timer": the label sits beside a
    /// timer glyph and a countdown, so "20 minute timer / Timer" said
    /// everything twice. Mixed durations compose ("1 hour 30 minutes")
    /// instead of collapsing to "90 minute".
    public static func describe(_ duration: TimeInterval) -> String {
        let total = Int(duration.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        var parts: [String] = []
        if hours > 0 { parts.append(hours == 1 ? "1 hour" : "\(hours) hours") }
        if minutes > 0 { parts.append(minutes == 1 ? "1 minute" : "\(minutes) minutes") }
        if hours == 0, seconds > 0 { parts.append(seconds == 1 ? "1 second" : "\(seconds) seconds") }
        return parts.isEmpty ? "Timer" : parts.joined(separator: " ")
    }
}
