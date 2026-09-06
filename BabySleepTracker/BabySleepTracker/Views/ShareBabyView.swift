import CloudKit
import SwiftUI
import UIKit

struct ShareBabyView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer

    func makeUIViewController(context: Context) -> UICloudSharingController {
        UICloudSharingController(share: share, container: container, delegate: context.coordinator)
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {}

        func itemTitle(for csc: UICloudSharingController) -> String? {
            "SleepyBean"
        }

        func itemThumbnailData(for csc: UICloudSharingController) -> Data? {
            nil
        }

        func itemType(for csc: UICloudSharingController) -> String? {
            "Baby profile"
        }
    }
}

struct ShareBabyButton: View {
    let baby: BabyProfile
    @Environment(\.modelContext) private var modelContext

    @State private var share: CKShare?
    @State private var showShareSheet = false
    @State private var isPreparing = false
    @State private var errorMessage: String?

    private let sharingCoordinator = CloudKitSharingCoordinator.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if sharingCoordinator.isShared(baby, modelContext: modelContext) {
                Label("Shared with partner", systemImage: "person.2.fill")
                    .foregroundStyle(AppTheme.sleepPurple)
            }

            Button {
                prepareShare()
            } label: {
                if isPreparing {
                    HStack {
                        ProgressView()
                        Text("Preparing share…")
                    }
                } else {
                    Label("Share with partner", systemImage: "person.badge.plus")
                }
            }
            .disabled(isPreparing || !SleepyBeanModelContainer.isCloudKitEnabled)

            if !SleepyBeanModelContainer.isCloudKitEnabled {
                Text("Build and install from Xcode with your Apple Developer account to enable partner sharing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Invite your partner by email or link. They can log naps and feeds on their own phone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let share {
                ShareBabyView(share: share, container: sharingCoordinator.ckContainer)
            }
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
                share = preparedShare
                showShareSheet = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isPreparing = false
        }
    }
}
