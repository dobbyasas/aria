import Foundation
import UserNotifications

final class ProvisioningExpiryMonitor: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ProvisioningExpiryMonitor()

    private struct Warning {
        let hoursBeforeExpiry: Int

        var identifier: String {
            "aria.provisioning-expiry.\(hoursBeforeExpiry)h"
        }

        var remainingText: String {
            hoursBeforeExpiry == 1 ? "1 hour" : "\(hoursBeforeExpiry) hours"
        }
    }

    private static let warnings = [48, 24, 12, 4, 1].map(Warning.init)
    private let notificationCenter = UNUserNotificationCenter.current()

    private override init() {
        super.init()
    }

    func configureNotifications() async {
        notificationCenter.delegate = self
        let identifiers = Self.warnings.map(\.identifier)
        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)

        guard let expirationDate = Self.embeddedProfileExpirationDate() else { return }

        let settings = await notificationCenter.notificationSettings()
        let isAuthorized: Bool
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            isAuthorized = true
        case .notDetermined:
            isAuthorized = (try? await notificationCenter.requestAuthorization(
                options: [.alert, .sound]
            )) == true
        case .denied:
            isAuthorized = false
        @unknown default:
            isAuthorized = false
        }

        guard isAuthorized else { return }

        for warning in Self.warnings {
            let deliveryDate = expirationDate.addingTimeInterval(
                -TimeInterval(warning.hoursBeforeExpiry * 60 * 60)
            )
            guard deliveryDate.timeIntervalSinceNow > 1 else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Aria expires soon"
            content.body = "Your iPhone/iPad build expires in \(warning.remainingText). Reinstall it from Xcode before then."
            content.sound = .default
            content.threadIdentifier = "aria.provisioning-expiry"
            content.userInfo = ["expirationDate": expirationDate.timeIntervalSince1970]

            let dateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: deliveryDate
            )
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: dateComponents,
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: warning.identifier,
                content: content,
                trigger: trigger
            )
            try? await notificationCenter.add(request)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    static func embeddedProfileExpirationDate(in bundle: Bundle = .main) -> Date? {
        guard
            let profileURL = bundle.url(
                forResource: "embedded",
                withExtension: "mobileprovision"
            ),
            let data = try? Data(contentsOf: profileURL)
        else {
            return nil
        }
        return expirationDate(inProvisioningProfileData: data)
    }

    static func expirationDate(inProvisioningProfileData data: Data) -> Date? {
        let startMarker = Data("<?xml".utf8)
        let endMarker = Data("</plist>".utf8)
        guard
            let startRange = data.range(of: startMarker),
            let endRange = data.range(of: endMarker),
            startRange.lowerBound < endRange.upperBound
        else {
            return nil
        }

        let plistData = data.subdata(
            in: startRange.lowerBound..<endRange.upperBound
        )
        guard
            let profile = try? PropertyListSerialization.propertyList(
                from: plistData,
                options: [],
                format: nil
            ) as? [String: Any]
        else {
            return nil
        }
        return profile["ExpirationDate"] as? Date
    }
}
