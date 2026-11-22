import SwiftUI

struct JobsView: View {
    @EnvironmentObject private var identity: KutanaSessionStore
    @State private var query = ""
    @State private var records: [JobRecord] = []
    @State private var loading = false
    @State private var errorMessage: String?

    private var isPreview: Bool { identity.configuration == nil }

    private var previewRecords: [JobRecord] {
        let author = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
        let date = Date()
        return [
            JobRecord(id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!, author_id: author, title: "Assistant commercial (H/F)", company: "Entreprise de distribution", city: "Brazzaville", contract_type: "CDI", description: "Exemple de présentation KUTANA. Cette offre n'est pas publiée et aucune candidature ne peut y être envoyée.", status: "demo", created_at: date),
            JobRecord(id: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!, author_id: author, title: "Chargé de marketing digital (H/F)", company: "Agence de communication", city: "Pointe-Noire", contract_type: "CDD", description: "Exemple de présentation KUTANA. Cette offre n'est pas publiée.", status: "demo", created_at: date)
        ]
    }

    private var visible: [JobRecord] {
        let all = isPreview ? previewRecords : records
        guard !query.isEmpty else { return all }
        return all.filter { [$0.title, $0.company, $0.city, $0.contract_type]
            .contains { $0.localizedCaseInsensitiveContains(query) } }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Trouvez votre prochain emploi au Congo")
                            .font(.largeTitle.bold()).foregroundStyle(KutanaTheme.ink)
                        Text("Des opportunités près de vous").foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                }
                if isPreview {
                    Section {
                        Label("Aperçu de maquette · aucune de ces offres n'est réelle", systemImage: "info.circle")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if loading { Section { ProgressView("Chargement des offres…") } }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
                }
                Section(isPreview ? "Offres de démonstration" : "Offres récentes") {
                    ForEach(visible) { job in
                        NavigationLink {
                            JobDetailView(job: job, preview: isPreview)
                        } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                Text(job.title).font(.headline)
                                Text(job.company).font(.subheadline)
                                Label("\(job.city) · \(job.contract_type)", systemImage: "mappin")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 6)
                        }
                    }
                    if visible.isEmpty && !loading {
                        ContentUnavailableView.search(text: query)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, prompt: "Métier, entreprise, ville…")
            .refreshable { await load() }
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(isPreview || loading).accessibilityLabel("Actualiser les offres")
            }}
            .navigationTitle("KUTANA")
            .task { await load() }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("kutana-publications-changed"))) { _ in
                Task { await load() }
            }
        }
    }

    @MainActor private func load() async {
        guard let configuration = identity.configuration else { return }
        loading = true; errorMessage = nil
        defer { loading = false }
        do { records = try await KutanaAPI(configuration: configuration).publishedJobs() }
        catch { errorMessage = "Impossible de charger les offres. Réessayez." }
    }
}

struct JobDetailView: View {
    let job: JobRecord
    let preview: Bool
    @EnvironmentObject private var identity: KutanaSessionStore
    @State private var sending = false
    @State private var sent = false
    @State private var showReport = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(job.title).font(.largeTitle.bold()).foregroundStyle(KutanaTheme.ink)
                Text(job.company).font(.title3)
                Label("\(job.city) · \(job.contract_type)", systemImage: "mappin")
                    .foregroundStyle(.secondary)
                Divider()
                Text("Description du poste").font(.title2.bold())
                Text(job.description)
                if sent { Label("Candidature envoyée", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                KutanaPrimaryButton(title: sending ? "Envoi en cours…" : "Postuler à cette offre") {
                    Task { await apply() }
                }
                .disabled(preview || !identity.authenticated || sending || sent || isMine)
                if sent {
                    Text("Pour joindre votre CV PDF à cette candidature, ouvrez Profil, puis Mes candidatures.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if preview || !identity.authenticated {
                    Text(preview ? "Offre fictive : candidature désactivée." : "Connectez-vous pour postuler.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.padding(20)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Signaler", systemImage: "flag") { showReport = true }
                    .disabled(preview || !identity.authenticated || isMine)
            }
        }
        .sheet(isPresented: $showReport) {
            ReportContentSheet(kind: "job", contentID: job.id)
                .environmentObject(identity)
        }
    }

    private var isMine: Bool {
        guard let token = identity.active?.token.access_token,
              let ownID = AccessTokenMetadata.subject(token) else { return false }
        return job.author_id == ownID
    }

    @MainActor private func apply() async {
        guard let configuration = identity.configuration,
              let token = await identity.freshAccessToken() else {
            errorMessage = "Connectez-vous avant de postuler."
            return
        }
        sending = true; errorMessage = nil
        defer { sending = false }
        do {
            _ = try await KutanaAPI(configuration: configuration).applyToJob(jobID: job.id, accessToken: token)
            sent = true
        } catch { errorMessage = "La candidature n'a pas été enregistrée. Réessayez." }
    }
}
