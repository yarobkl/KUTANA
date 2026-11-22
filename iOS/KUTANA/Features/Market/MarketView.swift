import SwiftUI

struct MarketView: View {
    let unreadCount: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("kutana.marketSavedFavorites") private var storedFavorites = ""
    @State private var showFavoritesSheet = false
    @State private var favoritesOnly = false
    @State private var headerShown = false
    @State private var priceBand: PriceBand = .all

    private enum PriceBand: String, CaseIterable {
        case all = "Tous les prix"
        case low = "Moins de 50 000 FCFA"
        case medium = "50 000 à 200 000 FCFA"
        case high = "Plus de 200 000 FCFA"

        func matches(_ price: Int64) -> Bool {
            switch self {
            case .all: return true
            case .low: return price < 50_000
            case .medium: return (50_000...200_000).contains(price)
            case .high: return price > 200_000
            }
        }
    }

    private var savedIDs: Set<UUID> {
        Set(storedFavorites.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
    }

    private func toggleSaved(_ id: UUID) {
        var ids = savedIDs
        if ids.contains(id) { ids.remove(id) }
        else { ids.insert(id) }
        storedFavorites = ids.map(\.uuidString).sorted().joined(separator: ",")
    }
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
            let matchesCategory = category == "Toutes" || item.category == category
            let matchesQuery = query.isEmpty || [item.title, item.city, item.description]
                .contains { $0.localizedCaseInsensitiveContains(query) }
            return matchesCategory && matchesQuery && priceBand.matches(item.price_xaf)
                && (!favoritesOnly || savedIDs.contains(item.id))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                introduction
                resultsSection
            }
            .sensoryFeedback(.selection, trigger: category)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showFavoritesSheet) {
                favoritesSheet
            }
            .refreshable { await load() }
            .task { await load() }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("kutana-publications-changed"))) { _ in
                Task { await load() }
            }
        }
    }

    private var introduction: some View {
        Section {
            VStack(alignment: .leading, spacing: 17) {
                HStack {
                    Text("Annonces")
                        .font(.system(size: 36, weight: .bold))
                        .tracking(-1)
                    Spacer()
                    NavigationLink {
                        NotificationsView()
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "bell")
                                .font(.system(size: 27, weight: .regular))
                                .foregroundStyle(.primary)
                                .frame(width: 44, height: 44)
                            if unreadCount > 0 {
                                Circle()
                                    .fill(KutanaTheme.blue)
                                    .frame(width: 9, height: 9)
                                    .offset(x: 1, y: -1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(unreadCount > 0
                                        ? "Notifications, \(unreadCount) non lues"
                                        : "Notifications")
                }

                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                    TextField("Produit, vendeur ou ville", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                }
                .padding(.horizontal, 16)
                .frame(height: 54)
                .background(Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(Color(.separator).opacity(0.28), lineWidth: 1)
                }

                HStack(spacing: 8) {
                    Menu {
                        ForEach(categories, id: \.self) { option in
                            Button(option) { category = option }
                        }
                    } label: {
                        filterPill(category == "Toutes" ? "Catégorie" : category,
                                   symbol: "chevron.down")
                    }
                    Menu {
                        ForEach(PriceBand.allCases, id: \.self) { band in
                            Button(band.rawValue) { priceBand = band }
                        }
                    } label: {
                        filterPill(priceBand == .all ? "Prix" : "Prix choisi",
                                   symbol: "chevron.down")
                    }
                    Button {
                        showFavoritesSheet = true
                    } label: {
                        filterPill("Favoris", symbol: favoritesOnly ? "bookmark.fill" : "bookmark")
                            .foregroundStyle(favoritesOnly ? KutanaTheme.blue : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .opacity(headerShown || reduceMotion ? 1 : 0)
            .offset(y: headerShown || reduceMotion ? 0 : 8)
            .onAppear {
                if reduceMotion { headerShown = true }
                else { withAnimation(.easeOut(duration: 0.3)) { headerShown = true } }
            }
            .padding(.top, 8)
            .padding(.bottom, 5)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
    }

    private func filterPill(_ title: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            if symbol == "bookmark" || symbol == "bookmark.fill" {
                Image(systemName: symbol)
            }
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.83)
            if symbol == "chevron.down" {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .font(.subheadline.weight(.medium))
        .frame(maxWidth: .infinity, minHeight: 45)
        .padding(.horizontal, 9)
        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
        .overlay(Capsule().strokeBorder(Color(.separator).opacity(0.3), lineWidth: 1))
        .contentShape(Capsule())
    }

    private var favoritesSheet: some View {
        NavigationStack {
            List {
                Toggle("Afficher uniquement mes favoris", isOn: $favoritesOnly)
                Section("Enregistrer sur cet iPhone") {
                    ForEach(listings) { item in
                        Button {
                            toggleSaved(item.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title).foregroundStyle(.primary)
                                    Text(item.city).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: savedIDs.contains(item.id)
                                      ? "bookmark.fill" : "bookmark")
                                    .foregroundStyle(KutanaTheme.blue)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    if listings.isEmpty {
                        Text("Aucune annonce publiée à enregistrer.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Favoris")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { showFavoritesSheet = false }
                }
            }
        }
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
                        description: Text(identity.isConfigured ?
                            "Les annonces publiées apparaîtront ici." :
                            "La nouvelle base KUTANA n'est pas encore connectée."))
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
