import SwiftUI
import PhotosUI
import UIKit
import UserNotifications

struct RootView: View {
    var allowNotificationPrompt = false
    @EnvironmentObject private var identity: KutanaSessionStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("kutana.notificationPromptSeen") private var notificationPromptSeen = false
    @State private var selection = 0
    @State private var unreadNotifications = 0
    @State private var showingNotificationPrompt = false
    @State private var knownNotificationIDs: Set<UUID> = []
    @State private var hasNotificationSnapshot = false
    var body: some View {
        TabView(selection: $selection) {
            JobsView(unreadCount: unreadNotifications).modifier(KutanaTabEntrance())
                .tabItem { Label("Emploi", systemImage: "briefcase") }.tag(0)
            MarketView(unreadCount: unreadNotifications).modifier(KutanaTabEntrance())
                .tabItem { Label("Annonces", systemImage: "tag") }.tag(1)
            PublishView().modifier(KutanaTabEntrance())
                .tabItem { Label("Publier", systemImage: "plus.square") }.tag(2)
            MessagesView().modifier(KutanaTabEntrance())
                .tabItem { Label("Messages", systemImage: "bubble.left.and.bubble.right") }.tag(3)
            ProfileView().modifier(KutanaTabEntrance())
                .tabItem { Label("Profil", systemImage: "person.crop.circle") }
                .badge(unreadNotifications).tag(4)
        }
        .tint(KutanaTheme.blue)
        .sensoryFeedback(.selection, trigger: selection)
        .task {
            while !Task.isCancelled {
                if scenePhase == .active { await refreshUnread() }
                try? await Task.sleep(for: .seconds(25))
            }
        }
        .onChange(of: selection) { _, _ in Task { await refreshUnread() } }
        .onAppear { offerNotificationPrompt() }
        .onChange(of: allowNotificationPrompt) { _, _ in offerNotificationPrompt() }
        .alert("Rester informé sur KUTANA ?", isPresented: $showingNotificationPrompt) {
            Button("Activer") {
                notificationPromptSeen = true
                Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) }
            }
            Button("Plus tard", role: .cancel) { notificationPromptSeen = true }
        } message: {
            Text("Recevez une alerte quand de nouveaux messages ou des offres suivies arrivent pendant que l'application est ouverte. Vous pourrez modifier ce choix dans les réglages iPhone.")
        }
    }

    private func offerNotificationPrompt() {
        if allowNotificationPrompt && identity.authenticated && !notificationPromptSeen {
            showingNotificationPrompt = true
        }
    }

    @MainActor private func refreshUnread() async {
        guard identity.authenticated, let config = identity.configuration,
              let token = await identity.freshAccessToken() else {
            unreadNotifications = 0; return
        }
        if let items = try? await KutanaAPI(configuration: config).notifications(accessToken: token) {
            unreadNotifications = items.filter { $0.read_at == nil }.count
            let newItems = hasNotificationSnapshot ? items.filter { !knownNotificationIDs.contains($0.id) } : []
            knownNotificationIDs = Set(items.map(\.id))
            hasNotificationSnapshot = true
            for item in newItems.prefix(3) { await presentLocalNotification(item) }
        }
    }

    private func presentLocalNotification(_ item: KutanaNotification) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.body
        content.sound = .default
        let request = UNNotificationRequest(identifier: item.id.uuidString, content: content, trigger: nil)
        try? await center.add(request)
    }
}

