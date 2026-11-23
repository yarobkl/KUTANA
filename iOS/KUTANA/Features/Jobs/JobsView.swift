import SwiftUI

struct JobsView: View {
    let unreadCount: Int
    @Namespace private var navigationNamespace
    @EnvironmentObject private var identity: KutanaSessionStore
    @State private var query = ""
    @State private var cityFilter: String?
    @State private var contractFilter: String?
    @State private var favoritesOnly = false
    @State private var favoriteIDs: Set<UUID> = []
    @State private var records: [JobRecord] = []
    @State private var loading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?

    private var isPreview: Bool { identity.configuration == nil }

    private var previewRecords: [JobRecord] {
        let author = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
        let date = Date()
        return [
            JobRecord(id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!, author_id: author, title: "Assistant commercial (H/F)", company: "Entreprise de distribution", city: "Brazzaville", contract_type: "CDI", description: "Exemple de présentation LUKA. Cette offre n'est pas publiée et aucune candidature ne peut y être envoyée.", status: "demo", created_at: date),
            JobRecord(id: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!, author_id: author, title: "Chargé de marketing digital (H/F)", company: "Agence de communication", city: "Pointe-Noire", contract_type: "CDD", description: "Exemple de présentation LUKA. Cette offre n'est pas publiée.", status: "demo", created_at: date)
        ]
    }

    private var visible: [JobRecord] {
        let all = isPreview ? previewRecords : records
        return all.filter { job in
            (query.isEmpty || [job.title, job.company, job.city, job.contract_type]
                .contains { $0.localizedCaseInsensitiveContains(query) }) &&
            (cityFilter == nil || job.city == cityFilter) &&
            (contractFilter == nil || job.contract_type == contractFilter) &&
            (!favoritesOnly || favoriteIDs.contains(job.id))
        }
    }

