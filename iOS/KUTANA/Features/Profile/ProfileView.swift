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
                    Label("Mes offres sauvegardées", systemImage: "bookmark")
                }
                Section("Annonces") {
                    Label("Mes annonces", systemImage: "tag")
                }
                Section {
                    Button("Se déconnecter", role: .destructive) { identity.signOut() }
                }
            }.navigationTitle("Mon profil")
        }
    }
}
