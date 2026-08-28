import Foundation

/// Declared here rather than in `main.swift` on purpose. Top-level code
/// initialises its globals in statement order, so a `let` written below the
/// command dispatch would still be uninitialised when `printUsage()` reads it —
/// which segfaults instead of printing help.
let ledgeVersion = "0.3.0"

/// A very small flag parser.
///
/// Hand-rolled on purpose: `ledge` is meant to be droppable into any script
/// without pulling a package graph behind it, so the CLI has zero dependencies.
struct Arguments {
    private(set) var flags: [String: String] = [:]
    private(set) var switches: Set<String> = []
    private(set) var positional: [String] = []
    /// Everything after a bare `--`, handed through untouched.
    private(set) var passthrough: [String] = []

    /// Flags that take no value.
    static let booleanFlags: Set<String> = ["json", "indeterminate", "quiet", "help", "version"]

    init(_ raw: [String]) {
        var index = 0
        while index < raw.count {
            let token = raw[index]

            if token == "--" {
                passthrough = Array(raw[(index + 1)...])
                break
            }

            if token.hasPrefix("--") {
                let name = String(token.dropFirst(2))
                if let equals = name.firstIndex(of: "=") {
                    flags[String(name[name.startIndex..<equals])] = String(name[name.index(after: equals)...])
                } else if Self.booleanFlags.contains(name) {
                    switches.insert(name)
                } else if index + 1 < raw.count, !raw[index + 1].hasPrefix("--") {
                    flags[name] = raw[index + 1]
                    index += 1
                } else {
                    switches.insert(name)
                }
            } else {
                positional.append(token)
            }
            index += 1
        }
    }

    func string(_ name: String) -> String? { flags[name] }
    func has(_ name: String) -> Bool { switches.contains(name) || flags[name] != nil }

    func double(_ name: String) -> Double? {
        guard let raw = flags[name] else { return nil }
        // Accept `0.5` and `50%` alike — scripts produce both.
        if raw.hasSuffix("%"), let percent = Double(raw.dropLast()) { return percent / 100 }
        return Double(raw)
    }

    func int(_ name: String) -> Int? { flags[name].flatMap(Int.init) }
}
