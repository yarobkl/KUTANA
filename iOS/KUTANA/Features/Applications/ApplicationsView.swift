import SwiftUI
import UniformTypeIdentifiers
import QuickLook

struct ApplicationsView: View {
    @EnvironmentObject private var identity: KutanaSessionStore
    @State private var applications: [ApplicationWithJob] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var openingConversation = false
    @State private var chatTarget: ChatTarget?
    @State private var cvTarget: UUID?
    @State private var showImporter = false
    @State private var uploadingCV = false
    @State private var cvPreview: URL?
    @State private var notice: String?

    private struct ChatTarget: Identifiable {
        let id: UUID
    }

    var body: some View {
        NavigationStack {
            List {
                if loading { ProgressView("Chargement des candidatures…") }
                if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                if let notice { Text(notice).font(.footnote).foregroundStyle(.green) }
                ForEach(applications) { item in
                    VStack(alignment: .leading, spacing: 7) {
                        Text(item.jobs?.title ?? "Offre indisponible").font(.headline)
                        if let company = item.jobs?.company { Text(company).font(.subheadline) }
                        Text(item.status.frenchLabel)
                            .font(.subheadline.bold()).foregroundStyle(KutanaTheme.blue)
                        Button {
                            Task { await openConversation(for: item.id) }
                        } label: {
                            Label("Échanger avec le recruteur", systemImage: "bubble.left")
                                .font(.subheadline)
                        }.disabled(openingConversation)
                        HStack(spacing: 18) {
                            Button(uploadingCV ? "Ajout du CV…" : "Joindre ou remplacer un CV") {
                                cvTarget = item.id
                                showImporter = true
                            }
                            .disabled(uploadingCV)
                            .font(.subheadline)
                            Button("Voir le CV") {
                                Task { await openCV(for: item.id) }
                            }
                            .font(.subheadline)
                        }
                    }.padding(.vertical, 8)
                }
                if applications.isEmpty && !loading {
                    ContentUnavailableView("Aucune candidature", systemImage: "doc.text.magnifyingglass",
                        description: Text("Vos candidatures et leur statut apparaîtront ici."))
                }
            }
            .navigationTitle("Mes candidatures")
            .refreshable { await load() }
            .task { await load() }
            .sheet(item: $chatTarget) { target in
                NavigationStack {
                    KutanaChatView(conversationID: target.id)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Fermer") { chatTarget = nil }
                            }
                        }
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf]) { result in
                guard let cvTarget else { return }
                switch result {
                case .success(let url):
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    guard let data = try? Data(contentsOf: url) else {
                        errorMessage = "Impossible de lire le fichier PDF."
                        return
                    }
                    Task { await uploadCV(data, filename: url.lastPathComponent, applicationID: cvTarget) }
                case .failure:
                    errorMessage = "Sélection du fichier annulée ou impossible."
                }
            }
            .quickLookPreview($cvPreview)
            .onChange(of: cvPreview) { oldURL, newURL in
                if newURL == nil, let oldURL {
                    try? FileManager.default.removeItem(at: oldURL)
                }
            }
        }
    }

    @MainActor private func openConversation(for applicationID: UUID) async {
        guard let configuration = identity.configuration,
              let token = await identity.freshAccessToken() else {
            errorMessage = "Connectez-vous pour ouvrir une conversation."
            return
        }
        openingConversation = true
        errorMessage = nil
        defer { openingConversation = false }
        do {
            let id = try await KutanaAPI(configuration: configuration)
                .startApplicationConversation(applicationID: applicationID, accessToken: token)
            chatTarget = ChatTarget(id: id)
        } catch {
            errorMessage = "Impossible d’ouvrir cette conversation."
        }
    }


    @MainActor private func uploadCV(_ pdf: Data, filename: String, applicationID: UUID) async {
        guard let configuration = identity.configuration,
              let token = await identity.freshAccessToken(),
              let owner = AccessTokenMetadata.subject(token) else {
            errorMessage = "Reconnectez-vous avant d'ajouter votre CV."
            return
        }
        uploadingCV = true
        errorMessage = nil
        notice = nil
        defer { uploadingCV = false }
        do {
            _ = try await KutanaAPI(configuration: configuration)
                .uploadApplicationCV(pdf, filename: filename, applicationID: applicationID,
                                     ownerID: owner, accessToken: token)
            notice = "Votre CV PDF a été enregistré et joint à la candidature."
        } catch {
            errorMessage = "CV refusé. Vérifiez qu'il s'agit d'un PDF de moins de 5 Mo."
        }
    }

    @MainActor private func openCV(for applicationID: UUID) async {
        guard let configuration = identity.configuration,
              let token = await identity.freshAccessToken() else {
            errorMessage = "Connectez-vous pour ouvrir votre CV."
            return
        }
        errorMessage = nil
        do {
            let api = KutanaAPI(configuration: configuration)
            guard let cv = try await api.applicationCV(applicationID: applicationID, accessToken: token) else {
                errorMessage = "Aucun CV joint à cette candidature."
                return
            }
            cvPreview = try await api.downloadApplicationCV(cv, accessToken: token)
        } catch {
            errorMessage = "Le CV ne peut pas être ouvert."
        }
    }

    @MainActor private func load() async {
        guard let configuration = identity.configuration,
              let token = await identity.freshAccessToken() else { return }
        loading = true; errorMessage = nil
        defer { loading = false }
        do { applications = try await KutanaAPI(configuration: configuration).myApplications(accessToken: token) }
        catch { errorMessage = "Impossible de charger les candidatures." }
    }
}


