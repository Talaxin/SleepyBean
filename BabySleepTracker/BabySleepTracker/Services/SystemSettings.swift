import UIKit

enum SystemSettings {
    static func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    static func openAppleAccountSettings() {
        let candidates = [
            "App-Prefs:root=APPLE_ACCOUNT",
            "prefs:root=APPLE_ACCOUNT",
            "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings",
        ]

        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            return
        }

        openAppSettings()
    }

    static func openiCloudSettings() {
        let candidates = [
            "App-Prefs:root=CASTLE",
            "prefs:root=CASTLE",
            "App-Prefs:root=APPLE_ACCOUNT&path=ICLOUD_SERVICE",
        ]

        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            return
        }

        openAppleAccountSettings()
    }
}
