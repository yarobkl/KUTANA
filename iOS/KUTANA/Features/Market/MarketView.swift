import SwiftUI

struct MarketView: View {
    let unreadCount: Int
    @EnvironmentObject private var identity: KutanaSessionStore
    @State private var listings: [ListingRecord] = []
    @State private var category = "Toutes"
    @State private var cityFilter: String?
    @State private var priceLimit: Int64?
    @State private var query = ""
    @State private var loading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?

    private let categories = ["Toutes", "Téléphones", "Informatique", "Électroménager", "Meubles", "Véhicules", "Mode", "Maison", "Matériel professionnel", "Autres"]

    private var visible: [ListingRecord] {
        listings.filter { item in
            let matchesCategory = category == "Toutes" || item.category == category
            let matchesQuery = query.isEmpty || [item.title, item.category, item.city, item.description]
                .contains { $0.localizedCaseInsensitiveContains(query) }
            return matchesCategory && matchesQuery &&
                (cityFilter == nil || item.city == cityFilter) &&
                (priceLimit.map { item.price_xaf <= $0 } ?? true)
        }
    }

    private var cities: [String] { Array(Set(listings.map(\.city))).sorted() }

    var body: some View {
        NavigationStack {
            List {
                discoveryControls
                resultsSection
            }
            .sensoryFeedback(.selection, trigger: category)
            .navigationTitle("Annonces")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { NotificationsView() } label: {
                        Image(systemName: unreadCount > 0 ? "bell.badge.fill" : "bell")
                    }
                    .accessibilityLabel(unreadCount > 0 ? "Notifications, \(unreadCount) non lues" : "Notifications")
                }
            }
            .refreshable { await load() }
            .task { await load() }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("kutana-publications-changed"))) { _ in
                Task { await load() }
            }
        }
    }

    private var discoveryControls: some View {
        Section {
            KutanaInlineSearch(text: $query, prompt: "Article, catégorie ou ville")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Menu {
                        ForEach(categories, id: \.self) { option in
                            Button(option) { category = option }
                        }
                    } label: {
                        KutanaFilterChip(title: category == "Toutes" ? "Catégorie" : category,
                                         symbol: "chevron.down", active: category != "Toutes")
                    }
                    Menu {
                        Button("Tous les lieux") { cityFilter = nil }
                        ForEach(cities, id: \.self) { city in
                            Button(city) { cityFilter = city }
                        }
                    } label: { KutanaFilterChip(title: cityFilter ?? "Lieu", symbol: "chevron.down", active: cityFilter != nil) }
                    Menu {
                        Button("Tous les prix") { priceLimit = nil }
                        ForEach([Int64(50_000), 100_000, 250_000, 500_000], id: \.self) { amount in
                            Button("Jusqu'à \(KutanaFormat.xaf(amount))") { priceLimit = amount }
                        }
                    } label: {
                        KutanaFilterChip(title: priceLimit.map { "≤ \(KutanaFormat.xaf($0))" } ?? "Prix",
                                         symbol: "chevron.down", active: priceLimit != nil)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
    }

    private var resultsSection: some View {
        Section("Annonces récentes") {
            if loading && !hasLoaded {
                ForEach(0..<4, id: \.self) { _ in
                    KutanaLoadingRow(withThumbnail: true)
                }
            }
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
            }
            if !loading || hasLoaded {
                ForEach(visible) { item in
                    NavigationLink {
                        ListingDetailView(item: item)
                    } label: {
                        listingRow(item)
                    }
                }
                if visible.isEmpty && !loading && hasLoaded {
                    ContentUnavailableView("Aucune annonce", systemImage: "tag",
                        description: Text(category != "Toutes" || cityFilter != nil || priceLimit != nil || !query.isEmpty ?
                            "Essayez d'autres critères de recherche." :
                            "Les annonces publiées apparaîtront ici."))
                }
            }
        }
    }

    private func listingRow(_ item: ListingRecord) -> some View {
        let url: URL?
        if let path = item.listing_images?.first?.storage_path {
            url = identity.configuration?.publicListingImageURL(path: path)
        } else {
            url = nil
        }
        return HStack(spacing: 14) {
            KutanaListingPhoto(url: url)
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title).font(.headline)
                Text(KutanaFormat.xaf(item.price_xaf))
                    .font(.headline).foregroundStyle(KutanaTheme.blue)
                Label("\(item.city) · \(item.category)", systemImage: "mappin")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
    }

    @MainActor private func load() async {
        guard let configuration = identity.configuration else { return }
        loading = true
        errorMessage = nil
        defer { loading = false; hasLoaded = true }
        do {
            listings = try await KutanaAPI(configuration: configuration).publishedListings()
        } catch {
            errorMessage = "Impossible de récupérer les annonces."
        }
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
