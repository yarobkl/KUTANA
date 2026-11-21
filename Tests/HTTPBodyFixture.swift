import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// URLProtocol receives an HTTP body differently across Apple Foundation and
/// swift-corelibs-foundation. Test the outgoing payload on both platforms.
func capturedRequestBody(_ request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var body = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while true {
        let readCount = stream.read(&buffer, maxLength: buffer.count)
        if readCount < 0 { return nil }
        if readCount == 0 { return body }
        body.append(contentsOf: buffer[..<readCount])
    }
}
