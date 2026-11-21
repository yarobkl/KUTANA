import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class DraftRequestProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler else { fatalError("Missing stub") }
        let (status, body) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct DraftsSmoke {
    static func main() async throws {
        let job = try JobDraftInput(title: "  Chargé de communication  ", company: "Exemple Congo",
                                    city: "Brazzaville", contract: "CDI",
                                    description: "Préparer les supports et animer les campagnes de communication.")
        assert(job.p_title == "Chargé de communication")
        do {
            _ = try JobDraftInput(title: "A", company: "Exemple", city: "Brazzaville", contract: "CDI",
                                   description: "Une description de taille suffisante pour ce test.")
            fatalError("Job validation failed")
        } catch DraftValidationError.title { /* correct */ }

        let listing = try ListingDraftInput(category: "Téléphones", title: "iPhone d'occasion", description: "Très bon état, chargeur inclus.", city: "Pointe-Noire", price: "120 000")
        assert(listing.p_price_xaf == 120_000)
        do {
            _ = try ListingDraftInput(category: "Téléphones", title: "iPhone d'occasion", description: "Très bon état, chargeur inclus.", city: "Pointe-Noire", price: "-3")
            fatalError("Price validation failed")
        } catch DraftValidationError.price { /* correct */ }

        let config = BackendConfiguration(endpoint: "https://xwhjzftrzikgqweowtus.supabase.co", publishableKey: "public-test")!
        let mockConfig = URLSessionConfiguration.ephemeral
        mockConfig.protocolClasses = [DraftRequestProtocol.self]
        let session = URLSession(configuration: mockConfig)
        defer { session.invalidateAndCancel() }
        let identifier = UUID()
        DraftRequestProtocol.handler = { request in
            assert(request.url?.path == "/rest/v1/rpc/create_job_draft")
            assert(request.httpMethod == "POST")
            assert(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-test")
            let body = try! JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            assert(body["p_title"] as? String == "Chargé de communication")
            assert(body["p_company"] as? String == "Exemple Congo")
            assert(body["author_id"] == nil)
            assert(body["status"] == nil)
            return (200, Data("\"\(identifier.uuidString.lowercased())\"".utf8))
        }
        let api = KutanaAPI(configuration: config, session: session)
        let returned = try await api.createJobDraft(job, accessToken: "access-test")
        assert(returned == identifier)
        DraftRequestProtocol.handler = { request in
            assert(request.url?.path == "/rest/v1/rpc/create_listing_draft")
            let body = try! JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            assert(body["p_price_xaf"] as? Int == 120_000)
            assert(body["seller_id"] == nil)
            return (200, Data("\"\(identifier.uuidString.lowercased())\"".utf8))
        }
        let listingID = try await api.createListingDraft(listing, accessToken: "access-test")
        assert(listingID == identifier)
        print("Draft validation and RPC smoke tests: OK")
    }
}
