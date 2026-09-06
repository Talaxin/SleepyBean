import CloudKit
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        if let storeURL = SleepyBeanModelContainer.storeURL {
            Task { @MainActor in
                CloudKitSharingCoordinator.shared.configure(storeURL: storeURL)
            }
        }
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = CloudKitShareSceneDelegate.self
        if let metadata = options.cloudKitShareMetadata {
            Task { @MainActor in
                await Self.acceptShare(metadata)
            }
        }
        return configuration
    }

    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        Task { @MainActor in
            await Self.acceptShare(cloudKitShareMetadata)
        }
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        Task { @MainActor in
            await CloudKitSharingCoordinator.shared.acceptShare(from: url)
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        let notification = CKNotification(fromRemoteNotificationDictionary: userInfo)
        guard notification?.subscriptionID?.contains("sleepybean-partner") == true
                || notification?.notificationType == .database else {
            completionHandler(.noData)
            return
        }
        Task { @MainActor in
            CloudKitSharingCoordinator.shared.handleRemotePartnerNotification()
            completionHandler(.newData)
        }
    }

    @MainActor
    static func acceptShare(_ metadata: CKShare.Metadata) async {
        do {
            try await CloudKitSharingCoordinator.shared.acceptShare(metadata: metadata)
        } catch {
            print("Failed to accept CloudKit share: \(error.localizedDescription)")
        }
    }
}

final class CloudKitShareSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        Task { @MainActor in
            await AppDelegate.acceptShare(cloudKitShareMetadata)
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for context in URLContexts {
            Task { @MainActor in
                await CloudKitSharingCoordinator.shared.acceptShare(from: context.url)
            }
        }
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        if let url = userActivity.webpageURL {
            Task { @MainActor in
                await CloudKitSharingCoordinator.shared.acceptShare(from: url)
            }
        }
    }
}
