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
