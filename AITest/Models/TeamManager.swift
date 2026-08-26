import Foundation
import SwiftUI
import SwiftData
@preconcurrency import FirebaseAuth
@preconcurrency import FirebaseFirestore

@MainActor
final class TeamManager: ObservableObject {

    static let shared = TeamManager()
    private let db = Firestore.firestore()
    private let inviteCommitter: InviteAcceptanceCommitter

    @Published private(set) var activeWorkspaceOwnerUID: String? = nil
    @Published private(set) var currentRole: String = "owner"

    var isOwner: Bool { currentRole == "owner" }
    var canEdit: Bool { currentRole == "owner" || currentRole == "manager" }
    var canDeleteItem: Bool { currentRole == "owner" || currentRole == "manager" }
    var canDeleteStorage: Bool { currentRole == "owner" }
    var canManageTeam: Bool { currentRole == "owner" }
    var isInTeamWorkspace: Bool { activeWorkspaceOwnerUID != nil }

    var effectiveUID: String? {
        activeWorkspaceOwnerUID ?? Auth.auth().currentUser?.uid
    }

    init(inviteCommitter: InviteAcceptanceCommitter = FirestoreInviteAcceptanceCommitter()) {
        self.inviteCommitter = inviteCommitter
        restoreWorkspaceState()
    }

    // MARK: - Workspace Switching

    func joinWorkspace(ownerUID: String, role: String) {
        activeWorkspaceOwnerUID = ownerUID
        currentRole = role
        UserDefaults.standard.set(ownerUID, forKey: "stoqly_activeWorkspaceOwnerUID")
        UserDefaults.standard.set(role, forKey: "stoqly_currentRole")
    }

    func leaveWorkspace() {
        activeWorkspaceOwnerUID = nil
        currentRole = "owner"
        UserDefaults.standard.removeObject(forKey: "stoqly_activeWorkspaceOwnerUID")
        UserDefaults.standard.removeObject(forKey: "stoqly_currentRole")
    }

    private func restoreWorkspaceState() {
        activeWorkspaceOwnerUID = UserDefaults.standard.string(forKey: "stoqly_activeWorkspaceOwnerUID")
        currentRole = UserDefaults.standard.string(forKey: "stoqly_currentRole") ?? "owner"
    }

    func reset() {
        leaveWorkspace()
    }

    // MARK: - Invite Flow

