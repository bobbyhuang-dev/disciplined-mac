import Foundation

enum Domain {
    // Must match DOMAIN_RE in apply-blocklist.sh.
    private static let pattern = #"^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$"#

    /// Turns whatever the user typed ("https://www.YouTube.com/watch?v=1") into a bare domain ("youtube.com").
    static func normalize(_ input: String) -> String? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let r = s.range(of: "://") { s = String(s[r.upperBound...]) }
        if let i = s.firstIndex(where: { "/?#".contains($0) }) { s = String(s[..<i]) }
        if let at = s.lastIndex(of: "@") { s = String(s[s.index(after: at)...]) }
        if let colon = s.firstIndex(of: ":") { s = String(s[..<colon]) }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        while s.hasPrefix("www.") { s.removeFirst(4) }
        guard s.count <= 253, s.range(of: pattern, options: .regularExpression) != nil else { return nil }
        return s
    }

    /// Hostnames the helper writes for a domain. Must match the loop in apply-blocklist.sh.
    static func hosts(for domain: String) -> [String] {
        [domain, "www.\(domain)", "m.\(domain)"]
    }
}
