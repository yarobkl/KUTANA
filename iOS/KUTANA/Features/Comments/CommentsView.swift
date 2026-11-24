import SwiftUI

/// Public discussion tied to the currently open offer or listing.
struct LukaCommentsView: View {
    let kind: String
    let contentID: UUID
    let isOwner: Bool
    @EnvironmentObject private var identity: KutanaSessionStore
    @State private var comments: [LukaComment] = []
    @State private var enabled = true
    @State private var loading = false
    @State private var loaded = false
    @State private var sending = false
    @State private var draft = ""
    @State private var replyingTo: LukaComment?
    @State private var reportTarget: LukaComment?
    @State private var errorMessage: String?
    @State private var resumeSend = false

    private var ownID: UUID? {
        guard let token = identity.active?.token.access_token else { return nil }
        return AccessTokenMetadata.subject(token)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
            HStack {
                Text("Commentaires").font(.title2.bold())
                Spacer()
                if isOwner && loaded {
                    Button(enabled ? "Fermer" : "Ouvrir") {
                        Task { await changeEnabled() }
                    }
                    .disabled(sending)
                    .font(.subheadline)
                    .accessibilityLabel(enabled ? "Fermer les nouveaux commentaires" : "Ouvrir les commentaires")
                }
            }

            if loading && !loaded { ProgressView("Chargement des commentaires…") }
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
                Button("Réessayer") { Task { await load() } }
                    .disabled(loading)
            }
            if loaded && comments.isEmpty {
                Text("Aucun commentaire pour le moment.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(loaded ? comments : []) { comment in
                commentRow(comment)
                    .padding(.leading, comment.parent_id == nil ? 0 : 16)
            }

            if enabled && loaded {
                if let replyingTo {
                    HStack {
                        Text("Réponse à \(replyingTo.author_name)").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Annuler") { self.replyingTo = nil }
                            .font(.caption)
                    }
                }
                TextField("Votre commentaire", text: $draft, axis: .vertical)
                    .accessibilityIdentifier("luka-comment-draft")
                    .lineLimit(2...5)
                    .textInputAutocapitalization(.sentences)
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                Button(sending ? "Envoi…" : "Publier le commentaire") {
                    if identity.authenticated {
                        Task { await send() }
                    } else {
                        resumeSend = true
                        NotificationCenter.default.post(name: Notification.Name("kutana-request-login"), object: nil)
                    }
                }
                .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.count > 2000)
            } else if loaded {
                Text("Les nouveaux commentaires sont fermés.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .task(id: contentID) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("kutana-login-cancelled"))) { _ in
            resumeSend = false
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("luka-profile-ready"))) { _ in
            if identity.authenticated && resumeSend {
                resumeSend = false
                Task { await send() }
            }
        }
        .sheet(item: $reportTarget) { comment in
            LukaCommentReportSheet(comment: comment)
        }
    }

    private func commentRow(_ comment: LukaComment) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(comment.author_name).font(.subheadline.bold())
                Spacer()
                Text(comment.created_at, style: .date).font(.caption).foregroundStyle(.secondary)
                if comment.deleted_at == nil {
                    Menu {
                        if enabled {
                            Button("Répondre") {
                                replyingTo = comment
                                if !identity.authenticated {
                                    NotificationCenter.default.post(name: Notification.Name("kutana-request-login"), object: nil)
                                }
                            }
                        }
                        if ownID == comment.author_id {
                            Button("Supprimer", role: .destructive) { Task { await remove(comment) } }
                        } else if identity.authenticated {
                            Button("Signaler") { reportTarget = comment }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("Actions du commentaire")
                }
            }
            if let parent = comment.parent_id {
                let name = comments.first(where: { $0.id == parent })?.author_name ?? "un commentaire"
                Text("En réponse à \(name)").font(.caption).foregroundStyle(.secondary)
            }
            Text(comment.body).font(.subheadline)
        }
        .padding(.vertical, 5)
    }

    @MainActor private func load() async {
        guard let config = identity.configuration else { return }
        loading = true
        defer { loading = false }
        do {
            let api = KutanaAPI(configuration: config)
            async let rows = api.publicComments(kind: kind, contentID: contentID)
            async let state = api.commentsEnabled(kind: kind, contentID: contentID)
            (comments, enabled) = try await (rows, state)
            loaded = true
            errorMessage = nil
        } catch {
            loaded = false
            errorMessage = "Impossible de charger les commentaires. Réessayez."
        }
    }

    @MainActor private func send() async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, body.count <= 2000, let config = identity.configuration else { return }
        guard let token = await identity.freshAccessToken() else {
            if !identity.authenticated {
                resumeSend = true
                NotificationCenter.default.post(name: Notification.Name("kutana-request-login"), object: nil)
            } else { errorMessage = "Connexion indisponible. Réessayez." }
            return
        }
        sending = true
        defer { sending = false }
        do {
            try await KutanaAPI(configuration: config).addComment(
                kind: kind, contentID: contentID, parentID: replyingTo?.id, body: body, accessToken: token)
            draft = ""
            replyingTo = nil
            await load()
        } catch { errorMessage = "Envoi impossible. Vérifiez que les commentaires sont ouverts et réessayez." }
    }

    @MainActor private func remove(_ comment: LukaComment) async {
        guard let config = identity.configuration, let token = await identity.freshAccessToken() else {
            errorMessage = "Reconnectez-vous pour supprimer votre commentaire."
            return
        }
        do {
            try await KutanaAPI(configuration: config).deleteComment(id: comment.id, accessToken: token)
            await load()
        } catch { errorMessage = "Impossible de supprimer le commentaire." }
    }

    @MainActor private func changeEnabled() async {
        guard let config = identity.configuration, let token = await identity.freshAccessToken() else {
            errorMessage = "Reconnectez-vous pour modifier les commentaires."
            return
        }
        sending = true
        defer { sending = false }
        do {
            try await KutanaAPI(configuration: config).setCommentsEnabled(
                kind: kind, contentID: contentID, enabled: !enabled, accessToken: token)
            await load()
        } catch { errorMessage = "Impossible de modifier les commentaires." }
    }
}

private struct LukaCommentReportSheet: View {
    let comment: LukaComment
    @EnvironmentObject private var identity: KutanaSessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var sending = false
    @State private var sent = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Pourquoi signalez-vous ce commentaire ?") {
                    TextField("Décrivez le problème", text: $reason, axis: .vertical).lineLimit(4...8)
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
                if sent {
                    Label("Signalement transmis", systemImage: "checkmark.circle").foregroundStyle(.green)
                } else {
                    Button(sending ? "Envoi…" : "Envoyer le signalement") { Task { await send() } }
                        .disabled(sending || !(10...1000).contains(reason.trimmingCharacters(in: .whitespacesAndNewlines).count))
                }
            }
            .navigationTitle("Signaler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } } }
        }
    }

    @MainActor private func send() async {
        guard let config = identity.configuration, let token = await identity.freshAccessToken() else {
            errorMessage = "Reconnectez-vous pour signaler un commentaire."
            return
        }
        sending = true
        defer { sending = false }
        do {
            try await KutanaAPI(configuration: config).reportComment(
                id: comment.id, reason: reason.trimmingCharacters(in: .whitespacesAndNewlines), accessToken: token)
            sent = true
        } catch { errorMessage = "Impossible d'envoyer le signalement." }
    }
}
