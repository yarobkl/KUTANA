import SwiftUI

struct MarketView: View {
    @EnvironmentObject private var identity: KutanaSessionStore
    @State private var listings: [ListingRecord] = []
    @State private var category = "Toutes"
    @State private var loading = false
    @State private var errorMessage: String?
    private let categories = ["Toutes", "Téléphones", "Informatique", "Électroménager", "Meubles", "Véhicules", "Mode", "Maison", "Matériel professionnel", "Autres"]

    private var visible: [ListingRecord] {
        category == "Toutes" ? listings : listings.filter { $0.category == category }
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
                Section("Catégories") {
                    Picker("Catégorie", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0) }
                    }.pickerStyle(.menu)
                }
                Section("Annonces récentes") {
                    if loading { ProgressView("Chargement des annonces…") }
                    if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                    ForEach(visible) { item in
                        NavigationLink {
                            ListingDetailView(item: item)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.title).font(.headline)
                                Text(KutanaFormat.xaf(item.price_xaf))
                                    .font(.headline).foregroundStyle(KutanaTheme.blue)
                                Label("\(item.city) · \(item.category)", systemImage: "mappin")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 5)
                        }
                    }
                    if visible.isEmpty && !loading {
                        ContentUnavailableView("Aucune annonce", systemImage: "tag",
                            description: Text(identity.isConfigured ? "Les annonces publiées apparaîtront ici." : "La nouvelle base KUTANA n'est pas encore connectée."))
                    }
                }
            }
            .navigationTitle("Annonces")
            .refreshable { await load() }
            .task { await load() }
        }
    }

    @MainActor private func load() async {
        guard let configuration = identity.configuration else { return }
        loading = true; errorMessage = nil
        defer { loading = false }
        do { listings = try await KutanaAPI(configuration: configuration).publishedListings() }
        catch { errorMessage = "Impossible de récupérer les annonces." }
    }
}

private struct ListingDetailView: View {
    let item: ListingRecord
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(item.title).font(.largeTitle.bold())
                Text(KutanaFormat.xaf(item.price_xaf))
                    .font(.title2.bold()).foregroundStyle(KutanaTheme.blue)
                Label("\(item.city) · \(item.category)", systemImage: "mappin")
                    .foregroundStyle(.secondary)
                Divider()
                Text("Description").font(.title2.bold())
                Text(item.description)
                Text("La messagerie sécurisée sera disponible après la mise en place des conversations liées aux annonces.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(20)
        }.navigationBarTitleDisplayMode(.inline)
    }
}
