import Foundation
import SwiftUI

enum AriaRelease {
    static let version = Bundle.main.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
    ) as? String ?? "1.6.0"

    static var displayText: String {
        "Version \(version)"
    }
}

@main
struct AriaApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
