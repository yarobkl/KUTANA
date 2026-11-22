import SwiftUI

struct ProblemReportView: View {
    @EnvironmentObject private var identity: KutanaSessionStore
    @State private var details = ""
    @State private var sending = false
    @State private var confirmation: UUID?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Text("Un bouton bloqué, une page qui ne s'affiche pas ? Décrivez ce qui s'est passé et où le problème apparaît.")
                    .foregroundStyle(.secondary)
                TextField("Décrivez le problème…", text: $details, axis: .vertical)
                    .lineLimit(5...12)
            } header: { Text("Votre signalement") } footer: {
                Text("N'incluez pas de mot de passe ni d'informations sensibles.")
            }
            Section {
                if let confirmation {
                    Label("Signalement reçu", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Référence : \(confirmation.uuidString)").font(.caption).textSelection(.enabled)
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
                Button(sending ? "Envoi en cours…" : "Envoyer le signalement") {
                    Task { await submit() }
                }
                .disabled(sending || confirmation != nil || details.trimmingCharacters(in: .whitespacesAndNewlines).count < 10)
            }
        }
        .navigationTitle("Signaler un problème")
    }

    @MainActor private func submit() async {
        guard let config = identity.configuration,
              let token = await identity.freshAccessToken() else {
            errorMessage = "Connectez-vous pour envoyer un signalement."
            return
        }
        sending = true; errorMessage = nil
        defer { sending = false }
        let version = "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))"
        do {
            confirmation = try await KutanaAPI(configuration: config).submitProblem(
                details: details.trimmingCharacters(in: .whitespacesAndNewlines),
                appVersion: version, accessToken: token)
        } catch {
            errorMessage = "Le signalement n'a pas été enregistré. Réessayez."
        }
    }
}
