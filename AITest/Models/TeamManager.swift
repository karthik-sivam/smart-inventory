import Foundation
import SwiftUI
import SwiftData
@preconcurrency import FirebaseAuth
@preconcurrency import FirebaseFirestore

@MainActor
final class TeamManager: ObservableObject {

    static let shared = TeamManager()
    private let db = Firestore.firestore()

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

    private init() {
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

    func acceptInvite(_ invite: PendingInvite, modelContext: ModelContext) async {
        guard let myUID = Auth.auth().currentUser?.uid,
              let myEmail = Auth.auth().currentUser?.email else { return }

        let myName = AuthManager.shared.actorName

        try? await db.collection("workspaceInvites").document(invite.id)
            .updateData(["status": "accepted"])

        let memberData: [String: Any] = [
            "uid": myUID,
            "displayName": myName,
            "email": myEmail,
            "role": invite.role,
            "status": "active",
            "joinedAt": FieldValue.serverTimestamp()
        ]
        try? await db.collection("users").document(invite.ownerUID)
            .collection("members").document(myUID)
            .setData(memberData, merge: true)

        let member = TeamMember(uid: myUID, displayName: myName,
                                email: myEmail, role: invite.role, status: "active")
        modelContext.insert(member)
        modelContext.safeSave(context: "acceptInvite")
        joinWorkspace(ownerUID: invite.ownerUID, role: invite.role)
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
            return snap.documents.compactMap { doc -> MemberRecord? in
                let d = doc.data()
                guard let uid = d["uid"] as? String,
                      let name = d["displayName"] as? String,
                      let email = d["email"] as? String,
                      let role = d["role"] as? String else { return nil }
                return MemberRecord(uid: uid, displayName: name,
                                   email: email, role: role,
                                   status: d["status"] as? String ?? "active")
            }
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

    // MARK: - Supporting Types

    struct PendingInvite: Identifiable {
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
    }

    enum TeamError: LocalizedError {
        case notAuthenticated
        var errorDescription: String? { "You must be signed in." }
    }
}
