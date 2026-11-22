import SwiftUI

struct ApplicationsView: View {
    @EnvironmentObject private var identity: KutanaSessionStore
    @State private var applications: [ApplicationWithJob] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var openingConversation = false
    @State private var chatTarget: ChatTarget?

    private struct ChatTarget: Identifiable {
        let id: UUID
    }

    var body: some View {
        NavigationStack {
            List {
                if loading { ProgressView("Chargement des candidatures…") }
                if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
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
                        }
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
