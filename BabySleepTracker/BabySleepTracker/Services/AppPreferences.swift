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
        get { UserDefaults.standard.bool(forKey: iCloudBackupEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: iCloudBackupEnabledKey) }
    }
}
