import Foundation
import AuthenticationServices
import CryptoKit
import Security
import UIKit

// Apple ID token + Google PKCE never expose private OAuth credentials in the iOS binary.
enum KutanaSocialAuthError: LocalizedError {
    case randomUnavailable
    case failedToStart
    case cancelled
    case missingAuthorizationCode
    case invalidRedirect
    case missingAppleToken
    case providerNotReady

    var errorDescription: String? {
        switch self {
        case .randomUnavailable:
            "La connexion sécurisée n'a pas pu démarrer. Réessayez."
        case .failedToStart:
            "Impossible d'ouvrir la connexion Google."
        case .cancelled:
            "Connexion annulée."
        case .missingAuthorizationCode, .invalidRedirect:
            "Google n'a pas renvoyé une session valide. Réessayez."
        case .missingAppleToken:
            "Apple n'a pas transmis de jeton d'identité. Réessayez."
        case .providerNotReady:
            "Le service de connexion n'est pas encore configuré sur le serveur KUTANA."
        }
    }
}

enum KutanaAuthNonce {
    static func generate() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = bytes.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!)
        }
        guard status == errSecSuccess else { throw KutanaSocialAuthError.randomUnavailable }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func appleHash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    static func pkceChallenge(_ verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8)))
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Uses the system browser, a unique PKCE verifier and the app's own callback scheme.
/// The redirect URI must be whitelisted under Supabase Auth > URL Configuration.
@MainActor
final class KutanaGoogleOAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    static let callback = "kutana://auth/callback"

    func authorize(configuration: BackendConfiguration) async throws -> (code: String, verifier: String) {
        let verifier = try KutanaAuthNonce.generate()
        guard var url = URLComponents(
            url: configuration.endpoint.appendingPathComponent("auth/v1/authorize"),
            resolvingAgainstBaseURL: false
        ) else { throw KutanaSocialAuthError.invalidRedirect }
        url.queryItems = [
            URLQueryItem(name: "provider", value: "google"),
            URLQueryItem(name: "redirect_to", value: Self.callback),
            URLQueryItem(name: "code_challenge", value: KutanaAuthNonce.pkceChallenge(verifier)),
            URLQueryItem(name: "code_challenge_method", value: "s256")
        ]
        guard let authorizationURL = url.url else { throw KutanaSocialAuthError.invalidRedirect }

        let returnedURL: URL = try await withCheckedThrowingContinuation { continuation in
            let browser = ASWebAuthenticationSession(
                url: authorizationURL,
                callbackURLScheme: "kutana"
            ) { returned, error in
                if let error {
                    if let authError = error as? ASWebAuthenticationSessionError,
                       authError.code == .canceledLogin {
                        continuation.resume(throwing: KutanaSocialAuthError.cancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                guard let returned else {
                    continuation.resume(throwing: KutanaSocialAuthError.invalidRedirect)
                    return
                }
                continuation.resume(returning: returned)
            }
            self.session = browser
            browser.presentationContextProvider = self
            browser.prefersEphemeralWebBrowserSession = false
            guard browser.start() else {
                continuation.resume(throwing: KutanaSocialAuthError.failedToStart)
                return
            }
        }
        session = nil
        guard returnedURL.scheme == "kutana",
              returnedURL.host == "auth",
              returnedURL.path == "/callback" else {
            throw KutanaSocialAuthError.invalidRedirect
        }
        let values = URLComponents(url: returnedURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let message = values.first(where: { $0.name == "error_description" })?.value {
            throw AuthFailure.remoteMessage(message)
        }
        guard let code = values.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else {
            throw KutanaSocialAuthError.missingAuthorizationCode
        }
        return (code, verifier)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
