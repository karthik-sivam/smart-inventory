import XCTest
import SwiftData
@testable import SmartInventory

private enum FakeCommitError: Error {
    case rejected
}

@MainActor
private final class FakeInviteAcceptanceCommitter: InviteAcceptanceCommitter {
    enum Outcome {
        case success
        case failure(Error)
    }

    var outcome: Outcome
    private(set) var committedPlans: [AcceptInvitePlan] = []

    init(outcome: Outcome) {
        self.outcome = outcome
    }

    func commit(_ plan: AcceptInvitePlan) async throws {
        committedPlans.append(plan)
        switch outcome {
        case .success:
            return
        case .failure(let error):
            throw error
        }
    }
}

final class InviteAcceptanceTests: XCTestCase {
    private var previousOwnerUID: Any?
    private var previousRole: Any?

    override func setUp() {
        super.setUp()
        previousOwnerUID = UserDefaults.standard.object(forKey: "stoqly_activeWorkspaceOwnerUID")
        previousRole = UserDefaults.standard.object(forKey: "stoqly_currentRole")
        UserDefaults.standard.removeObject(forKey: "stoqly_activeWorkspaceOwnerUID")
        UserDefaults.standard.removeObject(forKey: "stoqly_currentRole")
    }

    override func tearDown() {
        if let previousOwnerUID {
            UserDefaults.standard.set(previousOwnerUID, forKey: "stoqly_activeWorkspaceOwnerUID")
        } else {
            UserDefaults.standard.removeObject(forKey: "stoqly_activeWorkspaceOwnerUID")
        }
        if let previousRole {
            UserDefaults.standard.set(previousRole, forKey: "stoqly_currentRole")
        } else {
            UserDefaults.standard.removeObject(forKey: "stoqly_currentRole")
        }
        super.tearDown()
    }

    @MainActor
    private func sampleInvite(
        id: String = "inv-1",
        ownerUID: String = "owner-9",
        role: String = "manager"
    ) -> TeamManager.PendingInvite {
        TeamManager.PendingInvite(
            id: id,
            ownerUID: ownerUID,
            ownerName: "Boss",
            role: role
        )
    }

