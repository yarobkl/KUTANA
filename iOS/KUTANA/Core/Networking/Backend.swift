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

extension BackendConfiguration {
    func publicListingImageURL(path: String) -> URL? {
        let pieces = path.split(separator: "/", omittingEmptySubsequences: false)
        guard pieces.count == 3,
              UUID(uuidString: String(pieces[0])) != nil,
              UUID(uuidString: String(pieces[1])) != nil,
              pieces[2].hasSuffix(".jpg"),
              UUID(uuidString: String(pieces[2].dropLast(4))) != nil else { return nil }
        return endpoint.appending(path: "storage/v1/object/public/kutana-listing-images/\(path)")
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
            URLQueryItem(name: "select", value: "id,seller_id,category,title,description,city,price_xaf,status,created_at,listing_images(storage_path)"),
            URLQueryItem(name: "status", value: "eq.published"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 50)))
        ])
    }


    /// RLS also enforces ownership; the explicit predicate keeps the account list scoped.
    func myJobs(ownerID: UUID, accessToken: String) async throws -> [JobRecord] {
        try await get("jobs", query: [
            URLQueryItem(name: "select", value: "id,author_id,title,company,city,contract_type,description,status,created_at"),
            URLQueryItem(name: "author_id", value: "eq.\(ownerID.uuidString.lowercased())"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: "100")
        ], accessToken: accessToken)
    }

    func myListings(ownerID: UUID, accessToken: String) async throws -> [ListingRecord] {
        try await get("listings", query: [
            URLQueryItem(name: "select", value: "id,seller_id,category,title,description,city,price_xaf,status,created_at"),
            URLQueryItem(name: "seller_id", value: "eq.\(ownerID.uuidString.lowercased())"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: "100")
        ], accessToken: accessToken)
    }


    /// Only applications attached to the signed-in recruiter's jobs are visible through RLS.
    func receivedApplications(accessToken: String) async throws -> [RecruiterApplication] {
        try await get("rpc/received_applications", query: [], accessToken: accessToken)
    }

    /// The recruiter-only SQL RPC validates ownership and records an audit event.
    func changeApplicationStatus(id: UUID, next: ApplicationState, accessToken: String) async throws {
        guard !accessToken.isEmpty, next != .submitted else { throw BackendError.invalidResponse }
        let url = configuration.endpoint.appending(path: "rest/v1/rpc/change_application_status")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "p_application": id.uuidString.lowercased(), "p_next": next.rawValue
        ])
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BackendError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw BackendError.server(http.statusCode) }
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


    /// Author-only transitions; publishing requires a server-verified email.
    func publishJob(id: UUID, accessToken: String) async throws -> UUID {
        try await rpc(name: "publish_job", body: ["p_job": id.uuidString.lowercased()], accessToken: accessToken)
    }

    func publishListing(id: UUID, accessToken: String) async throws -> UUID {
        try await rpc(name: "publish_listing", body: ["p_listing": id.uuidString.lowercased()], accessToken: accessToken)
    }

    func withdrawPublication(kind: String, id: UUID, accessToken: String) async throws -> UUID {
        guard kind == "job" || kind == "listing" else { throw BackendError.invalidResponse }
        return try await rpc(name: "withdraw_publication", body: [
            "p_kind": kind, "p_id": id.uuidString.lowercased()
        ], accessToken: accessToken)
    }

    func startListingConversation(listingID: UUID, accessToken: String) async throws -> UUID {
        try await rpc(name: "start_listing_conversation",
                      body: ["p_listing": listingID.uuidString.lowercased()], accessToken: accessToken)
    }

    func reportContent(kind: String, id: UUID, reason: String, accessToken: String) async throws -> UUID {
        let cleaned = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ["job","listing"].contains(kind), (10...2000).contains(cleaned.count) else {
            throw BackendError.invalidResponse
        }
        return try await rpc(name: "report_content", body: [
            "p_kind": kind, "p_id": id.uuidString.lowercased(), "p_reason": cleaned
        ], accessToken: accessToken)
    }


    func listingImages(listingID: UUID, accessToken: String? = nil) async throws -> [ListingImageRecord] {
        try await get("listing_images", query: [
            URLQueryItem(name: "select", value: "id,listing_id,storage_path,sort_order"),
            URLQueryItem(name: "listing_id", value: "eq.\(listingID.uuidString.lowercased())"),
            URLQueryItem(name: "order", value: "sort_order.asc"),
            URLQueryItem(name: "limit", value: "5")
        ], accessToken: accessToken)
    }

    /// Metadata is added only after successful upload; the server checks owner,
    /// unpublished status, actual storage object and per-listing photo quota.
    func uploadListingImage(_ jpeg: Data, listingID: UUID, ownerID: UUID,
                            accessToken: String) async throws -> UUID {
        guard (1...5_242_880).contains(jpeg.count), !accessToken.isEmpty else {
            throw BackendError.invalidResponse
        }
        let path = "\(ownerID.uuidString.lowercased())/\(listingID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
        let url = configuration.endpoint.appending(path: "storage/v1/object/kutana-listing-images/\(path)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 35
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("false", forHTTPHeaderField: "x-upsert")
        request.httpBody = jpeg
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BackendError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw BackendError.server(http.statusCode) }
        return try await rpc(name: "attach_listing_image", body: [
            "p_listing": listingID.uuidString.lowercased(), "p_path": path
        ], accessToken: accessToken)
    }


    func applicationCV(applicationID: UUID, accessToken: String) async throws -> ApplicationCVRecord? {
        let results: [ApplicationCVRecord] = try await get("application_cvs", query: [
            URLQueryItem(name: "select", value: "application_id,storage_path,file_name"),
            URLQueryItem(name: "application_id", value: "eq.\(applicationID.uuidString.lowercased())"),
            URLQueryItem(name: "limit", value: "1")
        ], accessToken: accessToken)
        return results.first
    }

    /// Upload a PDF into the candidate's private bucket folder, then attach it
    /// to their own application through a server-authorized RPC.
    func uploadApplicationCV(_ pdf: Data, filename: String, applicationID: UUID,
                             ownerID: UUID, accessToken: String) async throws -> UUID {
        guard (5...5_242_880).contains(pdf.count),
              pdf.starts(with: Data("%PDF-".utf8)), !accessToken.isEmpty else {
            throw BackendError.invalidResponse
        }
        let cleanName = String(filename.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ").prefix(160))
        guard !cleanName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BackendError.invalidResponse
        }
        let path = "\(ownerID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).pdf"
        let url = configuration.endpoint.appending(path: "storage/v1/object/kutana-cvs/\(path)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 40
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/pdf", forHTTPHeaderField: "Content-Type")
        request.setValue("false", forHTTPHeaderField: "x-upsert")
        request.httpBody = pdf
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BackendError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw BackendError.server(http.statusCode) }
        return try await rpc(name: "attach_application_cv", body: [
            "p_application": applicationID.uuidString.lowercased(),
            "p_path": path,
            "p_file_name": cleanName
        ], accessToken: accessToken)
    }

    /// RLS allows reading only by the candidate or the recruiting job owner.
    /// An authenticated PDF is copied to a temporary local file for Quick Look.
    func downloadApplicationCV(_ cv: ApplicationCVRecord, accessToken: String) async throws -> URL {
        guard !accessToken.isEmpty else { throw BackendError.notAuthenticated }
        let pieces = cv.storage_path.split(separator: "/", omittingEmptySubsequences: false)
        guard pieces.count == 2, UUID(uuidString: String(pieces[0])) != nil,
              pieces[1].hasSuffix(".pdf"),
              UUID(uuidString: String(pieces[1].dropLast(4))) != nil else {
            throw BackendError.invalidResponse
        }
        let url = configuration.endpoint.appending(path: "storage/v1/object/authenticated/kutana-cvs/\(cv.storage_path)")
        var request = URLRequest(url: url)
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BackendError.invalidResponse }
        guard (200...299).contains(http.statusCode),
              (5...5_242_880).contains(data.count),
              data.starts(with: Data("%PDF-".utf8)) else { throw BackendError.invalidResponse }
        let local = FileManager.default.temporaryDirectory
            .appendingPathComponent("KUTANA-CV-\(UUID().uuidString)")
            .appendingPathExtension("pdf")
        try data.write(to: local, options: .atomic)
        return local
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