    func sendInvite(to email: String, role: String) async -> Result<Void, Error> {
        guard let ownerUID = Auth.auth().currentUser?.uid else {
            return .failure(TeamError.notAuthenticated)
        }
        let ownerName = AuthManager.shared.actorName
        let data: [String: Any] = [
            "ownerUID": ownerUID,
            "ownerDisplayName": ownerName,
            "inviteeEmail": email.lowercased(),
            "role": role,
            "status": "pending",
            "createdAt": FieldValue.serverTimestamp()
        ]
        do {
            try await db.collection("workspaceInvites").addDocument(data: data)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func checkPendingInvites() async -> [PendingInvite] {
        guard let email = Auth.auth().currentUser?.email?.lowercased() else { return [] }
        do {
            let snap = try await db.collection("workspaceInvites")
                .whereField("inviteeEmail", isEqualTo: email)
                .whereField("status", isEqualTo: "pending")
                .getDocuments()
            return snap.documents.compactMap { doc -> PendingInvite? in
                let d = doc.data()
                guard let ownerUID = d["ownerUID"] as? String,
                      let ownerName = d["ownerDisplayName"] as? String,
                      let role = d["role"] as? String else { return nil }
                return PendingInvite(id: doc.documentID, ownerUID: ownerUID,
                                    ownerName: ownerName, role: role)
            }
        } catch {
            return []
        }
    }

    func acceptInvite(_ invite: PendingInvite, modelContext: ModelContext) async -> Result<Void, Error> {
        guard let myUID = Auth.auth().currentUser?.uid,
              let myEmail = Auth.auth().currentUser?.email,
              !myEmail.isEmpty else {
            return .failure(TeamError.notAuthenticated)
        }
        return await acceptInvite(
            invite,
            authenticatedUID: myUID,
            displayName: AuthManager.shared.actorName,
            email: myEmail,
            modelContext: modelContext
        )
    }

    /// Testable acceptance path. Remote batch commit is the authority gate;
    /// local persistence and `joinWorkspace` run only after it succeeds.
    func acceptInvite(
        _ invite: PendingInvite,
        authenticatedUID: String,
        displayName: String,
        email: String,
        modelContext: ModelContext
    ) async -> Result<Void, Error> {
        let plan = InviteAcceptancePlanner.plan(
            inviteId: invite.id,
            ownerUID: invite.ownerUID,
            role: invite.role,
            authenticatedUID: authenticatedUID,
            displayName: displayName,
            email: email
        )

        do {
            try await inviteCommitter.commit(plan)
        } catch {
            return .failure(error)
        }

        // Remote membership is now real. Join after local upsert/save; if local
        // persistence fails, still join so the user is not stuck on an already-
        // accepted invite, and surface the save error through Result.
        do {
            try upsertLocalMember(from: plan.member, modelContext: modelContext)
        } catch {
            joinWorkspace(ownerUID: plan.joinOwnerUID, role: plan.joinRole)
            return .failure(error)
        }

        let saved = modelContext.safeSave(context: "acceptInvite")
        joinWorkspace(ownerUID: plan.joinOwnerUID, role: plan.joinRole)
        guard saved else {
            return .failure(TeamError.localSaveFailed)
        }
        return .success(())
    }

    func declineInvite(_ invite: PendingInvite) async {
        try? await db.collection("workspaceInvites").document(invite.id)
            .updateData(["status": "declined"])
    }

    // MARK: - Team Members

    func fetchMembers() async -> [MemberRecord] {
        guard let ownerUID = Auth.auth().currentUser?.uid else { return [] }
        do {
            let snap = try await db.collection("users").document(ownerUID)
                .collection("members").getDocuments()
            return snap.documents.compactMap { MemberRecord.fromFirestore($0.data()) }
        } catch {
            return []
        }
    }

    func removeMember(uid: String) async {
        guard let ownerUID = Auth.auth().currentUser?.uid else { return }
        try? await db.collection("users").document(ownerUID)
            .collection("members").document(uid)
            .updateData(["status": "removed"])
    }

    // MARK: - Local member upsert

    private func upsertLocalMember(
        from payload: AcceptedMemberPayload,
        modelContext: ModelContext
    ) throws {
        let memberUID = payload.uid
        let descriptor = FetchDescriptor<TeamMember>(
            predicate: #Predicate { $0.uid == memberUID }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            existing.displayName = payload.displayName
            existing.email = payload.email
            existing.role = payload.role
            existing.status = payload.status
            existing.inviteId = payload.inviteId
            existing.joinedAt = Date()
        } else {
            modelContext.insert(
                TeamMember(
                    uid: payload.uid,
                    displayName: payload.displayName,
                    email: payload.email,
                    role: payload.role,
                    status: payload.status,
                    inviteId: payload.inviteId
                )
            )
        }
    }

    // MARK: - Supporting Types

    struct PendingInvite: Identifiable, Equatable {
        let id: String
        let ownerUID: String
        let ownerName: String
        let role: String
    }

    struct MemberRecord: Identifiable {
        let id = UUID()
        let uid: String
        let displayName: String
        let email: String
        let role: String
        let status: String
        /// Nil when a legacy member document has no `inviteId`.
        let inviteId: String?

        static func fromFirestore(_ data: [String: Any]) -> MemberRecord? {
            guard let uid = data["uid"] as? String,
                  let name = data["displayName"] as? String,
                  let email = data["email"] as? String,
                  let role = data["role"] as? String else { return nil }
            return MemberRecord(
                uid: uid,
                displayName: name,
                email: email,
                role: role,
                status: data["status"] as? String ?? "active",
                inviteId: data["inviteId"] as? String
            )
        }
    }

    enum TeamError: LocalizedError {
        case notAuthenticated
        case localSaveFailed

        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return L("team_error_not_authenticated", "You must be signed in.")
            case .localSaveFailed:
                return L(
                    "invite_accept_local_save_failed",
                    "Couldn't save team membership on this device. Try again."
                )
            }
        }
    }
}
