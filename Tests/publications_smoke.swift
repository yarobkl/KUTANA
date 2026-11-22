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
            assert(request.httpMethod == "GET")
            assert(request.url?.path == "/rest/v1/rpc/received_applications")
            assert(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
            return (200, Data("""
            [{"id":"\(id.uuidString.lowercased())","job_id":"\(id.uuidString.lowercased())",
              "candidate_id":"\(owner.uuidString.lowercased())",
              "status":"submitted","created_at":"2026-11-22T18:00:00+00:00",
              "job_title":"Assistant commercial","company":"Entreprise",
              "candidate_name":"Candidat Exemple"}]
            """.utf8))
        }
        let received = try await api.receivedApplications(accessToken: "test-token")
        assert(received.count == 1 && received[0].candidate_name == "Candidat Exemple")

        PublicationProtocol.handler = { request in
            assert(request.httpMethod == "POST")
            assert(request.url?.path == "/rest/v1/rpc/change_application_status")
            assert(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
            let body = try! JSONSerialization.jsonObject(with: capturedRequestBody(request)!) as! [String:String]
            assert(body["p_application"] == id.uuidString.lowercased())
            assert(body["p_next"] == "shortlisted")
            return (204, Data())
        }
        try await api.changeApplicationStatus(id: id, next: .shortlisted, accessToken: "test-token")


        PublicationProtocol.handler = { request in
            assert(request.url?.path == "/rest/v1/rpc/publish_job")
            assert(request.httpMethod == "POST")
            assert(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
            let payload = try! JSONSerialization.jsonObject(with: capturedRequestBody(request)!) as! [String:String]
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
            let payload = try! JSONSerialization.jsonObject(with: capturedRequestBody(request)!) as! [String:String]
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
            let payload = try! JSONSerialization.jsonObject(with: capturedRequestBody(request)!) as! [String:String]
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


        let jpg = Data([0xff, 0xd8, 0xff, 0xe0, 0x01, 0x02])
        let photoPath = "\(owner.uuidString.lowercased())/\(id.uuidString.lowercased())/\(id.uuidString.lowercased()).jpg"
        let imageURL = config.publicListingImageURL(path: photoPath)
        assert(imageURL?.path.contains("/storage/v1/object/public/kutana-listing-images/") == true)
        assert(config.publicListingImageURL(path: "../malicious.jpg") == nil)

        PublicationProtocol.handler = { request in
            assert(request.url?.path == "/rest/v1/listing_images")
            assert(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
            return (200, Data("""
            [{"id":"\(id.uuidString.lowercased())","listing_id":"\(id.uuidString.lowercased())",
              "storage_path":"\(photoPath)","sort_order":0}]
            """.utf8))
        }
        let photos = try await api.listingImages(listingID: id, accessToken: "test-token")
        assert(photos.count == 1 && photos[0].storage_path == photoPath)

        PublicationProtocol.handler = { request in
            if request.url?.path.hasPrefix("/storage/v1/object/kutana-listing-images/") == true {
                assert(request.httpMethod == "POST")
                assert(request.value(forHTTPHeaderField: "Content-Type") == "image/jpeg")
                return (200, Data("{}".utf8))
            }
            assert(request.url?.path == "/rest/v1/rpc/attach_listing_image")
            let body = try! JSONSerialization.jsonObject(with: capturedRequestBody(request)!) as! [String:String]
            assert(body["p_listing"] == id.uuidString.lowercased())
            assert(body["p_path"]?.hasSuffix(".jpg") == true)
            return (200, Data("\"\(id.uuidString.lowercased())\"".utf8))
        }
        let uploadedPhoto = try await api.uploadListingImage(jpg, listingID: id,
                                                              ownerID: owner, accessToken: "test-token")
        assert(uploadedPhoto == id)

        let pdf = Data("%PDF-1.7\n1 0 obj\n<<>>\nendobj\n%%EOF".utf8)
        let cvPath = "\(owner.uuidString.lowercased())/\(id.uuidString.lowercased()).pdf"
        PublicationProtocol.handler = { request in
            if request.url?.path.hasPrefix("/storage/v1/object/kutana-cvs/") == true {
                assert(request.value(forHTTPHeaderField: "Content-Type") == "application/pdf")
                return (200, Data("{}".utf8))
            }
            assert(request.url?.path == "/rest/v1/rpc/attach_application_cv")
            let body = try! JSONSerialization.jsonObject(with: capturedRequestBody(request)!) as! [String:String]
            assert(body["p_application"] == id.uuidString.lowercased())
            assert(body["p_file_name"] == "test.pdf")
            return (200, Data("\"\(id.uuidString.lowercased())\"".utf8))
        }
        let cvAttached = try await api.uploadApplicationCV(pdf, filename: "test.pdf",
            applicationID: id, ownerID: owner, accessToken: "test-token")
        assert(cvAttached == id)

        PublicationProtocol.handler = { request in
            assert(request.url?.path == "/rest/v1/application_cvs")
            return (200, Data("""
            [{"application_id":"\(id.uuidString.lowercased())",
              "storage_path":"\(cvPath)","file_name":"test.pdf"}]
            """.utf8))
        }
        let cv = try await api.applicationCV(applicationID: id, accessToken: "test-token")
        assert(cv?.storage_path == cvPath)

        PublicationProtocol.handler = { request in
            assert(request.url?.path == "/storage/v1/object/authenticated/kutana-cvs/\(cvPath)")
            assert(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
            return (200, pdf)
        }
        if let cv {
            let local = try await api.downloadApplicationCV(cv, accessToken: "test-token")
            assert(FileManager.default.fileExists(atPath: local.path))
            try FileManager.default.removeItem(at: local)
        }

        print("KUTANA publication, recruiter applications, withdrawal, seller chat and report and private media HTTP contract: OK")
    }
}
