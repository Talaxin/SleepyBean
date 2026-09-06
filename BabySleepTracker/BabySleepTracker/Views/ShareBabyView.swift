import CloudKit
import SwiftUI
import UIKit

struct ShareParentsSection: View {
    let baby: BabyProfile
    @Environment(\.modelContext) private var modelContext

    @AppStorage("partner.hasShare") private var hasPartnerShare = false
    @AppStorage("partner.isParticipant") private var isParticipant = false
    @AppStorage("partner.sharedWithName") private var sharedWithName = ""
    @AppStorage("partner.customName") private var customName = ""
    @AppStorage("partner.inviteHint") private var inviteHint = ""
    @AppStorage("partner.inviteAccepted") private var inviteAccepted = false
    @AppStorage("partner.inviteCode") private var inviteCode = ""

    @State private var inviteURL: URL?
    @State private var joinCode = ""
    @State private var isWorking = false
    @State private var showStopConfirm = false
    @State private var errorMessage: String?

    private let sharingCoordinator = CloudKitSharingCoordinator.shared

    private var parentName: String {
        let custom = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { return custom }
        let stored = sharedWithName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stored.isEmpty, !CloudKitSharingCoordinator.isContactHandle(stored) {
            return stored
        }
        let hint = inviteHint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !hint.isEmpty { return hint }
        return stored.isEmpty ? "" : stored
    }

    private var isOwnerWaiting: Bool {
        hasPartnerShare && !isParticipant && !inviteAccepted
    }

    private var isConnected: Bool {
        isParticipant || inviteAccepted
    }

    var body: some View {
        Section {
            if isConnected {
                connectedRows
            } else if isOwnerWaiting {
                waitingRows
            } else {
                setupRows
            }
        } header: {
            Text("Parents")
        } footer: {
            footerText
        }
        .onAppear {
            Task { await refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sleepyBeanDidReceiveShare)) { _ in
            Task { await refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sleepyBeanPartnerDataDidChange)) { _ in
            Task { await refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sleepyBeanShareAcceptFailed)) { note in
            errorMessage = note.userInfo?["error"] as? String
            isWorking = false
        }
        .alert("Sharing", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert(isParticipant ? "Leave this share?" : "Stop sharing?", isPresented: $showStopConfirm) {
            Button(isParticipant ? "Leave" : "Stop Sharing", role: .destructive) {
                Task { await stopSharing() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var connectedRows: some View {
        LabeledContent("Status", value: isParticipant ? "Joined" : "Sharing")
        TextField("Other parent’s name", text: $customName)
            .onChange(of: customName) { _, newValue in
                sharingCoordinator.setCustomPartnerName(newValue)
            }
        if !parentName.isEmpty {
            LabeledContent(isParticipant ? "Sharing with" : "Shared with", value: parentName)
        }
        Button(isParticipant ? "Leave share" : "Stop sharing", role: .destructive) {
            showStopConfirm = true
        }
    }

    @ViewBuilder
    private var waitingRows: some View {
        if !inviteCode.isEmpty {
            LabeledContent("Invite code") {
                Text(inviteCode)
                    .font(.title2.weight(.semibold).monospaced())
                    .textSelection(.enabled)
            }
        }
        if let inviteURL {
            ShareLink("Send invite", item: inviteURL, subject: Text("SleepyBean"), message: Text("Join \(baby.name) on SleepyBean. Code \(inviteCode)."))
        }
        Button("Copy code") {
            UIPasteboard.general.string = inviteCode
        }
        Button("Stop sharing", role: .destructive) {
            showStopConfirm = true
        }
    }

    @ViewBuilder
    private var setupRows: some View {
        Button {
            Task { await createInvite() }
        } label: {
            if isWorking {
                HStack {
                    ProgressView()
                    Text("Creating invite…")
                }
            } else {
                Text("Invite a parent")
            }
        }
        .disabled(isWorking)

        TextField("Invite code", text: $joinCode)
            .textInputAutocapitalization(.characters)
            .disableAutocorrection(true)
            .font(.body.monospaced())
            .onChange(of: joinCode) { _, newValue in
                joinCode = CloudKitSharingCoordinator.normalizedInviteCode(newValue)
            }

        Button("Join") {
            Task { await join() }
        }
        .disabled(isWorking || CloudKitSharingCoordinator.normalizedInviteCode(joinCode).count != 6)
    }

    private var footerText: Text {
        if isConnected {
            return Text("Naps and feeds stay in sync while SleepyBean is open.")
        }
        if isOwnerWaiting {
            return Text("Send the invite, or have them type this code in Settings → Parents.")
        }
        return Text("Create an invite on one phone. The other parent enters the code here.")
    }

    private func refresh() async {
        _ = await sharingCoordinator.sharedWithDisplayName(for: baby)
        hasPartnerShare = sharingCoordinator.hasPartnerShare
        isParticipant = UserDefaults.standard.bool(forKey: CloudKitSharingCoordinator.isParticipantKey)
        sharedWithName = UserDefaults.standard.string(forKey: CloudKitSharingCoordinator.sharedWithNameKey) ?? sharedWithName
        customName = UserDefaults.standard.string(forKey: CloudKitSharingCoordinator.customNameKey) ?? customName
        inviteHint = UserDefaults.standard.string(forKey: CloudKitSharingCoordinator.inviteHintKey) ?? inviteHint
        inviteAccepted = UserDefaults.standard.bool(forKey: CloudKitSharingCoordinator.inviteAcceptedKey)
        inviteCode = UserDefaults.standard.string(forKey: CloudKitSharingCoordinator.inviteCodeKey) ?? inviteCode
        inviteURL = await sharingCoordinator.inviteURL(for: baby)
        if hasPartnerShare, !isParticipant, inviteCode.isEmpty, let share = await sharingCoordinator.currentShare(for: baby) {
            inviteCode = (try? await sharingCoordinator.publishInvite(for: share)) ?? inviteCode
            inviteURL = share.url ?? inviteURL
        }
    }

    private func createInvite() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let share = try await sharingCoordinator.prepareShare(for: baby, modelContext: modelContext)
            inviteURL = share.url
            inviteCode = try await sharingCoordinator.publishInvite(for: share)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func join() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await sharingCoordinator.join(usingCode: CloudKitSharingCoordinator.normalizedInviteCode(joinCode))
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func stopSharing() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await sharingCoordinator.stopSharing(for: baby)
            hasPartnerShare = false
            isParticipant = false
            inviteAccepted = false
            sharedWithName = ""
            customName = ""
            inviteHint = ""
            inviteCode = ""
            inviteURL = nil
            joinCode = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
