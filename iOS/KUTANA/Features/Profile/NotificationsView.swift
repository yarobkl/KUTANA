import SwiftUI
import UserNotifications
import UIKit

struct NotificationsView: View {
    @EnvironmentObject private var identity: KutanaSessionStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var items: [KutanaNotification] = []
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            if items.isEmpty && errorMessage == nil {
                ContentUnavailableView("Aucune notification", systemImage: "bell", description: Text("Les nouveaux messages et les offres correspondant à vos alertes apparaîtront ici."))
            }
            ForEach(items) { item in
                Button {
                    Task { await markRead(item) }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: item.kind == "message" ? "bubble.left.fill" : "briefcase.fill")
                            .foregroundStyle(KutanaTheme.blue)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.title).fontWeight(item.read_at == nil ? .bold : .regular)
                            Text(item.body).font(.subheadline).foregroundStyle(.secondary)
                            Text(item.created_at, style: .relative).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if item.read_at == nil { Circle().fill(KutanaTheme.blue).frame(width: 7, height: 7) }
                    }
                }.buttonStyle(.plain)
            }
        }
        .navigationTitle("Notifications")
        .refreshable { await load() }
        .task { await load() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { return }
                if scenePhase == .active { await load() }
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await load() } } }
    }

    @MainActor private func load() async {
        guard let config = identity.configuration, let token = await identity.freshAccessToken() else { return }
        do { items = try await KutanaAPI(configuration: config).notifications(accessToken: token); errorMessage = nil }
        catch { errorMessage = "Impossible de charger les notifications." }
    }

    @MainActor private func markRead(_ item: KutanaNotification) async {
        guard item.read_at == nil, let config = identity.configuration,
              let token = await identity.freshAccessToken() else { return }
        do {
            try await KutanaAPI(configuration: config).markNotificationRead(id: item.id, accessToken: token)
            await load()
        } catch { errorMessage = "Impossible de marquer cette notification comme lue." }
    }
}

struct JobAlertsView: View {
    @EnvironmentObject private var identity: KutanaSessionStore
    @State private var keyword = ""
    @State private var city = ""
    @State private var alerts: [JobAlert] = []
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                TextField("Métier ou mot clé", text: $keyword)
                    .textInputAutocapitalization(.sentences)
                TextField("Ville (facultatif)", text: $city)
                Button("Créer une alerte") { Task { await add() } }
                    .disabled(keyword.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
            } header: { Text("Nouvelle alerte") } footer: {
                Text("Une nouvelle offre contenant ce mot clé dans le titre ou la description sera signalée dans Notifications. La ville est facultative.")
            }
            Section("Mes alertes") {
                ForEach(alerts) { alert in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(alert.keyword)
                            if !alert.city.isEmpty { Text(alert.city).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Button("Supprimer", systemImage: "trash", role: .destructive) { Task { await remove(alert) } }
                            .labelStyle(.iconOnly)
                    }
                }
                if alerts.isEmpty { Text("Aucune alerte enregistrée").foregroundStyle(.secondary) }
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .navigationTitle("Alertes emploi")
        .task { await load() }
        .refreshable { await load() }
    }

    @MainActor private func load() async {
        guard let config = identity.configuration, let token = await identity.freshAccessToken() else { return }
        do { alerts = try await KutanaAPI(configuration: config).alerts(accessToken: token); errorMessage = nil }
        catch { errorMessage = "Impossible de charger les alertes." }
    }

    @MainActor private func add() async {
        guard let config = identity.configuration, let token = await identity.freshAccessToken(),
              let userID = AccessTokenMetadata.subject(token) else { return }
        do {
            try await KutanaAPI(configuration: config).addAlert(keyword: keyword.trimmingCharacters(in: .whitespacesAndNewlines), city: city.trimmingCharacters(in: .whitespacesAndNewlines), userID: userID, accessToken: token)
            keyword = ""; city = ""; await load()
        } catch { errorMessage = "Cette alerte existe déjà ou n'a pas été enregistrée." }
    }

    @MainActor private func remove(_ alert: JobAlert) async {
        guard let config = identity.configuration, let token = await identity.freshAccessToken() else { return }
        do { try await KutanaAPI(configuration: config).removeAlert(id: alert.id, accessToken: token); await load() }
        catch { errorMessage = "Impossible de supprimer cette alerte." }
    }
}

struct KutanaAccountView: View {
    @EnvironmentObject private var identity: KutanaSessionStore
    var body: some View {
        Form {
            Section("Compte connecté") {
                if let token = identity.active?.token.access_token,
                   let userID = AccessTokenMetadata.subject(token) {
                    LabeledContent("Identifiant du compte", value: userID.uuidString)
                }
                Label("Compte candidat et recruteur", systemImage: "person.crop.circle")
            }
            Section("Emploi") { NavigationLink("Mes alertes emploi") { JobAlertsView() } }
        }.navigationTitle("Mon compte")
    }
}

struct NotificationSettingsView: View {
    @EnvironmentObject private var identity: KutanaSessionStore
    @Environment(\.openURL) private var openURL
    @State private var messages = true
    @State private var jobs = true
    @State private var errorMessage: String?
    @State private var saved = false
    @State private var systemPermission = ""

    var body: some View {
        Form {
            Section("Dans KUTANA") {
                Toggle("Nouveaux messages", isOn: $messages)
                Toggle("Offres de mes alertes", isOn: $jobs)
            }
            Section {
                Button("Enregistrer") { Task { await save() } }
                if saved { Label("Préférences enregistrées", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            } footer: {
                Text("Les notifications sont visibles dans KUTANA. Les alertes iPhone lorsque l'app est fermée nécessitent encore la configuration des notifications distantes.")
            }
            Section("Alertes iPhone") {
                Button("Autoriser les alertes sur cet iPhone") { Task { await requestSystemPermission() } }
                if !systemPermission.isEmpty { Text(systemPermission).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Réglages des notifications")
        .task { await load() }
    }

    @MainActor private func load() async {
        guard let config = identity.configuration, let token = await identity.freshAccessToken() else { return }
        do {
            let pref = try await KutanaAPI(configuration: config).preferences(accessToken: token)
            messages = pref.messages_enabled; jobs = pref.jobs_enabled
        } catch { errorMessage = "Impossible de charger les préférences." }
    }

    @MainActor private func save() async {
        guard let config = identity.configuration, let token = await identity.freshAccessToken(),
              let userID = AccessTokenMetadata.subject(token) else { return }
        do {
            try await KutanaAPI(configuration: config).savePreference(messages: messages, jobs: jobs, userID: userID, accessToken: token)
            saved = true; errorMessage = nil
        } catch { errorMessage = "Impossible d'enregistrer les préférences." }
    }

    @MainActor private func requestSystemPermission() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .denied {
            systemPermission = "Modifiez l'autorisation dans les réglages de l'iPhone."
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            return
        }
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            systemPermission = granted ? "Alertes autorisées sur cet iPhone." : "Alertes refusées sur cet iPhone."
        } catch { systemPermission = "L'autorisation n'a pas pu être demandée." }
    }
}
