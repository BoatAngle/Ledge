import Foundation

/// A semantic version, compared properly.
///
/// `"0.10.0" > "0.9.0"` is false as a string and true as a version, which is
/// exactly the bug that makes hand-rolled update checks announce a downgrade.
public struct SemanticVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public var components: [Int]

    /// Accepts `1.2.3`, `v1.2.3`, `1.2`, and `1.2.3-beta.1` (the pre-release
    /// tail is ignored for ordering — a release tagged with one is still that
    /// version as far as "is there something newer" goes).
    public init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        if let dash = text.firstIndex(of: "-") { text = String(text[text.startIndex..<dash]) }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard let value = Int(part), value >= 0 else { return nil }
            numbers.append(value)
        }
        components = numbers
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        // Compare position by position, treating a missing component as zero,
        // so 1.2 and 1.2.0 are the same version rather than two.
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    // Equality and hashing have to agree with `<`, which pads. Left to the
    // synthesized conformance they compare the raw arrays, so 1.2 and 1.2.0
    // come out unequal while neither is less than the other — a broken
    // `Comparable` that a `Set` or a sort would eventually trip over.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.normalized == rhs.normalized
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(normalized)
    }

    /// Trailing zeros removed, so 1.2.0 and 1.2 have one identity.
    private var normalized: [Int] {
        var trimmed = components
        while trimmed.count > 1, trimmed.last == 0 { trimmed.removeLast() }
        return trimmed
    }

    public var description: String { components.map(String.init).joined(separator: ".") }
}

/// Asks GitHub whether there is a newer release, and nothing else.
///
/// This is the app's only outbound connection that isn't weather, so it is
/// worth being precise about what it does: one unauthenticated `GET` to the
/// public releases endpoint, at most once a day, carrying no identifier of any
/// kind — no account, no machine id, no install id, no usage. GitHub sees an
/// anonymous request for a public URL, the same as loading the releases page in
/// a browser. The user can switch it off, and when it is off, no request is
/// made at all.
public struct UpdateChecker: Sendable {
    public enum Result: Equatable, Sendable {
        case upToDate(current: String)
        case updateAvailable(version: String, url: URL)
        case failed(String)
    }

    public var endpoint: URL
    public var releasesPage: URL

    public init(
        endpoint: URL = URL(string: "https://api.github.com/repos/BoatAngle/Ledge/releases/latest")!,
        releasesPage: URL = URL(string: "https://github.com/BoatAngle/Ledge/releases/latest")!
    ) {
        self.endpoint = endpoint
        self.releasesPage = releasesPage
    }

    /// The shape of the sliver of GitHub's response we read.
    private struct Release: Decodable {
        var tag_name: String
        var html_url: String?
        var draft: Bool?
        var prerelease: Bool?
    }

    public func check(current currentVersion: String) async -> Result {
        guard let current = SemanticVersion(currentVersion) else {
            return .failed("Couldn't read this build's version number.")
        }

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 10
        // GitHub asks for these two. `User-Agent` is the app's name and version
        // and nothing more — no system profile, no identifier.
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Ledge/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                return .failed("GitHub replied \(http.statusCode).")
            }
            let release = try JSONDecoder().decode(Release.self, from: data)
            guard release.draft != true, release.prerelease != true else {
                return .upToDate(current: current.description)
            }
            guard let latest = SemanticVersion(release.tag_name) else {
                return .failed("Couldn't read the latest release's version number.")
            }
            guard latest > current else { return .upToDate(current: current.description) }
            let page = release.html_url.flatMap(URL.init(string:)) ?? releasesPage
            return .updateAvailable(version: latest.description, url: page)
        } catch is CancellationError {
            return .failed("Cancelled.")
        } catch {
            // Offline is the common case and is not a failure worth alarming
            // anybody about; the pane says so plainly and moves on.
            return .failed(error.localizedDescription)
        }
    }
}
