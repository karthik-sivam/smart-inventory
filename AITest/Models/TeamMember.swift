import Foundation
import SwiftData

@Model
final class TeamMember {
    var id: UUID
    var uid: String
    var displayName: String
    var email: String
    var role: String
    var status: String
    var joinedAt: Date

    init(uid: String, displayName: String, email: String,
         role: String, status: String = "pending") {
        self.id = UUID()
        self.uid = uid
        self.displayName = displayName
        self.email = email
        self.role = role
        self.status = status
        self.joinedAt = Date()
    }

    var roleLabel: String {
        switch role {
        case "owner":   return "Owner"
        case "manager": return "Manager"
        case "viewer":  return "Viewer"
        default:        return role.capitalized
        }
    }

    var roleIcon: String {
        switch role {
        case "owner":   return "crown.fill"
        case "manager": return "person.badge.key.fill"
        case "viewer":  return "eye.fill"
        default:        return "person.fill"
        }
    }
}
