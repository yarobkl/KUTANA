import SwiftUI

struct RootView: View {
    @EnvironmentObject private var identity: KutanaSessionStore
    @State private var selection = 0
    var body: some View {
        TabView(selection: $selection) {
            JobsView().tabItem { Label("Emploi", systemImage: "briefcase") }.tag(0)
            MarketView().tabItem { Label("Annonces", systemImage: "tag") }.tag(1)
            PublishView().tabItem { Label("Publier", systemImage: "plus.square") }.tag(2)
            MessagesView().tabItem { Label("Messages", systemImage: "bubble.left.and.bubble.right") }.tag(3)
            ProfileView().tabItem { Label("Profil", systemImage: "person.crop.circle") }.tag(4)
        }
        .tint(KutanaTheme.blue)
    }
}

struct PublishView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Préparez votre publication. Elle restera privée tant qu'un parcours de vérification et de publication n'aura pas été validé.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section("Créer un brouillon") {
                    NavigationLink {
                        JobDraftFormView()
                    } label: {
                        Label("Offre d’emploi", systemImage: "briefcase")
                    }
                    NavigationLink {
                        ListingDraftFormView()
                    } label: {
                        Label("Petite annonce", systemImage: "tag")
                    }
                }
            }
            .navigationTitle("Publier")
        }
    }
}

private struct JobDraftFormView: View {
    @EnvironmentObject private var identity: KutanaSessionStore
    @State private var title = ""
    @State private var company = ""
    @State private var city = "Brazzaville"
    @State private var contract = "CDI"
    @State private var description = ""
    @State private var saving = false
    @State private var savedID: UUID?
    @State private var errorMessage: String?

    private let contractTypes = ["CDI", "CDD", "Stage", "Alternance", "Intérim", "Freelance", "Autre"]

    var body: some View {
        Form {
            Section("Entreprise et poste") {
                TextField("Intitulé du poste", text: $title)
                TextField("Nom de l'entreprise", text: $company)
                TextField("Ville", text: $city)
                Picker("Contrat", selection: $contract) {
                    ForEach(contractTypes, id: \.self) { Text($0) }
                }
                TextField("Décrivez les missions, le profil et les conditions…", text: $description, axis: .vertical)
                    .lineLimit(5...12)
            }
            Section {
                if let savedID {
                    Label("Brouillon privé enregistré", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Référence : \(savedID.uuidString)").font(.caption2).textSelection(.enabled)
                }
                if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                if !identity.isConfigured {
                    Text("Le serveur KUTANA indépendant n'est pas encore configuré.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                KutanaPrimaryButton(title: saving ? "Enregistrement…" : "Enregistrer le brouillon") {
                    Task { await save() }
                }.disabled(!identity.authenticated || !identity.isConfigured || saving || savedID != nil)
            } footer: {
                Text("Votre offre n'est pas publique. La publication sera possible après validation du parcours de modération.")
            }
        }
        .navigationTitle("Nouvelle offre")
        .navigationBarTitleDisplayMode(.inline)
    }

    @MainActor private func save() async {
        saving = true; errorMessage = nil
        defer { saving = false }
        do {
            let input = try JobDraftInput(title: title, company: company, city: city,
                                          contract: contract, description: description)
            guard let configuration = identity.configuration,
                  let accessToken = await identity.freshAccessToken() else {
                errorMessage = "Connectez-vous pour enregistrer le brouillon."
                return
            }
            savedID = try await KutanaAPI(configuration: configuration)
                .createJobDraft(input, accessToken: accessToken)
        } catch {
            errorMessage = error is DraftValidationError ? error.localizedDescription :
                "Enregistrement impossible. Vérifiez votre connexion et réessayez."
        }
    }
}

private struct ListingDraftFormView: View {
    @EnvironmentObject private var identity: KutanaSessionStore
    @State private var title = ""
    @State private var category = "Téléphones"
    @State private var city = "Brazzaville"
    @State private var description = ""
    @State private var price = ""
    @State private var saving = false
    @State private var savedID: UUID?
    @State private var errorMessage: String?
    private let categories = ["Téléphones", "Informatique", "Électroménager", "Meubles", "Véhicules", "Mode", "Maison", "Matériel professionnel", "Autres"]

    var body: some View {
        Form {
            Section("Votre article") {
                TextField("Titre de l'annonce", text: $title)
                Picker("Catégorie", selection: $category) {
                    ForEach(categories, id: \.self) { Text($0) }
                }
                TextField("Ville", text: $city)
                TextField("Prix en FCFA", text: $price).keyboardType(.numberPad)
                TextField("État, caractéristiques, accessoires…", text: $description, axis: .vertical)
                    .lineLimit(5...12)
            }
            Section {
                if let savedID {
                    Label("Brouillon privé enregistré", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Référence : \(savedID.uuidString)").font(.caption2).textSelection(.enabled)
                }
                if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                if !identity.isConfigured {
                    Text("Le serveur KUTANA indépendant n'est pas encore configuré.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                KutanaPrimaryButton(title: saving ? "Enregistrement…" : "Enregistrer le brouillon") {
                    Task { await save() }
                }.disabled(!identity.authenticated || !identity.isConfigured || saving || savedID != nil)
            } footer: {
                Text("Annonce privée jusqu'à sa vérification. Aucun paiement n'est réalisé dans KUTANA.")
            }
        }
        .navigationTitle("Nouvelle annonce")
        .navigationBarTitleDisplayMode(.inline)
    }

    @MainActor private func save() async {
        saving = true; errorMessage = nil
        defer { saving = false }
        do {
            let input = try ListingDraftInput(category: category, title: title,
                                              description: description, city: city, price: price)
            guard let configuration = identity.configuration,
                  let accessToken = await identity.freshAccessToken() else {
                errorMessage = "Connectez-vous pour enregistrer le brouillon."
                return
            }
            savedID = try await KutanaAPI(configuration: configuration)
                .createListingDraft(input, accessToken: accessToken)
        } catch {
            errorMessage = error is DraftValidationError ? error.localizedDescription :
                "Enregistrement impossible. Vérifiez votre connexion et réessayez."
        }
    }
}