    private var cities: [String] { Array(Set((isPreview ? previewRecords : records).map(\.city))).sorted() }
    private var contracts: [String] { Array(Set((isPreview ? previewRecords : records).map(\.contract_type))).sorted() }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    KutanaInlineSearch(text: $query, prompt: "Métier, entreprise ou ville")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Menu {
                                Button("Tous les lieux") { cityFilter = nil }
                                ForEach(cities, id: \.self) { city in
                                    Button(city) { cityFilter = city }
                                }
                            } label: { KutanaFilterChip(title: cityFilter ?? "Lieu", symbol: "chevron.down", active: cityFilter != nil) }
                            Menu {
                                Button("Tous les contrats") { contractFilter = nil }
                                ForEach(contracts, id: \.self) { contract in
                                    Button(contract) { contractFilter = contract }
                                }
                            } label: { KutanaFilterChip(title: contractFilter ?? "Contrat", symbol: "chevron.down", active: contractFilter != nil) }
                            Button {
                                if identity.authenticated { favoritesOnly.toggle() }
                                else { NotificationCenter.default.post(name: Notification.Name("kutana-request-login"), object: nil) }
                            } label: {
                                KutanaFilterChip(title: "Favoris", symbol: favoritesOnly ? "bookmark.fill" : "bookmark", active: favoritesOnly)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
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
                                .modifier(KutanaTransitionDestination(id: job.id, namespace: navigationNamespace))
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
                            .modifier(KutanaTransitionSource(id: job.id, namespace: navigationNamespace))
                        }
                    }
                    if visible.isEmpty && !loading && hasLoaded {
                        ContentUnavailableView("Aucune offre", systemImage: "briefcase",
                            description: Text("Essayez d'autres critères de recherche."))
                    }
                }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { await load() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if identity.authenticated {
                        NavigationLink { NotificationsView() } label: {
                            Image(systemName: unreadCount > 0 ? "bell.badge.fill" : "bell")
                        }
                        .accessibilityLabel(unreadCount > 0 ? "Notifications, \(unreadCount) non lues" : "Notifications")
                    } else {
                        Button {
                            NotificationCenter.default.post(name: Notification.Name("kutana-request-login"), object: nil)
                        } label: {
                            Image(systemName: "bell")
                        }
                        .accessibilityLabel("Se connecter pour consulter les notifications")
                    }
                }
            }
            .navigationTitle("Emploi")
            .navigationBarTitleDisplayMode(.large)
            .task { await load(); await loadFavorites() }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("kutana-favorites-changed"))) { _ in
                Task { await loadFavorites() }
            }
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

    @MainActor private func loadFavorites() async {
        guard identity.authenticated, let config = identity.configuration,
              let token = await identity.freshAccessToken() else { favoriteIDs = []; return }
        if let favorites = try? await KutanaAPI(configuration: config).favorites(accessToken: token) {
            favoriteIDs = Set(favorites.map(\.job_id))
        }
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
    @State private var pendingAction: PendingAction?
    private enum PendingAction { case application, favorite }

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
                if !isMine && !preview {
                    Button {
                        if identity.authenticated {
                            Task { await toggleFavorite() }
                        } else {
                            pendingAction = .favorite
                            NotificationCenter.default.post(name: Notification.Name("kutana-request-login"), object: nil)
                        }
                    } label: {
                        Label(favorite ? "Retirer des favoris" : "Ajouter aux favoris", systemImage: favorite ? "bookmark.fill" : "bookmark")
                    }.disabled(favoriteBusy)
                    Text("Un favori crée aussi une alerte pour des offres similaires dans cette ville. Vous pouvez l'ajuster dans Profil.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if sent { Label("Candidature envoyée", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                KutanaPrimaryButton(title: sending ? "Envoi en cours…" : "Postuler à cette offre") {
                    if identity.authenticated {
                        Task { await apply() }
                    } else {
                        pendingAction = .application
                        NotificationCenter.default.post(name: Notification.Name("kutana-request-login"), object: nil)
                    }
                }
                .disabled(preview || sending || sent || isMine)
                if isMine {
                    Text("C'est votre offre : vous ne pouvez pas y postuler. Un autre compte candidat peut le faire.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if sent {
                    Text("Pour joindre votre CV PDF à cette candidature, ouvrez Profil, puis Mes candidatures.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if preview || !identity.authenticated {
                    Text(preview ? "Offre fictive : candidature désactivée." : "Connectez-vous pour postuler.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if !preview { LukaCommentsView(kind: "job", contentID: job.id, isOwner: isMine) }
            }.padding(20)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: "\(job.title) — \(job.company) · \(job.city) · \(job.contract_type)") {
                    Label("Partager l'offre", systemImage: "square.and.arrow.up")
                }
                .disabled(preview)
            }
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
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("kutana-login-cancelled"))) { _ in
            pendingAction = nil
        }
        .onChange(of: identity.authenticated) { _, authenticated in
            guard authenticated, let action = pendingAction else { return }
            pendingAction = nil
            guard !preview, !isMine else { return }
            Task {
                switch action {
                case .application:
                    await apply()
                case .favorite:
                    await loadFavorite()
                    if !favorite { await toggleFavorite() }
                }
            }
        }
    }

    @MainActor private func loadFavorite() async {
        guard identity.authenticated, !preview, let config = identity.configuration,
              let token = await identity.freshAccessToken() else { return }
        do { favorite = try await KutanaAPI(configuration: config).favorites(accessToken: token).contains { $0.job_id == job.id } }
        catch { errorMessage = "Impossible de charger les favoris." }
    }

    @MainActor private func toggleFavorite() async {
        guard let config = identity.configuration, let token = await identity.freshAccessToken(),
              let userID = AccessTokenMetadata.subject(token) else {
            errorMessage = "Reconnectez-vous pour modifier vos favoris."
            return
        }
        favoriteBusy = true
        defer { favoriteBusy = false }
        let api = KutanaAPI(configuration: config)
        let adding = !favorite
        do {
            if adding { try await api.addFavorite(jobID: job.id, userID: userID, accessToken: token) }
            else { try await api.removeFavorite(jobID: job.id, accessToken: token) }
            favorite = adding
            errorMessage = nil
            NotificationCenter.default.post(name: Notification.Name("kutana-favorites-changed"), object: nil)
        } catch {
            errorMessage = "Impossible de modifier les favoris."
            return
        }
        if adding {
            let terms = job.title.split(separator: " ").prefix(2).joined(separator: " ")
            if terms.count >= 2 {
                do { try await api.addAlert(keyword: terms, city: job.city, userID: userID, accessToken: token) }
                catch { errorMessage = "Favori enregistré, mais l'alerte n'a pas pu être créée." }
            }
        }
    }

    private var isMine: Bool {
        guard let token = identity.active?.token.access_token,
              let ownID = AccessTokenMetadata.subject(token) else { return false }
        return job.author_id == ownID
    }

    @MainActor private func apply() async {
        guard let configuration = identity.configuration else {
            errorMessage = "Le service est momentanément indisponible."
            return
        }
        guard let token = await identity.freshAccessToken() else {
            if !identity.authenticated {
                pendingAction = .application
                NotificationCenter.default.post(name: Notification.Name("kutana-request-login"), object: nil)
            } else {
                errorMessage = "Connexion indisponible. Réessayez."
            }
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
