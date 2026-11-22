import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var identity: KutanaSessionStore
    var body: some View {
        NavigationStack {
            List {
                Section("Compte") {
                    NavigationLink { KutanaAccountView() } label: {
                        Label("Compte connecté", systemImage: "envelope.badge.shield.half.filled")
                    }
                    NavigationLink { NotificationsView() } label: {
                        Label("Notifications", systemImage: "bell")
                    }
                    NavigationLink { NotificationSettingsView() } label: {
                        Label("Réglages des notifications", systemImage: "slider.horizontal.3")
                    }
                }
                Section("Emploi") {
                    NavigationLink { JobAlertsView() } label: {
                        Label("Alertes emploi", systemImage: "bell.badge")
                    }
                    NavigationLink { ApplicationsView() } label: {
                        Label("Mes candidatures", systemImage: "doc.text")
                    }
                    NavigationLink { MyPublicationsView() } label: {
                        Label("Mes offres publiées", systemImage: "briefcase")
                    }
                    NavigationLink { ReceivedApplicationsView() } label: {
                        Label("Candidatures reçues", systemImage: "person.2.crop.square.stack")
                    }
                }
                Section("Annonces") {
                    NavigationLink { MyPublicationsView() } label: {
                        Label("Mes annonces", systemImage: "tag")
                    }
                }
                Section {
                    Button("Se déconnecter", role: .destructive) { identity.signOut() }
                }
            }.navigationTitle("Mon profil")
        }
    }
}
