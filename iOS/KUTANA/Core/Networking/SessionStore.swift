import Foundation
import Combine
import Security
import AuthenticationServices

/// Observable single-account session. Persist only credentials in iOS Keychain.
@MainActor final class KutanaSessionStore: ObservableObject {
    @Published private(set) var authenticated = false
    @Published private(set) var busy = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var notice: String?

    let configuration: BackendConfiguration?
    private let tokenStore = SecureTokenStore()
    private let googleOAuth = KutanaGoogleOAuth()
    private let storageAccount = "primary"
    private var auth: KutanaAuthService?
    private(set) var active: PersistedSession?

    var isConfigured: Bool { configuration != nil }

    init(configuration: BackendConfiguration? = .fromBundle()) {
        self.configuration = configuration
        if let configuration { self.auth = KutanaAuthService(config: configuration) }
    }

    func restore() async {
        guard let auth, let data = tokenStore.load(account: storageAccount),
              let persisted = try? JSONDecoder().decode(PersistedSession.self, from: data) else { return }
        if !persisted.requiresRefresh {
            active = persisted
            authenticated = true
            return
        }
        do {
            let new = try await auth.refresh(persisted.token.refresh_token)
            try save(new)
        } catch {
            if refreshFailureInvalidatesSession(error) {
                signOut()
            } else {
                // Keep the Keychain session so a temporary outage can recover.
                active = persisted
                authenticated = true
                errorMessage = "Connexion temporairement indisponible. Réessayez."
            }
        }
    }

    func signIn(email: String, password: String) async {
        guard let auth else { errorMessage = "Le serveur KUTANA n'est pas encore configuré."; return }
        busy = true; errorMessage = nil; notice = nil
        defer { busy = false }
        do { try save(try await auth.signIn(email: email, password: password)) }
        catch { errorMessage = error.localizedDescription }
    }

    func signInWithApple(idToken: String, nonce: String) async {
        guard let auth else {
            errorMessage = "Le serveur KUTANA n'est pas configuré."
            return
        }
        busy = true; errorMessage = nil; notice = nil
        defer { busy = false }
        do {
            try save(try await auth.signInWithApple(idToken: idToken, nonce: nonce))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signInWithGoogle() async {
        guard let auth, let configuration else {
            errorMessage = "Le serveur KUTANA n'est pas configuré."
            return
        }
        busy = true; errorMessage = nil; notice = nil
        defer { busy = false }
        do {
            try await auth.verifySocialProvider("google")
            let response = try await googleOAuth.authorize(configuration: configuration)
            try save(try await auth.exchangeGoogleCode(response.code, verifier: response.verifier))
        } catch {
            if let error = error as? KutanaSocialAuthError, case .cancelled = error {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    func reportSocialSignInFailure(_ error: Error) {
        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            return
        }
        errorMessage = error.localizedDescription
    }

    func signUp(email: String, password: String, fullName: String) async -> Bool {
        guard let auth else { errorMessage = "Le serveur KUTANA n'est pas encore configuré."; return false }
        busy = true; errorMessage = nil; notice = nil
        defer { busy = false }
        do {
            try await auth.signUp(email: email, password: password, fullName: fullName)
            notice = "Consultez votre boîte mail et confirmez votre adresse avant de vous connecter."
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func resetPassword(email: String) async -> Bool {
        guard let auth else { errorMessage = "Le serveur KUTANA n'est pas encore configuré."; return false }
        busy = true; errorMessage = nil; notice = nil
        defer { busy = false }
        do {
            try await auth.requestPasswordReset(email: email)
            notice = "Si cette adresse possède un compte, un e-mail de réinitialisation sera envoyé."
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func freshAccessToken() async -> String? {
        guard let active else { return nil }
        if !active.requiresRefresh { return active.token.access_token }
        guard let auth else { signOut(); return nil }
        do {
            let newToken = try await auth.refresh(active.token.refresh_token)
            try save(newToken)
            return newToken.access_token
        } catch {
            if refreshFailureInvalidatesSession(error) {
                signOut()
            } else {
                errorMessage = "Connexion temporairement indisponible. Réessayez."
            }
            return nil
        }
    }

    func signOut() {
        tokenStore.remove(account: storageAccount)
        active = nil
        authenticated = false
        notice = nil
        errorMessage = nil
    }

    func clearMessages() { errorMessage = nil; notice = nil }

    private func save(_ token: AuthSession) throws {
        let persisted = PersistedSession(token: token, expiration: Date().addingTimeInterval(Double(token.expires_in)))
        let value = try JSONEncoder().encode(persisted)
        guard tokenStore.save(value, account: storageAccount) == errSecSuccess else {
            throw AuthFailure.invalidSession
        }
        active = persisted
        authenticated = true
    }
}
