import CloudKit
import SwiftUI
import UIKit

final class InviteShareDelegate: NSObject, UICloudSharingControllerDelegate {
    static let shared = InviteShareDelegate()

    var onShareChanged: (() -> Void)?

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

    func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
        if let share = csc.share {
            CloudKitSharingCoordinator.shared.cacheParticipantNames(from: share)
        }
        onShareChanged?()
    }

    func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
        UserDefaults.standard.set(false, forKey: CloudKitSharingCoordinator.hasShareKey)
        UserDefaults.standard.removeObject(forKey: CloudKitSharingCoordinator.sharedWithNameKey)
        onShareChanged?()
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
    @AppStorage("partner.sharedWithName") private var sharedWithName = ""
    @State private var isPreparing = false
    @State private var isStopping = false
    @State private var errorMessage: String?
    @State private var showStopConfirm = false

    private let sharingCoordinator = CloudKitSharingCoordinator.shared

    private var displaySharedName: String {
        let trimmed = sharedWithName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "parent" : trimmed
    }

    private var isShared: Bool {
        hasPartnerShare || sharingCoordinator.isShared(baby, modelContext: modelContext)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isShared {
                Button {
                    showStopConfirm = true
                } label: {
                    Label("Shared with \(displaySharedName)", systemImage: "person.2.fill")
                        .foregroundStyle(AppTheme.sleepPurple)
                }
                .buttonStyle(.plain)
                .disabled(isStopping)
            }

            if !isShared {
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
            } else {
                Text("Tap to stop sharing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            InviteShareDelegate.shared.onShareChanged = {
                Task { await refreshSharedName() }
            }
            Task { await refreshSharedName() }
        }
        .alert("Stop sharing?", isPresented: $showStopConfirm) {
            Button("Stop Sharing", role: .destructive) {
                stopSharing()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(displaySharedName) will no longer be able to see or edit \(baby.name)’s logs.")
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

    private func refreshSharedName() async {
        if let name = await sharingCoordinator.sharedWithDisplayName(for: baby) {
            sharedWithName = name
            hasPartnerShare = true
        }
    }

    private func prepareShare() {
        isPreparing = true
        Task {
            do {
                let preparedShare = try await sharingCoordinator.prepareShare(for: baby, modelContext: modelContext)
                sharingCoordinator.cacheParticipantNames(from: preparedShare)
                await refreshSharedName()
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

    private func stopSharing() {
        isStopping = true
        Task {
            do {
                try await sharingCoordinator.stopSharing(for: baby)
                hasPartnerShare = false
                sharedWithName = ""
            } catch {
                errorMessage = error.localizedDescription
            }
            isStopping = false
        }
    }
}
