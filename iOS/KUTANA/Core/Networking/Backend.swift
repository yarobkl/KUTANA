import Foundation

private struct ListingEditRequest: Encodable {
    let p_listing: UUID
    let p_category: String
    let p_title: String
    let p_description: String
    let p_city: String
    let p_price_xaf: Int64
}
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

    func basicProfile(accessToken: String) async throws -> LukaBasicProfile? {
        let rows: [LukaBasicProfile] = try await get("profiles", query: [
            URLQueryItem(name: "select", value: "display_name"),
            URLQueryItem(name: "limit", value: "1")
        ], accessToken: accessToken)
        return rows.first
    }

    func privateProfile(accessToken: String) async throws -> LukaPrivateProfile? {
        let rows: [LukaPrivateProfile] = try await get("luka_private_profiles", query: [
            URLQueryItem(name: "select", value: "user_id,first_name,last_name,birth_date,phone_e164,phone_region,country_code,city,commune,share_location_with_recruiters"),
            URLQueryItem(name: "limit", value: "1")
        ], accessToken: accessToken)
        return rows.first
    }

    func savePrivateProfile(_ profile: LukaPrivateProfile, accessToken: String) async throws {
        try await write("luka_private_profiles", method: "POST",
                        query: [URLQueryItem(name: "on_conflict", value: "user_id")],
                        body: [
                            "user_id": profile.user_id.uuidString.lowercased(),
                            "first_name": profile.first_name, "last_name": profile.last_name,
                            "birth_date": profile.birth_date, "phone_e164": profile.phone_e164,
                            "phone_region": profile.phone_region, "country_code": profile.country_code,
                            "city": profile.city, "commune": profile.commune,
                            "share_location_with_recruiters": profile.share_location_with_recruiters
                        ], accessToken: accessToken, prefer: "resolution=merge-duplicates,return=minimal")
    }

    struct SharedApplicationLocation: Decodable {
        let country_code: String
        let city: String
        let commune: String
    }

    func sharedApplicationLocation(applicationID: UUID, accessToken: String) async throws -> SharedApplicationLocation? {
        guard !accessToken.isEmpty else { throw BackendError.notAuthenticated }
        let url = configuration.endpoint.appending(path: "rest/v1/rpc/luka_application_location")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["p_application": applicationID.uuidString.lowercased()])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BackendError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw BackendError.server(http.statusCode) }
        return try decoder.decode([SharedApplicationLocation].self, from: data).first
    }

    func publicComments(kind: String, contentID: UUID) async throws -> [LukaComment] {
        try await get("luka_comments", query: [
            URLQueryItem(name: "select", value: "id,kind,content_id,parent_id,author_id,author_name,body,created_at,deleted_at"),
            URLQueryItem(name: "kind", value: "eq.\(kind)"),
            URLQueryItem(name: "content_id", value: "eq.\(contentID.uuidString.lowercased())"),
            URLQueryItem(name: "order", value: "created_at.asc"),
            URLQueryItem(name: "limit", value: "100")
        ])
    }

    func commentsEnabled(kind: String, contentID: UUID) async throws -> Bool {
        let rows: [LukaCommentSetting] = try await get("luka_comment_settings", query: [
            URLQueryItem(name: "select", value: "enabled"),
            URLQueryItem(name: "kind", value: "eq.\(kind)"),
            URLQueryItem(name: "content_id", value: "eq.\(contentID.uuidString.lowercased())"),
            URLQueryItem(name: "limit", value: "1")
        ])
        return rows.first?.enabled ?? true
    }

    func addComment(kind: String, contentID: UUID, parentID: UUID?, body: String, accessToken: String) async throws {
        let parent: Any = parentID.map { $0.uuidString.lowercased() as Any } ?? NSNull()
        try await write("rpc/luka_add_comment", method: "POST", body: [
            "p_kind": kind, "p_content": contentID.uuidString.lowercased(), "p_parent": parent, "p_body": body
        ], accessToken: accessToken)
    }

    func deleteComment(id: UUID, accessToken: String) async throws {
        try await write("rpc/luka_delete_own_comment", method: "POST",
                        body: ["p_comment": id.uuidString.lowercased()], accessToken: accessToken)
    }

    func reportComment(id: UUID, reason: String, accessToken: String) async throws {
        try await write("rpc/luka_report_comment", method: "POST",
                        body: ["p_comment": id.uuidString.lowercased(), "p_reason": reason], accessToken: accessToken)
    }

    func setCommentsEnabled(kind: String, contentID: UUID, enabled: Bool, accessToken: String) async throws {
        try await write("rpc/luka_set_comments_enabled", method: "POST", body: [
            "p_kind": kind, "p_content": contentID.uuidString.lowercased(), "p_enabled": enabled
        ], accessToken: accessToken)
    }

    func publicJob(id: UUID) async throws -> JobRecord? {
        let rows: [JobRecord] = try await get("jobs", query: [
            URLQueryItem(name: "select", value: "id,author_id,title,company,city,contract_type,description,status,created_at"),
            URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())"),
            URLQueryItem(name: "status", value: "eq.published"), URLQueryItem(name: "limit", value: "1")
        ])
        return rows.first
    }

    func publicListing(id: UUID) async throws -> ListingRecord? {
        let rows: [ListingRecord] = try await get("listings", query: [
            URLQueryItem(name: "select", value: "id,seller_id,category,title,description,city,price_xaf,status,created_at,expires_at,listing_images(storage_path)"),
            URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())"),
            URLQueryItem(name: "status", value: "in.(published,sold)"), URLQueryItem(name: "limit", value: "1")
        ])
        return rows.first
    }

    func publishedJobs(limit: Int = 30) async throws -> [JobRecord] {
        try await get("jobs", query: [
            URLQueryItem(name: "select", value: "id,author_id,title,company,city,contract_type,description,status,created_at"),
            URLQueryItem(name: "status", value: "eq.published"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 50)))
        ])
    }

    func notifications(accessToken: String) async throws -> [KutanaNotification] {
        try await get("notifications", query: [
            URLQueryItem(name: "select", value: "id,kind,title,body,reference_id,created_at,read_at"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: "100")
        ], accessToken: accessToken)
    }

    func submitProblem(details: String, appVersion: String, accessToken: String) async throws -> UUID {
        try await rpc(name: "submit_problem_report", body: [
            "p_details": details,
            "p_app_version": appVersion
        ], accessToken: accessToken)
    }

    func listingFavorites(accessToken: String) async throws -> [ListingFavorite] {
        try await get("luka_listing_favorites", query: [URLQueryItem(name: "select", value: "listing_id")], accessToken: accessToken)
    }

    func addListingFavorite(listingID: UUID, userID: UUID, accessToken: String) async throws {
        try await write("luka_listing_favorites", method: "POST",
                        query: [URLQueryItem(name: "on_conflict", value: "user_id,listing_id")],
                        body: ["listing_id": listingID.uuidString.lowercased(), "user_id": userID.uuidString.lowercased()],
                        accessToken: accessToken, prefer: "resolution=ignore-duplicates,return=minimal")
    }

    func removeListingFavorite(listingID: UUID, accessToken: String) async throws {
        try await write("luka_listing_favorites", method: "DELETE",
                        query: [URLQueryItem(name: "listing_id", value: "eq.\(listingID.uuidString.lowercased())")], accessToken: accessToken)
    }

    func favorites(accessToken: String) async throws -> [JobFavorite] {
        try await get("job_favorites", query: [URLQueryItem(name: "select", value: "job_id")], accessToken: accessToken)
    }

    func alerts(accessToken: String) async throws -> [JobAlert] {
        try await get("job_alerts", query: [URLQueryItem(name: "select", value: "id,keyword,city"), URLQueryItem(name: "order", value: "created_at.desc")], accessToken: accessToken)
    }

    func preferences(accessToken: String) async throws -> NotificationPreference {
        let rows: [NotificationPreference] = try await get("notification_preferences", query: [
            URLQueryItem(name: "select", value: "messages_enabled,jobs_enabled"),
            URLQueryItem(name: "limit", value: "1")
        ], accessToken: accessToken)
        return rows.first ?? NotificationPreference(messages_enabled: true, jobs_enabled: true)
    }

    func savePreference(messages: Bool, jobs: Bool, userID: UUID, accessToken: String) async throws {
        try await write("notification_preferences", method: "POST", query: [URLQueryItem(name: "on_conflict", value: "user_id")],
                        body: ["user_id": userID.uuidString.lowercased(), "messages_enabled": messages, "jobs_enabled": jobs],
                        accessToken: accessToken, prefer: "resolution=merge-duplicates,return=minimal")
    }

    func addFavorite(jobID: UUID, userID: UUID, accessToken: String) async throws {
        try await write("job_favorites", method: "POST", body: ["job_id": jobID.uuidString.lowercased(), "user_id": userID.uuidString.lowercased()], accessToken: accessToken)
    }

    func removeFavorite(jobID: UUID, accessToken: String) async throws {
        try await write("job_favorites", method: "DELETE", query: [URLQueryItem(name: "job_id", value: "eq.\(jobID.uuidString.lowercased())")], accessToken: accessToken)
    }

    func addAlert(keyword: String, city: String, userID: UUID, accessToken: String) async throws {
        try await write("job_alerts", method: "POST", query: [URLQueryItem(name: "on_conflict", value: "user_id,keyword,city")], body: ["keyword": keyword, "city": city, "user_id": userID.uuidString.lowercased()], accessToken: accessToken, prefer: "resolution=ignore-duplicates,return=minimal")
    }

    func removeAlert(id: UUID, accessToken: String) async throws {
        try await write("job_alerts", method: "DELETE", query: [URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())")], accessToken: accessToken)
    }

    func markNotificationRead(id: UUID, accessToken: String) async throws {
        try await write("notifications", method: "PATCH", query: [URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())")],
                        body: ["read_at": ISO8601DateFormatter().string(from: Date())], accessToken: accessToken)
    }

    private func write(_ table: String, method: String, query: [URLQueryItem] = [],
                                     body: [String: Any]? = nil, accessToken: String,
                                     prefer: String = "return=minimal") async throws {
        guard !accessToken.isEmpty else { throw BackendError.notAuthenticated }
        var components = URLComponents(url: configuration.endpoint.appending(path: "rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw BackendError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(prefer, forHTTPHeaderField: "Prefer")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw BackendError.invalidResponse
        }
    }

    func publicListings(ids: [UUID]) async throws -> [ListingRecord] {
        guard !ids.isEmpty else { return [] }
        var result: [ListingRecord] = []
        for start in stride(from: 0, to: ids.count, by: 50) {
            let batch = ids[start..<min(start + 50, ids.count)].map { $0.uuidString.lowercased() }.joined(separator: ",")
            let rows: [ListingRecord] = try await get("listings", query: [
                URLQueryItem(name: "select", value: "id,seller_id,category,title,description,city,price_xaf,status,created_at,expires_at,listing_images(storage_path)"),
                URLQueryItem(name: "id", value: "in.(\(batch))"),
                URLQueryItem(name: "status", value: "in.(published,sold)"),
                URLQueryItem(name: "limit", value: "50")
            ])
            result.append(contentsOf: rows)
        }
        return result.sorted { $0.created_at > $1.created_at }
    }

    func publishedListings(limit: Int = 30) async throws -> [ListingRecord] {
        try await get("listings", query: [
            URLQueryItem(name: "select", value: "id,seller_id,category,title,description,city,price_xaf,status,created_at,expires_at,listing_images(storage_path)"),
            URLQueryItem(name: "status", value: "in.(published,sold)"),
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
            URLQueryItem(name: "select", value: "id,seller_id,category,title,description,city,price_xaf,status,created_at,expires_at"),
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

    func editListing(id: UUID, input: ListingDraftInput, accessToken: String) async throws -> UUID {
        let request = ListingEditRequest(p_listing: id, p_category: input.p_category,
            p_title: input.p_title, p_description: input.p_description,
            p_city: input.p_city, p_price_xaf: input.p_price_xaf)
        return try await rpc(name: "edit_listing", body: request, accessToken: accessToken)
    }

    func changeListingStatus(id: UUID, status: String, accessToken: String) async throws -> UUID {
        guard ["archived", "published", "sold"].contains(status) else { throw BackendError.invalidResponse }
        return try await rpc(name: "change_listing_status", body: [
            "p_listing": id.uuidString.lowercased(), "p_status": status
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
    /// listing status, actual storage object and per-listing photo quota.
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

    func replaceListingImage(_ jpeg: Data, path: String, ownerID: UUID,
                             accessToken: String) async throws {
        guard (1...5_242_880).contains(jpeg.count), !accessToken.isEmpty,
              path.hasPrefix(ownerID.uuidString.lowercased() + "/") else {
            throw BackendError.invalidResponse
        }
        let url = configuration.endpoint.appending(path: "storage/v1/object/kutana-listing-images/\(path)")
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.timeoutInterval = 35
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("0", forHTTPHeaderField: "cacheControl")
        request.httpBody = jpeg
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw BackendError.invalidResponse
        }
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
