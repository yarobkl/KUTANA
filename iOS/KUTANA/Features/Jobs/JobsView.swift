import SwiftUI

struct JobsView: View {
    @EnvironmentObject private var identity: KutanaSessionStore
    @State private var query = ""
    @State private var records: [JobRecord] = []
    @State private var loading = false
    @State private var hasLoaded = false
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
                if loading && !hasLoaded {
                    Section("Offres récentes") {
                        ForEach(0..<4, id: \.self) { _ in KutanaLoadingRow() }
                    }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
                }
                if !loading || hasLoaded || isPreview {
                Section(isPreview ? "Offres de démonstration" : "Offres récentes") {
                    ForEach(visible) { job in
                        NavigationLink {
                            JobDetailView(job: job, preview: isPreview)
                        } label: {
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: "building.2.crop.circle")
                                    .font(.system(size: 25, weight: .light))
                                    .foregroundStyle(KutanaTheme.blue)
                                    .frame(width: 48, height: 48)
                                    .background(Color(.secondarySystemGroupedBackground),
                                                in: RoundedRectangle(cornerRadius: 13))
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(job.title)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    Text(job.company)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    HStack(spacing: 8) {
                                        Label(job.city, systemImage: "mappin")
                                        Text(job.contract_type)
                                            .fontWeight(.semibold)
                                    }
                                    .font(.caption)
                                    .foregroundStyle(KutanaTheme.blue)
                                }
                            }
                            .padding(.vertical, 9)
                        }
                    }
                    if visible.isEmpty && !loading && hasLoaded {
                        ContentUnavailableView.search(text: query)
                    }
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
        defer { loading = false; hasLoaded = true }
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
    @State private var favorite = false
    @State private var favoriteBusy = false

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
                if identity.authenticated && !isMine && !preview {
                    Button {
                        Task { await toggleFavorite() }
                    } label: {
                        Label(favorite ? "Retirer des favoris" : "Ajouter aux favoris", systemImage: favorite ? "bookmark.fill" : "bookmark")
                    }.disabled(favoriteBusy)
                    Text("Un favori crée aussi une alerte pour des offres similaires dans cette ville. Vous pouvez l'ajuster dans Profil.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
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
        .task { await loadFavorite() }
    }

    @MainActor private func loadFavorite() async {
        guard identity.authenticated, !preview, let config = identity.configuration,
              let token = await identity.freshAccessToken() else { return }
        do { favorite = try await KutanaAPI(configuration: config).favorites(accessToken: token).contains { $0.job_id == job.id } }
        catch { errorMessage = "Impossible de charger les favoris." }
    }

    @MainActor private func toggleFavorite() async {
        guard let config = identity.configuration, let token = await identity.freshAccessToken(),
              let userID = AccessTokenMetadata.subject(token) else { return }
        favoriteBusy = true
        defer { favoriteBusy = false }
        do {
            let api = KutanaAPI(configuration: config)
            if favorite { try await api.removeFavorite(jobID: job.id, accessToken: token) }
            else {
                try await api.addFavorite(jobID: job.id, userID: userID, accessToken: token)
                let terms = job.title.split(separator: " ").prefix(2).joined(separator: " ")
                if terms.count >= 2 {
                    try await api.addAlert(keyword: terms, city: job.city, userID: userID, accessToken: token)
                }
            }
            favorite.toggle(); errorMessage = nil
        } catch { errorMessage = "Impossible de modifier les favoris." }
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