    @MainActor
    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([TeamMember.self])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return (container, ModelContext(container))
    }

    @MainActor
    private func makeManager(outcome: FakeInviteAcceptanceCommitter.Outcome) -> (TeamManager, FakeInviteAcceptanceCommitter) {
        let committer = FakeInviteAcceptanceCommitter(outcome: outcome)
        return (TeamManager(inviteCommitter: committer), committer)
    }

    // MARK: - Payload / plan

    func testMemberPayloadContainsInviteIdAndApprovedKeys() {
        let plan = InviteAcceptancePlanner.plan(
            inviteId: "inv-99",
            ownerUID: "owner-1",
            role: "viewer",
            authenticatedUID: "user-7",
            displayName: "Ada",
            email: "ada@example.com"
        )

        XCTAssertEqual(plan.member.inviteId, "inv-99")
        XCTAssertEqual(plan.member.uid, "user-7")
        XCTAssertEqual(plan.member.displayName, "Ada")
        XCTAssertEqual(plan.member.email, "ada@example.com")
        XCTAssertEqual(plan.member.role, "viewer")
        XCTAssertEqual(plan.member.status, "active")
        XCTAssertEqual(
            Set(plan.member.firestoreData.keys),
            AcceptedMemberPayload.firestoreKeys
        )
        XCTAssertTrue(AcceptedMemberPayload.firestoreKeys.contains("inviteId"))
    }

    func testAcceptancePlanSchedulesBothMutationsAtomically() {
        let plan = InviteAcceptancePlanner.plan(
            inviteId: "inv-1",
            ownerUID: "owner-9",
            role: "manager",
            authenticatedUID: "user-2",
            displayName: "Me",
            email: "me@example.com"
        )

        XCTAssertEqual(plan.mutationCount, 2)
        XCTAssertEqual(plan.inviteDocumentPath, "workspaceInvites/inv-1")
        XCTAssertEqual(plan.inviteStatusUpdate, "accepted")
        XCTAssertEqual(plan.memberDocumentPath, "users/owner-9/members/user-2")
        XCTAssertTrue(plan.mergeMember)
        XCTAssertEqual(plan.joinOwnerUID, "owner-9")
        XCTAssertEqual(plan.joinRole, "manager")
        XCTAssertEqual(plan.member.inviteId, "inv-1")
    }

    // MARK: - Remote commit gate

    @MainActor
    func testSuccessfulCommitJoinsWorkspaceAndPersistsLocalMember() async throws {
        let (container, context) = try makeContext()
        let (manager, committer) = makeManager(outcome: .success)
        XCTAssertFalse(manager.isInTeamWorkspace)

        let result = await manager.acceptInvite(
            sampleInvite(),
            authenticatedUID: "user-2",
            displayName: "Me",
            email: "me@example.com",
            modelContext: context
        )

        guard case .success = result else {
            XCTFail("expected success, got \(result)")
            return
        }
        XCTAssertEqual(committer.committedPlans.count, 1)
        XCTAssertEqual(committer.committedPlans.first?.member.inviteId, "inv-1")
        XCTAssertTrue(manager.isInTeamWorkspace)
        XCTAssertEqual(manager.activeWorkspaceOwnerUID, "owner-9")
        XCTAssertEqual(manager.currentRole, "manager")

        let members = try context.fetch(FetchDescriptor<TeamMember>())
        XCTAssertEqual(members.count, 1)
        XCTAssertEqual(members.first?.uid, "user-2")
        XCTAssertEqual(members.first?.inviteId, "inv-1")
        XCTAssertEqual(members.first?.status, "active")
        XCTAssertEqual(members.first?.role, "manager")
        _ = container
    }

    @MainActor
    func testFailedCommitLeavesWorkspaceUnjoinedAndDoesNotPersistMember() async throws {
        let (container, context) = try makeContext()
        let (manager, committer) = makeManager(outcome: .failure(FakeCommitError.rejected))

        let result = await manager.acceptInvite(
            sampleInvite(),
            authenticatedUID: "user-2",
            displayName: "Me",
            email: "me@example.com",
            modelContext: context
        )

        guard case .failure = result else {
            XCTFail("expected failure, got \(result)")
            return
        }
        XCTAssertEqual(committer.committedPlans.count, 1)
        XCTAssertFalse(manager.isInTeamWorkspace)
        XCTAssertNil(manager.activeWorkspaceOwnerUID)
        XCTAssertEqual(manager.currentRole, "owner")

        let members = try context.fetch(FetchDescriptor<TeamMember>())
        XCTAssertTrue(members.isEmpty)
        _ = container
    }

    @MainActor
    func testAcceptInviteUpsertsLocalMemberByUID() async throws {
        let (container, context) = try makeContext()
        let existing = TeamMember(
            uid: "user-2",
            displayName: "Old Name",
            email: "old@example.com",
            role: "viewer",
            status: "pending",
            inviteId: nil
        )
        context.insert(existing)
        XCTAssertTrue(context.safeSave(context: "test-seed"))

        let (manager, _) = makeManager(outcome: .success)
        let result = await manager.acceptInvite(
            sampleInvite(role: "manager"),
            authenticatedUID: "user-2",
            displayName: "Me",
            email: "me@example.com",
            modelContext: context
        )

        guard case .success = result else {
            XCTFail("expected success, got \(result)")
            return
        }

        let members = try context.fetch(FetchDescriptor<TeamMember>())
        XCTAssertEqual(members.count, 1)
        XCTAssertEqual(members.first?.displayName, "Me")
        XCTAssertEqual(members.first?.email, "me@example.com")
        XCTAssertEqual(members.first?.role, "manager")
        XCTAssertEqual(members.first?.status, "active")
        XCTAssertEqual(members.first?.inviteId, "inv-1")
        _ = container
    }

    // MARK: - Legacy decoding

    @MainActor
    func testMemberRecordDecodesWhenInviteIdIsMissing() {
        let record = TeamManager.MemberRecord.fromFirestore([
            "uid": "u1",
            "displayName": "Ada",
            "email": "ada@example.com",
            "role": "viewer",
            "status": "active"
        ])

        XCTAssertEqual(record?.uid, "u1")
        XCTAssertEqual(record?.displayName, "Ada")
        XCTAssertEqual(record?.email, "ada@example.com")
        XCTAssertEqual(record?.role, "viewer")
        XCTAssertEqual(record?.status, "active")
        XCTAssertNil(record?.inviteId)
    }

    @MainActor
    func testMemberRecordDecodesInviteIdWhenPresent() {
        let record = TeamManager.MemberRecord.fromFirestore([
            "uid": "u1",
            "displayName": "Ada",
            "email": "ada@example.com",
            "role": "manager",
            "status": "active",
            "inviteId": "inv-42"
        ])

        XCTAssertEqual(record?.inviteId, "inv-42")
    }

    @MainActor
    func testMemberRecordDefaultsStatusWhenMissing() {
        let record = TeamManager.MemberRecord.fromFirestore([
            "uid": "u1",
            "displayName": "Ada",
            "email": "ada@example.com",
            "role": "viewer"
        ])

        XCTAssertEqual(record?.status, "active")
        XCTAssertNil(record?.inviteId)
    }
}
