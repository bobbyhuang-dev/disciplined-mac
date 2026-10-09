import SwiftUI

@main
enum Entry {
    static func main() {
        // The same binary doubles as the browser extension's native messaging host.
        if let browser = NativeHost.launchingBrowser { NativeHost.run(for: browser) }
        DisciplinedApp.main()
    }
}
