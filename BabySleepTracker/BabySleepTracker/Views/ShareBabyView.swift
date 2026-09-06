import CloudKit
import SwiftUI
import UIKit

final class InviteShareDelegate: NSObject, UICloudSharingControllerDelegate {
    static let shared = InviteShareDelegate()

    func present(share: CKShare, container: CKContainer) {
        DispatchQueue.main.async {
            guard let presenter = Self.topViewController() else { return }
            let controller = UICloudSharingController(share: share, container: container)
            controller.delegate = self
            controller.availablePermissions = [.allowReadWrite, .allowPrivate]
            controller.popoverPresentationController?.sourceView = presenter.view
            controller.popoverPresentationController?.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.midY,
                width: 0,
                height: 0
            )
            presenter.present(controller, animated: true)
        }
    }

    func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
        print("Cloud sharing save failed: \(error.localizedDescription)")
    }

    func itemTitle(for csc: UICloudSharingController) -> String? {
        "SleepyBean"
    }

    func itemType(for csc: UICloudSharingController) -> String? {
        "com.sleepybean.tracker.baby"
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.first { $0.activationState == .foregroundActive }?.keyWindow
            ?? scenes.flatMap(\.windows).first { $0.isKeyWindow }
            ?? scenes.flatMap(\.windows).first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

struct ShareBabyButton: View {
    let baby: BabyProfile
    @Environment(\.modelContext) private var modelContext

    @AppStorage("partner.hasShare") private var hasPartnerShare = false
    @State private var isPreparing = false
    @State private var errorMessage: String?

    private let sharingCoordinator = CloudKitSharingCoordinator.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if hasPartnerShare || sharingCoordinator.isShared(baby, modelContext: modelContext) {
                Label("Shared with another parent", systemImage: "person.2.fill")
                    .foregroundStyle(AppTheme.sleepPurple)
            }

            Button {
                prepareShare()
            } label: {
                if isPreparing {
                    HStack {
                        ProgressView()
                        Text("Preparing invite…")
                    }
                } else {
                    Label("Invite Parent", systemImage: "person.badge.plus")
                }
            }
            .disabled(isPreparing)

            Text("Sends a Messages or Mail invite. The other parent needs SleepyBean installed and signed in to iCloud.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .alert("Sharing", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func prepareShare() {
        isPreparing = true
        Task {
            do {
                let preparedShare = try await sharingCoordinator.prepareShare(for: baby, modelContext: modelContext)
                InviteShareDelegate.shared.present(
                    share: preparedShare,
                    container: sharingCoordinator.ckContainer
                )
            } catch {
                errorMessage = error.localizedDescription
            }
            isPreparing = false
        }
    }
}
