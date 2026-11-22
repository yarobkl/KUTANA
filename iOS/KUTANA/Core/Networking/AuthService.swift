import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct AuthSession: Codable, Sendable {
    let access_token: String
    let refresh_token: String
    let expires_in: Int
    let token_type: String
}

struct AuthResponse: Decodable, Sendable {
    let access_token: String?
    let refresh_token: String?
    let expires_in: Int?
    let token_type: String?
}

struct PersistedSession: Codable {
    let token: AuthSession
    let expiration: Date
    var requiresRefresh: Bool { expiration <= Date().addingTimeInterval(60) }
}

enum AuthFailure: LocalizedError {
    case invalidEmail, weakPassword, missingName, confirmationRequired, invalidCredentials
    case badResponse(Int), invalidSession, remoteMessage(String)
    var errorDescription: String? {
        switch self {
        case .invalidEmail: "Saisissez une adresse e-mail valide."
        case .weakPassword: "Le mot de passe doit contenir au moins 12 caractères."
        case .missingName: "Indiquez vos nom et prénom."
        case .confirmationRequired: "Confirmez votre adresse e-mail avant de vous connecter."
        case .invalidCredentials: "Adresse e-mail ou mot de passe incorrect."
        case .badResponse(let code): "Le serveur a renvoyé une erreur (\(code))."
        case .invalidSession: "La session a expiré. Reconnectez-vous."
        case .remoteMessage(let message): message
        }
    }
}

/// Supabase GoTrue REST client. No service_role or other server secret belongs in this app.
actor KutanaAuthService {
    private let config: BackendConfiguration
    private let http: URLSession

    init(config: BackendConfiguration, session: URLSession = .shared) {
        self.config = config
        self.http = session
    }

    func signUp(email: String, password: String, fullName: String) async throws {
        let normalizedEmail = try validatedEmail(email)
        guard password.count >= 12 else { throw AuthFailure.weakPassword }
        let cleanedName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanedName.count >= 2 else { throw AuthFailure.missingName }
        // If the provider returns a token because email confirmations are disabled,
        // intentionally discard it: KUTANA requires explicit email verification.
        let _: AuthResponse = try await send(path: "signup", body: [
            "email": normalizedEmail,
            "password": password,
            "data": ["display_name": cleanedName]
        ])
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        let response: AuthResponse = try await send(path: "token?grant_type=password", body: [
            "email": try validatedEmail(email), "password": password
        ])
        return try validatedSession(response)
    }

    /// Public Auth settings: don't launch a provider when it is disabled server-side.
    func verifySocialProvider(_ name: String) async throws {
        guard let url = URL(string: "auth/v1/settings", relativeTo: config.endpoint)?.absoluteURL else {
            throw AuthFailure.invalidSession
        }
        var request = URLRequest(url: url)
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        let (data, response) = try await http.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AuthFailure.remoteMessage("Impossible de vérifier les connexions externes de KUTANA.")
        }
        let settings = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let providers = settings?["external"] as? [String: Any]
        if (providers?[name] as? Bool) == false {
            let label = name == "apple" ? "Apple" : "Google"
            throw AuthFailure.remoteMessage("Connexion \(label) indisponible : ce service n’est pas encore activé sur KUTANA.")
        }
    }

    /// Supabase GoTrue exchanges Apple's native identity token for a KUTANA session.
    func signInWithApple(idToken: String, nonce: String) async throws -> AuthSession {
        guard !idToken.isEmpty, !nonce.isEmpty else { throw AuthFailure.invalidSession }
        try await verifySocialProvider("apple")
        let response: AuthResponse = try await send(path: "token?grant_type=id_token", body: [
            "provider": "apple", "id_token": idToken, "nonce": nonce
        ])
        return try validatedSession(response)
    }

    /// Exchange a short-lived, PKCE-protected Google OAuth authorization code.
    func exchangeGoogleCode(_ code: String, verifier: String) async throws -> AuthSession {
        let response: AuthResponse = try await send(path: "token?grant_type=pkce", body: [
            "auth_code": code, "code_verifier": verifier
        ])
        return try validatedSession(response)
    }

    func refresh(_ refreshToken: String) async throws -> AuthSession {
        let response: AuthResponse = try await send(path: "token?grant_type=refresh_token", body: [
            "refresh_token": refreshToken
        ])
        return try validatedSession(response)
    }

    func requestPasswordReset(email: String) async throws {
        let _: AuthResponse = try await send(path: "recover", body: ["email": try validatedEmail(email)])
    }

    private func validatedEmail(_ email: String) throws -> String {
        let result = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let parts = result.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."),
              !result.contains(" ") else { throw AuthFailure.invalidEmail }
        return result
    }

    private func validatedSession(_ response: AuthResponse) throws -> AuthSession {
        guard let access = response.access_token, !access.isEmpty,
              let refresh = response.refresh_token, !refresh.isEmpty,
              let expires = response.expires_in, expires > 0,
              let kind = response.token_type, kind.lowercased() == "bearer" else {
            throw AuthFailure.confirmationRequired
        }
        return AuthSession(access_token: access, refresh_token: refresh,
                           expires_in: expires, token_type: kind)
    }

    private func send<T: Decodable>(path: String, body: [String: Any]) async throws -> T {
        guard let url = URL(string: "auth/v1/" + path, relativeTo: config.endpoint)?.absoluteURL else {
            throw AuthFailure.invalidSession
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await http.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw AuthFailure.invalidSession }
        guard (200...299).contains(response.statusCode) else {
            if response.statusCode == 400 || response.statusCode == 401 {
                let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let detail = (message?["msg"] as? String)
                    ?? (message?["error_description"] as? String)
                    ?? (message?["message"] as? String)
                    ?? ""
                if detail.localizedCaseInsensitiveContains("email not confirmed") {
                    throw AuthFailure.confirmationRequired
                }
                if path.contains("grant_type=id_token") || path.contains("grant_type=pkce") {
                    if detail.localizedCaseInsensitiveContains("provider") &&
                        (detail.localizedCaseInsensitiveContains("disabled") ||
                         detail.localizedCaseInsensitiveContains("not enabled")) {
                        throw AuthFailure.remoteMessage("La connexion via ce fournisseur n’est pas encore activée sur KUTANA.")
                    }
                    throw AuthFailure.remoteMessage(detail.isEmpty
                        ? "La connexion avec ce fournisseur n'est pas disponible. Vérifiez sa configuration."
                        : detail)
                }
                throw AuthFailure.invalidCredentials
            }
            throw AuthFailure.badResponse(response.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data.isEmpty ? Data("{}".utf8) : data)
    }
}
