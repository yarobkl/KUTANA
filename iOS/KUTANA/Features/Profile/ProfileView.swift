import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var identity: KutanaSessionStore
    var body: some View {
        NavigationStack {
            List {
                Section("Compte") {
                    Label("Compte connecté", systemImage: "envelope.badge.shield.half.filled")
                    Label("Profil candidat et recruteur", systemImage: "person.crop.circle")
                }
                Section("Emploi") {
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
