import Foundation

// DTOs intentionally independent of SwiftUI and backend SDK.
enum ApplicationState: String, Codable, CaseIterable, Sendable {
    case submitted, viewed, shortlisted, interview, rejected, hired
    var frenchLabel: String {
        switch self {
        case .submitted: "Envoyée"
        case .viewed: "CV consulté"
        case .shortlisted: "Présélectionnée"
        case .interview: "Entretien proposé"
        case .rejected: "Non retenue"
        case .hired: "Recruté"
        }
    }
}

struct JobRecord: Identifiable, Codable, Sendable {
    let id: UUID
    let author_id: UUID
    let title: String
    let company: String
    let city: String
    let contract_type: String
    let description: String
    let status: String
    let created_at: Date
}

struct ListingRecord: Identifiable, Codable, Sendable {
    let id: UUID
    let seller_id: UUID
    let category: String
    let title: String
    let description: String
    let city: String
    let price_xaf: Int64
    let status: String
    let created_at: Date
}

struct ApplicationRecord: Identifiable, Codable, Sendable {
    let id: UUID
    let job_id: UUID
    let candidate_id: UUID
    let status: ApplicationState
    let created_at: Date
}

struct ConversationRecord: Identifiable, Codable, Sendable {
    let id: UUID
    let participant_a: UUID
    let participant_b: UUID
    let created_at: Date
}

struct MessageRecord: Identifiable, Codable, Sendable {
    let id: UUID
    let conversation_id: UUID
    let sender_id: UUID
    let body: String
    let created_at: Date
}

struct ApplicationJobInfo: Codable, Sendable {
    let title: String
    let company: String
}


/// Recruiter-facing application; candidate contact details are not exposed.
struct RecruiterApplication: Identifiable, Codable, Sendable {
    let id: UUID
    let job_id: UUID
    let candidate_id: UUID
    let status: ApplicationState
    let created_at: Date
    let jobs: ApplicationJobInfo?
}

struct ApplicationWithJob: Identifiable, Codable, Sendable {
    let id: UUID
    let job_id: UUID
    let status: ApplicationState
    let created_at: Date
    let jobs: ApplicationJobInfo?
}

enum KutanaFormat {
    static func xaf(_ amount: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.locale = Locale(identifier: "fr_FR")
        return "\(formatter.string(from: NSNumber(value: amount)) ?? String(amount)) FCFA"
    }
}
