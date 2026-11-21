import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class ChatTestProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler else { fatalError("Missing handler") }
        let (code, content) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: code,
                                       httpVersion: "HTTP/1.1", headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: content)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct ChatSmoke {
    static func main() async throws {
        let uuid = UUID(uuidString: "0c666666-6666-4666-8666-666666666666")!
        let person = UUID(uuidString: "0a111111-1111-4111-8111-111111111111")!
        let payload = Data(#"{"sub":"0a111111-1111-4111-8111-111111111111"}"#.utf8)
            .base64EncodedString().replacingOccurrences(of: "=", with: "")
        assert(AccessTokenMetadata.subject("header.\(payload).signature") == person)
        assert(AccessTokenMetadata.subject("untrusted") == nil)
        let config = BackendConfiguration(endpoint: "https://xwhjzftrzikgqweowtus.supabase.co", publishableKey: "public-test")!
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [ChatTestProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)
        defer { session.invalidateAndCancel() }
        let api = KutanaAPI(configuration: config, session: session)
        ChatTestProtocol.handler = { request in
            assert(request.httpMethod == "GET")
            assert(request.url?.path == "/rest/v1/conversations")
            assert(request.value(forHTTPHeaderField: "Authorization") == "Bearer access")
            let body = """
            [{"id":"\(uuid.uuidString)","participant_a":"\(person.uuidString)","participant_b":"11111111-1111-4111-8111-111111111111","created_at":"2026-11-21T12:00:00+00:00"}]
            """
            return (200, Data(body.utf8))
        }
        let conversations = try await api.myConversations(accessToken: "access")
        assert(conversations.count == 1 && conversations[0].id == uuid)
        ChatTestProtocol.handler = { request in
            assert(request.url?.path == "/rest/v1/messages")
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            assert(components.queryItems?.contains(where: { $0.name == "conversation_id" && $0.value == "eq.\(uuid.uuidString.lowercased())" }) == true)
            assert(request.value(forHTTPHeaderField: "Authorization") == "Bearer access")
            return (200, Data("[]".utf8))
        }
        let empty = try await api.conversationMessages(conversationID: uuid, accessToken: "access")
        assert(empty.isEmpty)
        ChatTestProtocol.handler = { request in
            assert(request.url?.path == "/rest/v1/rpc/send_conversation_message")
            assert(request.httpMethod == "POST")
            assert(request.value(forHTTPHeaderField: "Authorization") == "Bearer access")
            let json = try! JSONSerialization.jsonObject(with: request.httpBody!) as! [String:String]
            assert(json["p_body"] == "Bonjour")
            assert(json["p_conversation"] == uuid.uuidString.lowercased())
            assert(json["sender_id"] == nil)
            return (200, Data("\"\(uuid.uuidString.lowercased())\"".utf8))
        }
        let sent = try await api.sendMessage(conversationID: uuid, text: "  Bonjour  ", accessToken: "access")
        assert(sent == uuid)
        do {
            _ = try await api.sendMessage(conversationID: uuid, text: "  ", accessToken: "access")
            fatalError("Blank message accepted")
        } catch BackendError.invalidResponse { /* expected */ }
        print("Private chat transport and payload tests: OK")
    }
}