struct PublishView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        JobDraftFormView()
                    } label: {
                        publishOption("Offre d’emploi", symbol: "briefcase")
                    }
                    NavigationLink {
                        ListingDraftFormView()
                    } label: {
                        publishOption("Petite annonce", symbol: "tag")
                    }
                }

                Section {
                    NavigationLink {
                        MyPublicationsView()
                    } label: {
                        publishOption("Mes publications", symbol: "square.stack")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Créer")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private func publishOption(_ title: String, symbol: String) -> some View {
        HStack(spacing: 15) {
            Image(systemName: symbol)
                .font(.system(size: 23, weight: .regular))
                .foregroundStyle(KutanaTheme.blue)
                .frame(width: 30)
                .accessibilityHidden(true)
            Text(title).font(.headline).foregroundStyle(.primary)
                .padding(.vertical, 12)
        }
        .accessibilityElement(children: .combine)
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
            Section("Photos") {
                if let savedID, !published {
                    ListingPhotoUploader(listingID: savedID)
                } else if savedID == nil {
                    Text("Enregistrez le brouillon pour ajouter les photos.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
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
                Text("L'annonce reste privée jusqu'à sa mise en ligne. Elle sera visible pendant 30 jours, puis conservée dans vos archives. Aucun paiement n'est réalisé dans KUTANA.")
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
            errorMessage = "Publication impossible. Vérifiez votre e-mail et ajoutez au moins une photo."
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
                ForEach(listings.filter { $0.status != "archived" }) { item in
                    listingRow(item)
                }
                if listings.allSatisfy({ $0.status == "archived" }) && !loading {
                    Text("Aucune annonce créée").foregroundStyle(.secondary)
                }
            }
            Section("Archives") {
                ForEach(listings.filter { $0.status == "archived" }) { item in
                    listingRow(item)
                }
            }
            Section {
                Text("Les brouillons et archives sont privés. Une annonce vendue reste visible avec la mention « Vendu ».")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Mes publications")
        .refreshable { await load() }
        .task { await load() }
    }

    private func listingRow(_ item: ListingRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.title).font(.headline)
            Text("\(KutanaFormat.xaf(item.price_xaf)) · \(item.city)")
                .font(.subheadline).foregroundStyle(.secondary)
            Text(statusLabel(item.status)).font(.caption).foregroundStyle(.secondary)
            if (item.status == "published" || item.status == "sold"), let expiresAt = item.expires_at {
                Text("En ligne jusqu'au \(expiresAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if item.status == "sold" {
                Button("Retirer et archiver") {
                    Task { await changeListing(id: item.id, status: "archived") }
                }
                .disabled(changingID != nil)
            }
            if item.status != "sold" {
                NavigationLink("Modifier l'annonce") {
                    ListingEditView(item: item) { Task { await load() } }
                }
                NavigationLink("Gérer les photos") { ListingPhotoManagerView(listingID: item.id) }
                if item.status == "draft" {
                    Button("Mettre en ligne") {
                        Task { await change(kind: "listing", id: item.id, publishing: true) }
                    }
                    .disabled(changingID != nil)
                } else if item.status == "published" {
                    Button("Marquer comme vendu") {
                        Task { await changeListing(id: item.id, status: "sold") }
                    }
                    .disabled(changingID != nil)
                    Button("Retirer et archiver") {
                        Task { await changeListing(id: item.id, status: "archived") }
                    }
                    .disabled(changingID != nil)
                } else if item.status == "archived" {
                    Button("Remettre en ligne") {
                        Task { await changeListing(id: item.id, status: "published") }
                    }
                    .disabled(changingID != nil)
                }
            }
        }
        .padding(.vertical, 5)
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

    @MainActor private func changeListing(id: UUID, status: String) async {
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
            _ = try await KutanaAPI(configuration: configuration)
                .changeListingStatus(id: id, status: status, accessToken: token)
            await load()
            notice = status == "sold" ? "Article marqué comme vendu." :
                (status == "archived" ? "Annonce conservée dans vos archives." : "Annonce remise en ligne.")
            NotificationCenter.default.post(name: Notification.Name("kutana-publications-changed"), object: nil)
        } catch {
            errorMessage = "Impossible de modifier l'état de cette annonce. Réessayez."
        }
    }
}

private struct ListingEditView: View {
    let item: ListingRecord
    let onSaved: () -> Void
    @EnvironmentObject private var identity: KutanaSessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var category: String
    @State private var city: String
    @State private var price: String
    @State private var description: String
    @State private var saving = false
    @State private var errorMessage: String?

    init(item: ListingRecord, onSaved: @escaping () -> Void) {
        self.item = item
        self.onSaved = onSaved
        _title = State(initialValue: item.title)
        _category = State(initialValue: item.category)
        _city = State(initialValue: item.city)
        _price = State(initialValue: String(item.price_xaf))
        _description = State(initialValue: item.description)
    }

    var body: some View {
        Form {
            TextField("Titre de l'annonce", text: $title)
            Picker("Catégorie", selection: $category) {
                ForEach(["Téléphones", "Informatique", "Électroménager", "Meubles", "Véhicules", "Mode", "Maison", "Matériel professionnel", "Autres"], id: \.self) { Text($0) }
            }
            TextField("Ville", text: $city)
            TextField("Prix en FCFA", text: $price).keyboardType(.numberPad)
            TextField("Description", text: $description, axis: .vertical).lineLimit(5...12)
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            Button(saving ? "Enregistrement…" : "Enregistrer les modifications") {
                Task { await save() }
            }
            .disabled(saving)
        }
        .navigationTitle("Modifier l'annonce")
        .navigationBarTitleDisplayMode(.inline)
    }

    @MainActor private func save() async {
        saving = true
        errorMessage = nil
        defer { saving = false }
        do {
            let input = try ListingDraftInput(category: category, title: title,
                description: description, city: city, price: price)
            guard let configuration = identity.configuration,
                  let token = await identity.freshAccessToken() else {
                errorMessage = "Votre session a expiré."
                return
            }
            _ = try await KutanaAPI(configuration: configuration)
                .editListing(id: item.id, input: input, accessToken: token)
            onSaved()
            NotificationCenter.default.post(name: Notification.Name("kutana-publications-changed"), object: nil)
            dismiss()
        } catch {
            errorMessage = error is DraftValidationError ? error.localizedDescription :
                "Impossible d'enregistrer les modifications."
        }
    }
}


/// User-generated content moderation entry point, scoped to a published job or listing.
struct ReportContentSheet: View {
    let kind: String
    let contentID: UUID
    @EnvironmentObject private var identity: KutanaSessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var sending = false
    @State private var errorMessage: String?
    @State private var sent = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Pourquoi signalez-vous ce contenu ?") {
                    TextField("Décrivez le problème (10 caractères minimum)", text: $reason, axis: .vertical)
                        .lineLimit(4...8)
                }
                Section {
                    if let errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red)
                    }
                    if sent {
                        Label("Signalement transmis", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button(sending ? "Envoi en cours…" : "Envoyer le signalement") {
                            Task { await send() }
                        }
                        .disabled(sending || !(10...2000).contains(reason.trimmingCharacters(in: .whitespacesAndNewlines).count))
                    }
                } footer: {
                    Text("Les signalements sont examinés par l'équipe de modération. Aucun contenu n'est automatiquement retiré.")
                }
            }
            .navigationTitle("Signaler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    @MainActor private func send() async {
        guard let configuration = identity.configuration,
              let token = await identity.freshAccessToken() else {
            errorMessage = "Reconnectez-vous avant de signaler."
            return
        }
        sending = true
        errorMessage = nil
        defer { sending = false }
        do {
            _ = try await KutanaAPI(configuration: configuration)
                .reportContent(kind: kind, id: contentID, reason: reason, accessToken: token)
            sent = true
        } catch {
            errorMessage = "Impossible d'enregistrer le signalement."
        }
    }
}


