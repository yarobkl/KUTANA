import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct BackendConfiguration: Sendable {
    // Isolation invariant: the production client must NEVER point to another Yaro app.
    static let projectHost = "xwhjzftrzikgqweowtus.supabase.co"

    static func fromBundle(_ bundle: Bundle = .main) -> BackendConfiguration? {
        guard let url = bundle.object(forInfoDictionaryKey: "KUTANA_SUPABASE_URL") as? String,
              let key = bundle.object(forInfoDictionaryKey: "KUTANA_SUPABASE_PUBLISHABLE_KEY") as? String else { return nil }
        return BackendConfiguration(endpoint: url, publishableKey: key)
    }
    let endpoint: URL
    let publishableKey: String
    init?(endpoint: String, publishableKey: String) {
        guard let url = URL(string: endpoint), url.scheme == "https",
              url.host == Self.projectHost,
              url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil,
              (url.path.isEmpty || url.path == "/"),
              !publishableKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        self.endpoint = url
        self.publishableKey = publishableKey
    }
}

enum BackendError: Error {
    case notConfigured, notAuthenticated, invalidResponse, server(Int)
}

/// Transport only: never embed service_role keys or long-lived admin tokens in the app.
actor KutanaAPI {
    private let configuration: BackendConfiguration
    private let session: URLSession
    private let decoder: JSONDecoder

    init(configuration: BackendConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
        let decoder = JSONDecoder()
        // Supabase/PostgREST timestamps often include fractional seconds (e.g. .123456+00:00).
        // Foundation's plain .iso8601 decoder rejects some of those values.
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let parsed = fractional.date(from: value) { return parsed }
            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            if let parsed = standard.date(from: value) { return parsed }
            throw DecodingError.dataCorruptedError(in: container,
                debugDescription: "Invalid backend timestamp: \(value)")
        }
        self.decoder = decoder
    }

    func publishedJobs(limit: Int = 30) async throws -> [JobRecord] {
        try await get("jobs", query: [
            URLQueryItem(name: "select", value: "id,author_id,title,company,city,contract_type,description,status,created_at"),
            URLQueryItem(name: "status", value: "eq.published"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 50)))
        ])
    }

    func publishedListings(limit: Int = 30) async throws -> [ListingRecord] {
        try await get("listings", query: [
            URLQueryItem(name: "select", value: "id,seller_id,category,title,description,city,price_xaf,status,created_at"),
            URLQueryItem(name: "status", value: "eq.published"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 50)))
        ])
    }

    func myApplications(accessToken: String) async throws -> [ApplicationWithJob] {
        try await get("applications", query: [
            URLQueryItem(name: "select", value: "id,job_id,status,created_at,jobs(title,company)"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: "50")
        ], accessToken: accessToken)
    }

    func myConversations(accessToken: String) async throws -> [ConversationRecord] {
        try await get("conversations", query: [
            URLQueryItem(name: "select", value: "id,participant_a,participant_b,created_at"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: "100")
        ], accessToken: accessToken)
    }

    func conversationMessages(conversationID: UUID, accessToken: String) async throws -> [MessageRecord] {
        try await get("messages", query: [
            URLQueryItem(name: "select", value: "id,conversation_id,sender_id,body,created_at"),
            URLQueryItem(name: "conversation_id", value: "eq.\(conversationID.uuidString.lowercased())"),
            URLQueryItem(name: "order", value: "created_at.asc"),
            URLQueryItem(name: "limit", value: "100")
        ], accessToken: accessToken)
    }

    func startApplicationConversation(applicationID: UUID, accessToken: String) async throws -> UUID {
        try await rpc(name: "start_application_conversation",
                      body: ["p_application": applicationID.uuidString.lowercased()],
                      accessToken: accessToken)
    }

    func sendMessage(conversationID: UUID, text: String, accessToken: String) async throws -> UUID {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count <= 4_000 else { throw BackendError.invalidResponse }
        return try await rpc(name: "send_conversation_message", body: [
            "p_conversation": conversationID.uuidString.lowercased(),
            "p_body": cleaned
        ], accessToken: accessToken)
    }

    func applyToJob(jobID: UUID, accessToken: String) async throws -> UUID {
        let url = configuration.endpoint.appending(path: "rest/v1/rpc/apply_to_job")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["p_job": jobID.uuidString.lowercased()])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BackendError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw BackendError.server(http.statusCode) }
        return try decoder.decode(UUID.self, from: data)
    }

    /// Creates a private, unpublished draft. The server sets the authenticated owner.
    func createJobDraft(_ input: JobDraftInput, accessToken: String) async throws -> UUID {
        try await rpc(name: "create_job_draft", body: input, accessToken: accessToken)
    }

    func createListingDraft(_ input: ListingDraftInput, accessToken: String) async throws -> UUID {
        try await rpc(name: "create_listing_draft", body: input, accessToken: accessToken)
    }

    private func rpc<T: Encodable>(name: String, body: T, accessToken: String) async throws -> UUID {
        guard !accessToken.isEmpty else { throw BackendError.notAuthenticated }
        let url = configuration.endpoint.appending(path: "rest/v1/rpc/\(name)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BackendError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw BackendError.server(http.statusCode) }
        return try decoder.decode(UUID.self, from: data)
    }

    private func get<T: Decodable>(_ table: String, query: [URLQueryItem], accessToken: String? = nil) async throws -> T {
        var components = URLComponents(url: configuration.endpoint.appending(path: "rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        guard let url = components.url else { throw BackendError.invalidResponse }
        var request = URLRequest(url: url)
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        if let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw BackendError.invalidResponse }
        guard (200...299).contains(response.statusCode) else { throw BackendError.server(response.statusCode) }
        return try decoder.decode(T.self, from: data)
    }
}
