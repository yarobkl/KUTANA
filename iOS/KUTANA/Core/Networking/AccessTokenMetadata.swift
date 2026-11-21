import Foundation

/// Read-only UI hint from the current access token. This is NOT a JWT signature
/// validator and MUST NOT be used to grant permissions or build SQL filters.
enum AccessTokenMetadata {
    static func subject(_ token: String) -> UUID? {
        let sections = token.split(separator: ".", omittingEmptySubsequences: false)
        guard sections.count == 3 else { return nil }
        var encoded = String(sections[1]).replacingOccurrences(of: "-", with: "+")
                                         .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let payload = Data(base64Encoded: encoded),
              let dictionary = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let sub = dictionary["sub"] as? String else { return nil }
        return UUID(uuidString: sub)
    }
}
