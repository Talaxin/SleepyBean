import Foundation

enum AppPreferences {
    private static let liveActivitiesEnabledKey = "settings.liveActivitiesEnabled"
    private static let iCloudBackupEnabledKey = "settings.iCloudBackupEnabled"

    static var liveActivitiesEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: liveActivitiesEnabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: liveActivitiesEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: liveActivitiesEnabledKey) }
    }

    static var iCloudBackupEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: iCloudBackupEnabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: iCloudBackupEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: iCloudBackupEnabledKey) }
    }

    static var displayVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        if build.isEmpty || version == build || version.hasSuffix(".\(build)") {
            return version
        }
        return "\(version) (\(build))"
    }
}
