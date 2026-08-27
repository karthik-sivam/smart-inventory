import Foundation
@preconcurrency import FirebaseFirestore

// MARK: - Invite acceptance plan (pure; no Firestore I/O)

/// The seven fields hardened rules permit on `users/{ownerUID}/members/{memberUID}`.
/// `joinedAt` is always `FieldValue.serverTimestamp()` at commit time.
struct AcceptedMemberPayload: Equatable {
    let uid: String
    let displayName: String
    let email: String
    let role: String
    let status: String
    let inviteId: String

    static let firestoreKeys: Set<String> = [
        "uid", "displayName", "email", "role", "status", "inviteId", "joinedAt"
    ]

    /// Merge is required by the existing iOS/Android write contract.
    /// Hardened rules still require `request.resource.data` to contain *only*
    /// these seven keys after the merge is applied.
    var firestoreData: [String: Any] {
        [
            "uid": uid,
            "displayName": displayName,
            "email": email,
            "role": role,
            "status": status,
            "inviteId": inviteId,
            "joinedAt": FieldValue.serverTimestamp()
        ]
    }
}

/// Describes the two Firestore mutations that must commit in one WriteBatch,
/// plus the local workspace join that is allowed only after that commit succeeds.
struct AcceptInvitePlan: Equatable {
    let inviteId: String
    let inviteStatusUpdate: String
    let ownerUID: String
    let memberUID: String
    let member: AcceptedMemberPayload
    let mergeMember: Bool
    let joinOwnerUID: String
    let joinRole: String

    /// Invite update + member set. Production committers must schedule both
    /// in one batch and call `commit` once.
    var mutationCount: Int { 2 }

    var inviteDocumentPath: String { "workspaceInvites/\(inviteId)" }
    var memberDocumentPath: String { "users/\(ownerUID)/members/\(memberUID)" }
}

enum InviteAcceptancePlanner {
    static func plan(
        inviteId: String,
        ownerUID: String,
        role: String,
        authenticatedUID: String,
        displayName: String,
        email: String
    ) -> AcceptInvitePlan {
        let member = AcceptedMemberPayload(
            uid: authenticatedUID,
            displayName: displayName,
            email: email,
            role: role,
            status: "active",
            inviteId: inviteId
        )
        return AcceptInvitePlan(
            inviteId: inviteId,
            inviteStatusUpdate: "accepted",
            ownerUID: ownerUID,
            memberUID: authenticatedUID,
            member: member,
            mergeMember: true,
            joinOwnerUID: ownerUID,
            joinRole: role
        )
    }
}

// MARK: - Remote committer

@MainActor
protocol InviteAcceptanceCommitter {
    func commit(_ plan: AcceptInvitePlan) async throws
}

/// Production committer: one `WriteBatch`, exactly two mutations, one `commit()`.
@MainActor
final class FirestoreInviteAcceptanceCommitter: InviteAcceptanceCommitter {
    private let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func commit(_ plan: AcceptInvitePlan) async throws {
        let batch = db.batch()

        let inviteRef = db.collection("workspaceInvites").document(plan.inviteId)
        batch.updateData(["status": plan.inviteStatusUpdate], forDocument: inviteRef)

        let memberRef = db.collection("users").document(plan.ownerUID)
            .collection("members").document(plan.memberUID)
        batch.setData(plan.member.firestoreData, forDocument: memberRef, merge: plan.mergeMember)

        try await batch.commit()
    }
}
