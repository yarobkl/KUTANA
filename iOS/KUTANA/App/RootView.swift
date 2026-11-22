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
                Section {
                    NavigationLink {
                        MyPublicationsView()
                    } label: {
                        Label("Mes publications", systemImage: "square.stack")
                    }
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
    @State private var publishing = false
    @State private var published = false
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
                    Label(published ? "Publication en ligne" : "Brouillon privé enregistré", systemImage: "checkmark.circle.fill")
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
                if let savedID, !published {
                    KutanaPrimaryButton(title: publishing ? "Mise en ligne…" : "Mettre en ligne") {
                        Task { await publish(id: savedID) }
                    }
                    .disabled(publishing || !identity.authenticated)
                }
            } footer: {
                Text("L'offre est privée tant que vous ne choisissez pas « Mettre en ligne ». Votre e-mail doit être vérifié.")
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

    @MainActor private func publish(id: UUID) async {
        guard let configuration = identity.configuration,
              let token = await identity.freshAccessToken() else {
            errorMessage = "Reconnectez-vous pour publier."
            return
        }
        publishing = true
        errorMessage = nil
        defer { publishing = false }
        do {
            _ = try await KutanaAPI(configuration: configuration).publishJob(id: id, accessToken: token)
            published = true
            NotificationCenter.default.post(name: Notification.Name("kutana-publications-changed"), object: nil)
        } catch {
            errorMessage = "Publication impossible. Vérifiez votre e-mail et réessayez."
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
    @State private var publishing = false
    @State private var published = false
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
                    Label(published ? "Publication en ligne" : "Brouillon privé enregistré", systemImage: "checkmark.circle.fill")
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
                if let savedID, !published {
                    KutanaPrimaryButton(title: publishing ? "Mise en ligne…" : "Mettre en ligne") {
                        Task { await publish(id: savedID) }
                    }
                    .disabled(publishing || !identity.authenticated)
                }
            } footer: {
                Text("L'annonce reste privée jusqu'à sa mise en ligne. Aucun paiement n'est réalisé dans KUTANA.")
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

    @MainActor private func publish(id: UUID) async {
        guard let configuration = identity.configuration,
              let token = await identity.freshAccessToken() else {
            errorMessage = "Reconnectez-vous pour publier."
            return
        }
        publishing = true
        errorMessage = nil
        defer { publishing = false }
        do {
            _ = try await KutanaAPI(configuration: configuration).publishListing(id: id, accessToken: token)
            published = true
            NotificationCenter.default.post(name: Notification.Name("kutana-publications-changed"), object: nil)
        } catch {
            errorMessage = "Publication impossible. Vérifiez votre e-mail et réessayez."
        }
    }

}


/// Owner dashboard: drafts stay private and can only be published through a
/// server-validated, authenticated RPC (never by direct UPDATE).
struct MyPublicationsView: View {
    @EnvironmentObject private var identity: KutanaSessionStore
    @State private var jobs: [JobRecord] = []
    @State private var listings: [ListingRecord] = []
    @State private var loading = false
    @State private var changingID: UUID?
    @State private var errorMessage: String?
    @State private var notice: String?

    var body: some View {
        List {
            if loading { ProgressView("Chargement de vos publications…") }
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
            }
            if let notice {
                Text(notice).font(.footnote).foregroundStyle(.green)
            }
            Section("Emploi") {
                ForEach(jobs) { job in
                    publicationRow(title: job.title, subtitle: "\(job.company) · \(job.city)",
                                   status: job.status, kind: "job", id: job.id)
                }
                if jobs.isEmpty && !loading {
                    Text("Aucune offre créée").foregroundStyle(.secondary)
                }
            }
            Section("Petites annonces") {
                ForEach(listings) { item in
                    publicationRow(title: item.title, subtitle: "\(KutanaFormat.xaf(item.price_xaf)) · \(item.city)",
                                   status: item.status, kind: "listing", id: item.id)
                }
                if listings.isEmpty && !loading {
                    Text("Aucune annonce créée").foregroundStyle(.secondary)
                }
            }
            Section {
                Text("Les brouillons sont privés. Une publication en ligne est visible par tous. Vous pouvez la retirer à tout moment.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Mes publications")
        .refreshable { await load() }
        .task { await load() }
    }

    @ViewBuilder private func publicationRow(title: String, subtitle: String, status: String,
                                             kind: String, id: UUID) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.headline)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            Text(statusLabel(status)).font(.caption).foregroundStyle(.secondary)
            if status == "draft" || status == "published" {
                Button(changingID == id ? "Traitement…" : (status == "draft" ? "Mettre en ligne" : "Retirer de la plateforme")) {
                    Task { await change(kind: kind, id: id, publishing: status == "draft") }
                }
                .disabled(changingID != nil)
                .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.vertical, 5)
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "draft": return "Brouillon privé"
        case "published": return "En ligne"
        case "closed": return "Offre clôturée"
        case "reserved": return "Réservée"
        case "sold": return "Vendue"
        case "archived": return "Annonce retirée"
        default: return status
        }
    }

    @MainActor private func load() async {
        guard let configuration = identity.configuration,
              let token = await identity.freshAccessToken(),
              let owner = AccessTokenMetadata.subject(token) else {
            errorMessage = "Connectez-vous pour retrouver vos publications."
            return
        }
        loading = true
        errorMessage = nil
        defer { loading = false }
        do {
            let api = KutanaAPI(configuration: configuration)
            jobs = try await api.myJobs(ownerID: owner, accessToken: token)
            listings = try await api.myListings(ownerID: owner, accessToken: token)
        } catch {
            errorMessage = "Impossible de récupérer vos publications."
        }
    }

    @MainActor private func change(kind: String, id: UUID, publishing: Bool) async {
        guard let configuration = identity.configuration,
              let token = await identity.freshAccessToken() else {
            errorMessage = "Votre session a expiré."
            return
        }
        changingID = id
        errorMessage = nil
        notice = nil
        defer { changingID = nil }
        do {
            let api = KutanaAPI(configuration: configuration)
            if publishing {
                if kind == "job" { _ = try await api.publishJob(id: id, accessToken: token) }
                else { _ = try await api.publishListing(id: id, accessToken: token) }
            } else {
                _ = try await api.withdrawPublication(kind: kind, id: id, accessToken: token)
            }
            await load()
            notice = publishing ? "Publication en ligne." : "Publication retirée."
            NotificationCenter.default.post(name: Notification.Name("kutana-publications-changed"), object: nil)
        } catch {
            errorMessage = publishing
                ? "Impossible de publier. Votre adresse e-mail doit être vérifiée."
                : "Impossible de retirer cette publication."
        }
    }
}
