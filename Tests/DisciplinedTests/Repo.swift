import Foundation

/// Files in the repository, for tests that check the script and the extension against the app.
enum Repo {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func url(_ path: String) -> URL { root.appendingPathComponent(path) }

    static func read(_ path: String) throws -> String {
        try String(contentsOf: url(path), encoding: .utf8)
    }

    static func json(_ path: String) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: url(path))) as? [String: Any] ?? [:]
    }

    /// The first capture group of `pattern` in a repository file.
    static func capture(_ pattern: String, in path: String) throws -> String? {
        let text = try read(path)
        let regex = try NSRegularExpression(pattern: pattern, options: .anchorsMatchLines)
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }
}