/// An employer can see only the applications to their own jobs.
/// PostgreSQL checks the recruiter identity on every read and status update.
struct ReceivedApplicationsView: View {
    @EnvironmentObject private var identity: KutanaSessionStore
    @State private var received: [RecruiterApplication] = []
    @State private var loading = false
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var notice: String?
    @State private var chatTarget: ChatTarget?
    @State private var pendingID: UUID?
    @State private var pendingStatus: ApplicationState?
    @State private var showConfirmation = false
    @State private var cvPreview: URL?
    @State private var locationMessage: String?
    @State private var showLocation = false

    private struct ChatTarget: Identifiable {
        let id: UUID
    }

    var body: some View {
        NavigationStack {
            List {
                if loading { ProgressView("Chargement des candidatures reçues…") }
                if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                if let notice { Text(notice).font(.footnote).foregroundStyle(.green) }
                ForEach(received) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.job_title).font(.headline)
                        Text(item.company).font(.subheadline).foregroundStyle(.secondary)
                        Text("Candidature : \(item.candidate_name)")
                            .font(.subheadline)
                        Label(item.status.frenchLabel, systemImage: "person.text.rectangle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(KutanaTheme.blue)
                        Text(item.created_at, style: .date)
                            .font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 16) {
                            Menu {
                                ForEach(ApplicationState.allCases.filter { $0 != .submitted }, id: \.self) { next in
                                    Button(next.frenchLabel) {
                                        pendingID = item.id
                                        pendingStatus = next
                                        showConfirmation = true
                                    }
                                }
                            } label: {
                                Label("Statut", systemImage: "arrow.triangle.2.circlepath")
                                    .font(.subheadline)
                            }
                            .disabled(busy || item.status == .hired || item.status == .rejected)
                            Button {
                                Task { await openConversation(for: item.id) }
                            } label: {
                                Label("Échanger", systemImage: "bubble.left")
                                    .font(.subheadline)
                            }
                            .disabled(busy)
                            Button {
                                Task { await openCV(for: item.id) }
                            } label: {
                                Label("CV PDF", systemImage: "doc.text")
                                    .font(.subheadline)
                            }
                            .disabled(busy)
                        }
                        Button {
                            Task { await openLocation(for: item.id) }
                        } label: {
                            Label("Localisation partagée", systemImage: "mappin.and.ellipse")
                                .font(.subheadline)
                        }
                        .disabled(busy)
                    }
                    .padding(.vertical, 8)
                }
                if received.isEmpty && !loading {
                    ContentUnavailableView("Aucune candidature reçue", systemImage: "person.crop.rectangle.stack",
                        description: Text("Les candidatures à vos offres publiées apparaîtront ici."))
                }
            }
            .navigationTitle("Candidatures reçues")
            .refreshable { await load() }
            .task { await load() }
            .confirmationDialog("Modifier le statut de cette candidature ?", isPresented: $showConfirmation) {
                Button("Confirmer") {
                    if let pendingID, let pendingStatus {
                        Task { await changeStatus(id: pendingID, next: pendingStatus) }
                    }
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("La décision sera enregistrée dans l'historique du recrutement. Une décision finale ne pourra pas être annulée.")
            }
            .sheet(item: $chatTarget) { target in
                NavigationStack {
                    KutanaChatView(conversationID: target.id)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Fermer") { chatTarget = nil }
                            }
                        }
                }
            }
            .alert("Localisation du candidat", isPresented: $showLocation) {
                Button("Fermer", role: .cancel) {}
            } message: {
                Text(locationMessage ?? "")
            }
            .quickLookPreview($cvPreview)
            .onChange(of: cvPreview) { oldURL, newURL in
                if newURL == nil, let oldURL {
                    try? FileManager.default.removeItem(at: oldURL)
                }
            }
        }
    }


    @MainActor private func openLocation(for applicationID: UUID) async {
        guard let configuration = identity.configuration,
              let token = await identity.freshAccessToken() else {
            errorMessage = "Reconnectez-vous pour consulter la localisation."
            return
        }
        busy = true
        defer { busy = false }
        do {
            let location = try await KutanaAPI(configuration: configuration)
                .sharedApplicationLocation(applicationID: applicationID, accessToken: token)
            if let location {
                let country = Locale.current.localizedString(forRegionCode: location.country_code) ?? location.country_code
                locationMessage = "\(location.commune), \(location.city), \(country)"
            } else {
                locationMessage = "Le candidat n’a pas partagé sa localisation."
            }
            showLocation = true
        } catch {
            errorMessage = "Impossible de consulter la localisation."
        }
    }

    @MainActor private func openCV(for applicationID: UUID) async {
        guard let configuration = identity.configuration,
              let token = await identity.freshAccessToken() else {
            errorMessage = "Connectez-vous pour consulter le CV."
            return
        }
        errorMessage = nil
        do {
            let api = KutanaAPI(configuration: configuration)
            guard let cv = try await api.applicationCV(applicationID: applicationID, accessToken: token) else {
                errorMessage = "Le candidat n'a pas encore joint de CV."
                return
            }
            cvPreview = try await api.downloadApplicationCV(cv, accessToken: token)
        } catch {
            errorMessage = "Accès au CV refusé ou téléchargement impossible."
        }
    }

    @MainActor private func load() async {
        guard let configuration = identity.configuration,
              let token = await identity.freshAccessToken() else {
            errorMessage = "Connectez-vous pour consulter les candidatures reçues."
            return
        }
        loading = true
        errorMessage = nil
        defer { loading = false }
        do {
            received = try await KutanaAPI(configuration: configuration)
                .receivedApplications(accessToken: token)
        } catch {
            errorMessage = "Impossible de charger les candidatures reçues."
        }
    }

    @MainActor private func changeStatus(id: UUID, next: ApplicationState) async {
        guard let configuration = identity.configuration,
              let token = await identity.freshAccessToken() else {
            errorMessage = "Reconnectez-vous pour gérer les candidatures."
            return
        }
        busy = true
        errorMessage = nil
        notice = nil
        defer { busy = false }
        do {
            try await KutanaAPI(configuration: configuration)
                .changeApplicationStatus(id: id, next: next, accessToken: token)
            await load()
            notice = "Statut de candidature mis à jour."
        } catch {
            errorMessage = "Changement de statut refusé ou impossible."
        }
    }

    @MainActor private func openConversation(for applicationID: UUID) async {
        guard let configuration = identity.configuration,
              let token = await identity.freshAccessToken() else {
            errorMessage = "Connectez-vous pour échanger."
            return
        }
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            let id = try await KutanaAPI(configuration: configuration)
                .startApplicationConversation(applicationID: applicationID, accessToken: token)
            chatTarget = ChatTarget(id: id)
        } catch {
            errorMessage = "Impossible d'ouvrir la conversation."
        }
    }
}
