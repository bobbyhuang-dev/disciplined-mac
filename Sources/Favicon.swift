import AppKit

/// Site icons for the domain list. A blocked site resolves to 0.0.0.0, so icons come from a favicon
/// service the user picks in Settings instead of the site itself, and are cached on disk once found.
@MainActor
enum Favicon {
    enum Source: String, CaseIterable, Identifiable {
        case google, duckDuckGo

        var id: Self { self }

        var name: String {
            switch self {
            case .google: "Google"
            case .duckDuckGo: "DuckDuckGo"
            }
        }

        /// Each answers 404 (or with something that isn't an image) when it has no icon.
        fileprivate func url(for domain: String) -> URL {
            switch self {
            case .google: URL(string: "https://www.google.com/s2/favicons?domain=\(domain)&sz=64")!
            case .duckDuckGo: URL(string: "https://icons.duckduckgo.com/ip3/\(domain).ico")!
            }
        }
    }

    /// UserDefaults keys for the settings.
    static let showKey = "showSiteIcons"
    static let sourceKey = "siteIconSource"

    /// Keyed by `key(_:_:)`.
    private static var images: [String: NSImage] = [:]
    /// Lookups the source had no icon for; not asked again until the next launch.
    private static var missing: Set<String> = []

    private static let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("com.disciplined.mac/Favicons", isDirectory: true)

    /// The icon if it's in memory or on disk, without touching the network.
    static func cached(_ domain: String, from source: Source) -> NSImage? {
        let key = key(domain, source)
        if let image = images[key] { return image }
        guard let image = NSImage(contentsOf: folder.appendingPathComponent(key)) else { return nil }
        images[key] = image
        return image
    }

    /// nil if the source has no icon for the site, or can't be reached right now.
    static func load(_ domain: String, from source: Source) async -> NSImage? {
        if let image = cached(domain, from: source) { return image }
        let key = key(domain, source)
        if missing.contains(key) { return nil }
        // Offline, or the row went away mid-request: try again next time.
        guard let (data, response) = try? await URLSession.shared.data(from: source.url(for: domain)) else { return nil }
        guard (response as? HTTPURLResponse)?.statusCode == 200, let image = NSImage(data: data), image.isValid else {
            missing.insert(key)
            return nil
        }
        images[key] = image
        let file = folder.appendingPathComponent(key)
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        return image
    }

    /// Also the icon's path in the cache folder. Domains are validated by `Domain.normalize`, so they're safe as file names.
    private static func key(_ domain: String, _ source: Source) -> String {
        "\(source.rawValue)/\(domain)"
    }
}