/// Owner photo flow for drafts, live listings and archived listings.
struct ListingPhotoManagerView: View {
    let listingID: UUID
    var body: some View {
        ScrollView {
            ListingPhotoUploader(listingID: listingID)
                .padding(20)
        }
        .navigationTitle("Photos de l'annonce")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ListingPhotoUploader: View {
    let listingID: UUID
    @EnvironmentObject private var identity: KutanaSessionStore
    @State private var selected: [PhotosPickerItem] = []
    @State private var images: [ListingImageRecord] = []
    @State private var uploading = false
    @State private var photoRevision = 0
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Jusqu'à 5 photos. La première sera utilisée pour présenter l'annonce.")
                .font(.footnote).foregroundStyle(.secondary)
            addPhotosButton
            if uploading { ProgressView("Importation sécurisée…") }
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
            }
            Text("\(images.count) photo(s) enregistrée(s)")
                .font(.caption).foregroundStyle(.secondary)
            photoGallery
        }
        .task(id: listingID) { await load() }
        .onChange(of: selected) { _, items in
            Task { await upload(items) }
        }
    }

    private var addPhotosButton: some View {
        PhotosPicker(selection: $selected, maxSelectionCount: 5, matching: .images) {
            Label(uploading ? "Ajout des photos…" : "Ajouter des photos", systemImage: "photo.badge.plus")
                .font(.subheadline.weight(.semibold))
        }
        .disabled(uploading || images.count >= 5)
    }

    private var photoGallery: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(images) { item in
                    if let url = identity.configuration?.publicListingImageURL(path: item.storage_path) {
                        ListingPhotoReplacement(url: url, revision: photoRevision, disabled: uploading) { selected in
                            Task { await replace(selected, path: item.storage_path) }
                        }
                    }
                }
            }
        }
    }

    @MainActor private func load() async {
        guard let configuration = identity.configuration,
              let token = await identity.freshAccessToken() else { return }
        do {
            images = try await KutanaAPI(configuration: configuration)
                .listingImages(listingID: listingID, accessToken: token)
        } catch {
            errorMessage = "Impossible de charger les photos."
        }
    }

    @MainActor private func upload(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty, !uploading else { return }
        guard let configuration = identity.configuration,
              let token = await identity.freshAccessToken(),
              let owner = AccessTokenMetadata.subject(token) else {
            errorMessage = "Reconnectez-vous pour ajouter des photos."
            return
        }
        uploading = true
        errorMessage = nil
        defer {
            uploading = false
            selected = []
        }
        let api = KutanaAPI(configuration: configuration)
        for item in items.prefix(max(0, 5 - images.count)) {
            do {
                guard let original = try await item.loadTransferable(type: Data.self),
                      let source = UIImage(data: original),
                      let jpeg = source.jpegData(compressionQuality: 0.72),
                      (1...5_242_880).contains(jpeg.count) else {
                    errorMessage = "Photo illisible ou trop volumineuse (maximum 5 Mo)."
                    continue
                }
                _ = try await api.uploadListingImage(jpeg, listingID: listingID,
                                                    ownerID: owner, accessToken: token)
                await load()
            } catch {
                errorMessage = "Échec de l'importation. Réessayez avec une photo JPEG."
            }
        }
    }

    @MainActor private func replace(_ item: PhotosPickerItem, path: String) async {
        guard !uploading, let configuration = identity.configuration,
              let token = await identity.freshAccessToken(),
              let owner = AccessTokenMetadata.subject(token) else { return }
        uploading = true
        errorMessage = nil
        defer { uploading = false }
        do {
            guard let original = try await item.loadTransferable(type: Data.self),
                  let source = UIImage(data: original),
                  let jpeg = source.jpegData(compressionQuality: 0.72),
                  (1...5_242_880).contains(jpeg.count) else {
                errorMessage = "Photo illisible ou trop volumineuse (maximum 5 Mo)."
                return
            }
            try await KutanaAPI(configuration: configuration)
                .replaceListingImage(jpeg, path: path, ownerID: owner, accessToken: token)
            photoRevision += 1
            NotificationCenter.default.post(name: Notification.Name("kutana-publications-changed"), object: nil)
        } catch {
            errorMessage = "Impossible de remplacer cette photo. Réessayez."
        }
    }
}

private struct ListingPhotoReplacement: View {
    let url: URL
    let revision: Int
    let disabled: Bool
    let onSelect: (PhotosPickerItem) -> Void
    @State private var selection: PhotosPickerItem?

    private var imageURL: URL {
        url.appending(queryItems: [URLQueryItem(name: "v", value: String(revision))])
    }

    var body: some View {
        VStack(spacing: 6) {
            AsyncImage(url: imageURL) { photo in
                photo.resizable().scaledToFill()
            } placeholder: {
                ProgressView()
            }
            .frame(width: 108, height: 108)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel("Photo d'annonce")
            PhotosPicker(selection: $selection, matching: .images) {
                Label("Remplacer", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption.weight(.semibold))
            }
            .disabled(disabled)
        }
        .onChange(of: selection) { _, item in
            if let item { onSelect(item) }
            selection = nil
        }
    }
}
