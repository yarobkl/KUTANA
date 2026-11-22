import SwiftUI

struct MarketView: View {
    @EnvironmentObject private var identity: KutanaSessionStore
    @State private var listings: [ListingRecord] = []
    @State private var category = "Toutes"
    @State private var query = ""
    @State private var loading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?
    private let categories = ["Toutes", "Téléphones", "Informatique", "Électroménager", "Meubles", "Véhicules", "Mode", "Maison", "Matériel professionnel", "Autres"]

    private var visible: [ListingRecord] {
        listings.filter { item in
            (category == "Toutes" || item.category == category) &&
            (query.isEmpty || [item.title, item.city, item.description].contains {
                $0.localizedCaseInsensitiveContains(query)
            })
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Achetez et vendez au Congo").font(.title.bold())
                        Text("Prix en FCFA · Contact direct · Aucun paiement dans l’app")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                }
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(categories, id: \.self) { option in
                                Button {
                                    withAnimation(KutanaMotion.quick) { category = option }
                                } label: {
                                    Text(option)
                                        .font(.subheadline.weight(category == option ? .semibold : .medium))
                                        .foregroundStyle(category == option ? .white : .primary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(
                                            category == option ? KutanaTheme.blue : Color(.secondarySystemGroupedBackground),
                                            in: Capsule()
                                        )
                                }
                                .buttonStyle(KutanaPressStyle())
                                .accessibilityAddTraits(category == option ? .isSelected : [])
                            }
                        }
                        .padding(.vertical, 3)
                    }
                    .contentMargins(.horizontal, 2)
                } header: {
                    Text("Explorer par catégorie")
                }
                Section("Annonces récentes") {
                    if loading && !hasLoaded {
                        ForEach(0..<4, id: \.self) { _ in
                            KutanaLoadingRow(withThumbnail: true)
                        }
                    }
                    if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                    if !loading || hasLoaded {
                    ForEach(visible) { item in
                        NavigationLink {
                            ListingDetailView(item: item)
                        } label: {
                            HStack(spacing: 14) {
                                KutanaListingPhoto(
                                    url: item.listing_images?.first?.storage_path
                                        .flatMap { identity.configuration?.publicListingImageURL(path: $0) }
                                )
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.title).font(.headline)
                                    Text(KutanaFormat.xaf(item.price_xaf))
                                        .font(.headline).foregroundStyle(KutanaTheme.blue)
                                    Label("\(item.city) · \(item.category)", systemImage: "mappin")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 5)
                        }
                    }
                    if visible.isEmpty && !loading && hasLoaded {
                        ContentUnavailableView("Aucune annonce", systemImage: "tag",
                            description: Text(identity.isConfigured ? "Les annonces publiées apparaîtront ici." : "La nouvelle base KUTANA n'est pas encore connectée."))
                    }
                    }
                }
            }
            .searchable(text: $query, prompt: "Article, ville, description…")
            .sensoryFeedback(.selection, trigger: category)
            .navigationTitle("Annonces")
            .refreshable { await load() }
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
        do { listings = try await KutanaAPI(configuration: configuration).publishedListings() }
        catch { errorMessage = "Impossible de récupérer les annonces." }
    }
}

private struct ListingDetailView: View {
    let item: ListingRecord
    @EnvironmentObject private var identity: KutanaSessionStore
    @State private var contacting = false
    @State private var showChat = false
    @State private var conversationID: UUID?
    @State private var errorMessage: String?
    @State private var showReport = false
    @State private var photos: [ListingImageRecord] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !photos.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(photos) { photo in
                                if let url = identity.configuration?.publicListingImageURL(path: photo.storage_path) {
                                    KutanaListingPhoto(url: url, width: 285, height: 225)
                                }
                            }
                        }
                    }
                }
                Text(item.title).font(.largeTitle.bold())
                Text(KutanaFormat.xaf(item.price_xaf))
                    .font(.title2.bold()).foregroundStyle(KutanaTheme.blue)
                Label("\(item.city) · \(item.category)", systemImage: "mappin")
                    .foregroundStyle(.secondary)
                Divider()
                Text("Description").font(.title2.bold())
                Text(item.description)
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
                KutanaPrimaryButton(title: contacting ? "Ouverture…" : "Contacter le vendeur") {
                    Task { await contactSeller() }
                }
                .disabled(contacting || !identity.authenticated || isMine)
                if !identity.authenticated {
                    Text("Connectez-vous pour contacter le vendeur en privé.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if isMine {
                    Text("C'est votre annonce.").font(.footnote).foregroundStyle(.secondary)
                }
            }.padding(20)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showChat) {
            if let conversationID {
                KutanaChatView(conversationID: conversationID)
            }
        }
        .task { await loadPhotos() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Signaler", systemImage: "flag") { showReport = true }
                    .disabled(!identity.authenticated || isMine)
            }
        }
        .sheet(isPresented: $showReport) {
            ReportContentSheet(kind: "listing", contentID: item.id)
                .environmentObject(identity)
        }
    }


    @MainActor private func loadPhotos() async {
        guard let configuration = identity.configuration else { return }
        do {
            photos = try await KutanaAPI(configuration: configuration).listingImages(listingID: item.id)
        } catch {
            // The text-only listing remains usable if images temporarily fail.
        }
    }

    private var isMine: Bool {
        guard let token = identity.active?.token.access_token,
              let ownID = AccessTokenMetadata.subject(token) else { return false }
        return item.seller_id == ownID
    }

    @MainActor private func contactSeller() async {
        guard let configuration = identity.configuration,
              let token = await identity.freshAccessToken() else {
            errorMessage = "Connectez-vous pour contacter le vendeur."
            return
        }
        contacting = true
        errorMessage = nil
        defer { contacting = false }
        do {
            conversationID = try await KutanaAPI(configuration: configuration)
                .startListingConversation(listingID: item.id, accessToken: token)
            showChat = true
        } catch {
            errorMessage = "Impossible de démarrer la conversation."
        }
    }
}
