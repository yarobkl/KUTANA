import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class PublicationProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler else { fatalError("Missing HTTP stub") }
        let (code, body) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: code,
                                       httpVersion: "HTTP/1.1", headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct PublicationsSmoke {
    static func main() async throws {
        let id = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
        let owner = UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!
        let config = BackendConfiguration(endpoint: "https://xwhjzftrzikgqweowtus.supabase.co",
                                          publishableKey: "public-test")!
        let network = URLSessionConfiguration.ephemeral
        network.protocolClasses = [PublicationProtocol.self]
        let session = URLSession(configuration: network)
        defer { session.invalidateAndCancel() }
        let api = KutanaAPI(configuration: config, session: session)

        PublicationProtocol.handler = { request in
            assert(request.httpMethod == "GET")
            assert(request.url?.path == "/rest/v1/jobs")
            assert(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            assert(components.queryItems?.contains(where: {
                $0.name == "author_id" && $0.value == "eq.\(owner.uuidString.lowercased())"
            }) == true)
            return (200, Data("""
            [{"id":"\(id.uuidString.lowercased())","author_id":"\(owner.uuidString.lowercased())",
              "title":"Assistant commercial","company":"Entreprise","city":"Brazzaville",
              "contract_type":"CDI","description":"Description de poste complete pour le test.",
              "status":"draft","created_at":"2026-11-22T18:00:00+00:00"}]
            """.utf8))
        }
        let mine = try await api.myJobs(ownerID: owner, accessToken: "test-token")
        assert(mine.count == 1 && mine[0].status == "draft")

        PublicationProtocol.handler = { request in
            assert(request.url?.path == "/rest/v1/rpc/publish_job")
            assert(request.httpMethod == "POST")
            assert(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
            let payload = try! JSONSerialization.jsonObject(with: request.httpBody!) as! [String:String]
            assert(payload["p_job"] == id.uuidString.lowercased())
            return (200, Data("\"\(id.uuidString.lowercased())\"".utf8))
        }
        let publishedJob = try await api.publishJob(id: id, accessToken: "test-token")
        assert(publishedJob == id)

        PublicationProtocol.handler = { request in
            assert(request.url?.path == "/rest/v1/rpc/publish_listing")
            return (200, Data("\"\(id.uuidString.lowercased())\"".utf8))
        }
        let publishedListing = try await api.publishListing(id: id, accessToken: "test-token")
        assert(publishedListing == id)

        PublicationProtocol.handler = { request in
            assert(request.url?.path == "/rest/v1/rpc/withdraw_publication")
            let payload = try! JSONSerialization.jsonObject(with: request.httpBody!) as! [String:String]
            assert(payload["p_kind"] == "listing")
            assert(payload["p_id"] == id.uuidString.lowercased())
            return (200, Data("\"\(id.uuidString.lowercased())\"".utf8))
        }
        let withdrawn = try await api.withdrawPublication(kind: "listing", id: id, accessToken: "test-token")
        assert(withdrawn == id)

        PublicationProtocol.handler = { request in
            assert(request.url?.path == "/rest/v1/rpc/start_listing_conversation")
            return (200, Data("\"\(id.uuidString.lowercased())\"".utf8))
        }
        let conversationID = try await api.startListingConversation(listingID: id, accessToken: "test-token")
        assert(conversationID == id)

        PublicationProtocol.handler = { request in
            assert(request.url?.path == "/rest/v1/rpc/report_content")
            let payload = try! JSONSerialization.jsonObject(with: request.httpBody!) as! [String:String]
            assert(payload["p_kind"] == "job")
            assert(payload["p_reason"] == "Contenu suspect")
            return (200, Data("\"\(id.uuidString.lowercased())\"".utf8))
        }
        let reportID = try await api.reportContent(kind: "job", id: id, reason: "  Contenu suspect  ", accessToken: "test-token")
        assert(reportID == id)
        do {
            _ = try await api.reportContent(kind: "job", id: id, reason: "court", accessToken: "test-token")
            assertionFailure("A short report should be rejected")
        } catch BackendError.invalidResponse { /* expected */ }

        print("KUTANA publication, owner filters, withdrawal, seller chat and report HTTP contract: OK")
    }
}
