import SwiftUI

struct TeamMembersView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var teamManager = TeamManager.shared
    @State private var members: [TeamManager.MemberRecord] = []
    @State private var showingInviteSheet = false
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            List {
                Section("Your Workspace") {
                    HStack {
                        Image(systemName: "crown.fill")
                            .foregroundColor(.yellow)
                        VStack(alignment: .leading) {
                            Text(AuthManager.shared.actorName)
                                .fontWeight(.semibold)
                            Text("Owner").font(.caption).foregroundColor(.secondary)
                        }
                    }
                }

                Section("Team Members (\(members.filter { $0.status == "active" }.count))") {
                    if isLoading {
                        ProgressView()
                    } else if members.isEmpty {
                        Text("No team members yet.")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(members) { member in
                            HStack {
                                Image(systemName: roleIcon(member.role))
                                    .foregroundColor(roleColor(member.role))
                                VStack(alignment: .leading) {
                                    Text(member.displayName).fontWeight(.medium)
                                    Text(member.email).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(member.role.capitalized)
                                    .font(.caption)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(roleColor(member.role).opacity(0.15))
                                    .foregroundColor(roleColor(member.role))
                                    .cornerRadius(8)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task {
                                        await teamManager.removeMember(uid: member.uid)
                                        await loadMembers()
                                    }
                                } label: {
                                    Label("Remove", systemImage: "person.badge.minus")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingInviteSheet = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                    }
                    .accessibilityLabel("Invite Member")
                }
            }
            .sheet(isPresented: $showingInviteSheet) {
                InviteMemberSheet(onInviteSent: { await loadMembers() })
            }
            .task { await loadMembers() }
        }
    }

    private func loadMembers() async {
        isLoading = true
        members = await teamManager.fetchMembers()
        isLoading = false
    }

    private func roleIcon(_ role: String) -> String {
        switch role {
        case "manager": return "person.badge.key.fill"
        case "viewer":  return "eye.fill"
        default:        return "person.fill"
        }
    }

    private func roleColor(_ role: String) -> Color {
        switch role {
        case "manager": return .blue
        case "viewer":  return .secondary
        default:        return .primary
        }
    }
}

struct InviteMemberSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var selectedRole = "manager"
    @State private var isSending = false
    @State private var resultMessage: String? = nil
    let onInviteSent: () async -> Void

    private let roles = ["manager", "viewer"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Invite by Email") {
                    TextField("Email address", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Role") {
                    Picker("Role", selection: $selectedRole) {
                        Text("Manager — can add, edit, count").tag("manager")
                        Text("Viewer — read-only").tag("viewer")
                    }
                    .pickerStyle(.inline)
                }

                if let msg = resultMessage {
                    Section {
                        Text(msg)
                            .foregroundColor(msg.contains("sent") ? .green : .red)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle("Invite Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Send Invite") {
                        Task {
                            isSending = true
                            let result = await TeamManager.shared.sendInvite(
                                to: email, role: selectedRole)
                            isSending = false
                            switch result {
                            case .success:
                                resultMessage = "Invite sent to \(email)."
                                await onInviteSent()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { dismiss() }
                            case .failure(let error):
                                resultMessage = "Failed: \(error.localizedDescription)"
                            }
                        }
                    }
                    .disabled(email.isEmpty || isSending)
                }
            }
        }
    }
}
