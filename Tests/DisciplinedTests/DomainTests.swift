import Testing

struct DomainTests {
    @Test(arguments: [
        ("youtube.com", "youtube.com"),
        ("  YouTube.COM \n", "youtube.com"),
        ("https://www.youtube.com/watch?v=1", "youtube.com"),
        ("www.www.example.com", "example.com"),
        ("http://m.reddit.com:8080/r/all", "m.reddit.com"),
        ("news.ycombinator.com#top", "news.ycombinator.com"),
        ("example.com?q=1", "example.com"),
        ("user:pass@example.com/", "example.com"),
        ("example.com.", "example.com"),
        ("bbc.co.uk", "bbc.co.uk"),
        ("xn--fiqs8s.cn", "xn--fiqs8s.cn"),
    ])
    func normalizesWhatUsersPaste(input: String, expected: String) {
        #expect(Domain.normalize(input) == expected)
    }

    /// Anything accepted here ends up in /etc/hosts and the browser rules, so junk must be refused.
    @Test(arguments: [
        "", "   ", "localhost", "not a domain.com", "exa_mple.com", "-example.com", "example-.com",
        "a..com", "http://", "例子.cn", "example.com\n0.0.0.0 bank.com",
        String(repeating: "a.", count: 130) + "com",
    ])
    func rejectsInvalidInput(input: String) {
        #expect(Domain.normalize(input) == nil)
    }

    /// The native host drops stored domains that don't normalize to themselves, so a saved domain
    /// that normalized differently would silently stop being sent to the extension.
    @Test(arguments: ["https://www.youtube.com/watch?v=1", "M.Reddit.com", "bbc.co.uk.", "user@example.com:443"])
    func normalizedDomainsAreStable(input: String) throws {
        let domain = try #require(Domain.normalize(input))
        #expect(Domain.normalize(domain) == domain)
    }
}
