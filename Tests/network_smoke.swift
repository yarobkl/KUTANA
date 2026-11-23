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
        print("Auth/network smoke tests: OK")
    }
}
