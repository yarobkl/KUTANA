import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class StubProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler else { fatalError("Missing stub") }
        let (status, body) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: "HTTP/1.1", headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct NetworkSmoke {
    static func main() async throws {
        let config = BackendConfiguration(endpoint: "https://xwhjzftrzikgqweowtus.supabase.co", publishableKey: "unit-test-public-key")!
        assert(BackendConfiguration(endpoint: "http://xwhjzftrzikgqweowtus.supabase.co", publishableKey: "key") == nil)
        assert(BackendConfiguration(endpoint: "https://other.org", publishableKey: "key") == nil)
        assert(BackendConfiguration(endpoint: "https://bmbwmwgfzrijglzcgjut.supabase.co", publishableKey: "key") == nil)
        assert(BackendConfiguration(endpoint: "https://xwhjzftrzikgqweowtus.supabase.co.evil.example", publishableKey: "key") == nil)
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)
        defer { session.invalidateAndCancel() }
        StubProtocol.handler = { request in
            guard request.url?.path == "/auth/v1/token" else { return (404, Data("{}".utf8)) }
            assert(request.url?.query == "grant_type=password")
            assert(request.value(forHTTPHeaderField: "apikey") == "unit-test-public-key")
            return (200, Data(#"{"access_token":"token","refresh_token":"refresh","expires_in":3600,"token_type":"bearer"}"#.utf8))
        }
        let auth = KutanaAuthService(config: config, session: session)
        let token = try await auth.signIn(email: "  TEST@EXAMPLE.COM  ", password: "password")
        assert(token.access_token == "token")
        let stored = PersistedSession(token: token, expiration: Date().addingTimeInterval(3600))
        let storedAgain = try JSONDecoder().decode(PersistedSession.self, from: JSONEncoder().encode(stored))
        assert(!storedAgain.requiresRefresh)

        StubProtocol.handler = { request in
            assert(request.url!.path == "/auth/v1/signup")
            return (200, Data("{}".utf8))
        }
        try await auth.signUp(email: "valid@example.com", password: "secure-password-123", fullName: "Marie Test")
        do {
            try await auth.signUp(email: "invalid", password: "secure-password-123", fullName: "Test")
            assertionFailure("Invalid email was accepted")
        } catch AuthFailure.invalidEmail { /* expected */ }
        assert(refreshFailureInvalidatesSession(AuthFailure.invalidCredentials))
        assert(!refreshFailureInvalidatesSession(AuthFailure.badResponse(503)))
        assert(!refreshFailureInvalidatesSession(URLError(.notConnectedToInternet)))
        let commentID = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
        let commentAPI = KutanaAPI(configuration: config, session: session)
        StubProtocol.handler = { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/luka_comments") {
                assert(request.value(forHTTPHeaderField: "Authorization") == nil)
                return (200, Data("[]".utf8))
            }
            if path.hasSuffix("/luka_comment_settings") {
                return (200, Data(#"[{"enabled":false}]"#.utf8))
            }
            if path.hasSuffix("/rpc/luka_add_comment") {
                assert(request.httpMethod == "POST")
                assert(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
                return (200, Data("{}".utf8))
            }
            return (404, Data("{}".utf8))
        }
        let comments = try await commentAPI.publicComments(kind: "job", contentID: commentID)
        assert(comments.isEmpty)
        let enabled = try await commentAPI.commentsEnabled(kind: "job", contentID: commentID)
        assert(!enabled)
        try await commentAPI.addComment(kind: "job", contentID: commentID, parentID: nil,
                                        body: "Bonjour", accessToken: "test-token")
        let profileAPI = KutanaAPI(configuration: config, session: session)
        StubProtocol.handler = { request in
            assert(request.url?.path == "/rest/v1/luka_private_profiles")
            assert(request.value(forHTTPHeaderField: "Authorization") == "Bearer profile-token")
            return (200, Data(request.httpMethod == "GET" ? "[]".utf8 : "{}".utf8))
        }
        let missingProfile = try await profileAPI.privateProfile(accessToken: "profile-token")
        assert(missingProfile == nil)
        let profile = LukaPrivateProfile(user_id: commentID, first_name: "Marie", last_name: "Test",
            birth_date: "1990-01-01", phone_e164: "+242061234567", phone_region: "CG",
            country_code: "CG", city: "Brazzaville", commune: "Bacongo", share_location_with_recruiters: false)
        try await profileAPI.savePrivateProfile(profile, accessToken: "profile-token")
        StubProtocol.handler = { request in
            assert(request.url?.path == "/rest/v1/profiles")
            assert(request.value(forHTTPHeaderField: "Authorization") == "Bearer profile-token")
            return (200, Data(#"[{"display_name":"Marie Test"}]"#.utf8))
        }
        let basicProfile = try await profileAPI.basicProfile(accessToken: "profile-token")
        assert(basicProfile?.display_name == "Marie Test")
        StubProtocol.handler = { request in
            assert(request.url?.path == "/auth/v1/user")
            assert(request.value(forHTTPHeaderField: "Authorization") == "Bearer profile-token")
            return (200, Data(#"{"email":"marie@example.invalid","email_confirmed_at":"2026-01-01T00:00:00Z"}"#.utf8))
        }
        let currentEmail = try await auth.currentUserEmail(accessToken: "profile-token")
        assert(currentEmail == "marie@example.invalid")
        StubProtocol.handler = { _ in
            (200, Data(#"{"email":"marie@example.invalid","email_confirmed_at":null}"#.utf8))
        }
        let unconfirmedEmail = try await auth.currentUserEmail(accessToken: "profile-token")
        assert(unconfirmedEmail == nil)
        StubProtocol.handler = { request in
            assert(request.url?.path == "/rest/v1/rpc/luka_application_location")
            assert(request.httpMethod == "POST")
            assert(request.value(forHTTPHeaderField: "Authorization") == "Bearer profile-token")
            return (200, Data(#"[{"country_code":"CG","city":"Brazzaville","commune":"Bacongo"}]"#.utf8))
        }
        let location = try await profileAPI.sharedApplicationLocation(applicationID: commentID, accessToken: "profile-token")
        assert(location?.city == "Brazzaville" && location?.country_code == "CG")
        StubProtocol.handler = { _ in (200, Data("[]".utf8)) }
        let unshared = try await profileAPI.sharedApplicationLocation(applicationID: commentID, accessToken: "profile-token")
        assert(unshared == nil)
        StubProtocol.handler = { request in
            assert(request.url?.path == "/rest/v1/luka_listing_favorites")
            assert(request.value(forHTTPHeaderField: "Authorization") == "Bearer profile-token")
            if request.httpMethod == "GET" {
                return (200, Data(#"[{"listing_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}]"#.utf8))
            }
            return (204, Data())
        }
        let listingFavorites = try await profileAPI.listingFavorites(accessToken: "profile-token")
        assert(listingFavorites.map(\.listing_id) == [commentID])
        try await profileAPI.addListingFavorite(listingID: commentID, userID: commentID, accessToken: "profile-token")
        try await profileAPI.removeListingFavorite(listingID: commentID, accessToken: "profile-token")
        StubProtocol.handler = { request in
            assert(request.value(forHTTPHeaderField: "Authorization") == nil)
            assert(request.url?.query?.contains("status=") == true)
            return (200, Data("[]".utf8))
        }
        let missingSharedJob = try await profileAPI.publicJob(id: commentID)
        let missingSharedListing = try await profileAPI.publicListing(id: commentID)
        assert(missingSharedJob == nil && missingSharedListing == nil)
        StubProtocol.handler = { request in
            assert(request.url?.path == "/rest/v1/listings")
            assert(request.value(forHTTPHeaderField: "Authorization") == nil)
            assert(request.url?.query?.contains("id=") == true)
            return (200, Data("[]".utf8))
        }
        let noSavedListings = try await profileAPI.publicListings(ids: [commentID])
        assert(noSavedListings.isEmpty)
        let noQueries = try await profileAPI.publicListings(ids: [])
        assert(noQueries.isEmpty)
        print("Auth/network smoke tests: OK")
    }
}
