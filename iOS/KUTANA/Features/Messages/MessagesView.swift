import SwiftUI

/// Real private job-conversation inbox. The server decides which conversations
/// the signed-in user may read; no public phone number is exposed.
struct MessagesView: View {
    @EnvironmentObject private var identity: KutanaSessionStore
    @State private var conversations: [ConversationRecord] = []
    @State private var loading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if loading { ProgressView("Chargement des conversations…") }
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
                ForEach(conversations) { conversation in
                    NavigationLink {
                        KutanaChatView(conversationID: conversation.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Label("Discussion privée", systemImage: "bubble.left.and.bubble.right")
                                .font(.headline)
                            Text(conversation.created_at, style: .date)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                }
                if conversations.isEmpty && !loading {
                    ContentUnavailableView("Aucune conversation", systemImage: "bubble.left.and.bubble.right",
                        description: Text("Après une candidature, vous pourrez échanger avec le recruteur en privé."))
                }
            }
            .navigationTitle("Messages")
            .refreshable { await load() }
            .task { await load() }
        }
    }

    @MainActor private func load() async {
        guard let configuration = identity.configuration,
              let accessToken = await identity.freshAccessToken() else { return }
        loading = true
        errorMessage = nil
        defer { loading = false }
        do {
            conversations = try await KutanaAPI(configuration: configuration)
                .myConversations(accessToken: accessToken)
        } catch {
            errorMessage = "Impossible de charger les conversations. Réessayez."
        }
    }
}

struct KutanaChatView: View {
    let conversationID: UUID
    @EnvironmentObject private var identity: KutanaSessionStore
    @State private var messages: [MessageRecord] = []
    @State private var draft = ""
    @State private var loading = false
    @State private var sending = false
    @State private var errorMessage: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if loading { ProgressView("Chargement des messages…") }
                        if messages.isEmpty && !loading {
                            ContentUnavailableView("Commencez la conversation", systemImage: "bubble.left",
                                description: Text("Votre échange reste privé entre les deux participants."))
                        }
                        ForEach(messages) { message in
                            HStack {
                                if isMine(message) { Spacer(minLength: 50) }
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(message.body)
                                        .foregroundStyle(isMine(message) ? .white : KutanaTheme.ink)
                                    Text(message.created_at, style: .time)
                                        .font(.caption2)
                                        .foregroundStyle(isMine(message) ? .white.opacity(0.8) : .secondary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(isMine(message) ? KutanaTheme.blue : Color(.secondarySystemBackground),
                                            in: RoundedRectangle(cornerRadius: 16))
                                if !isMine(message) { Spacer(minLength: 50) }
                            }.id(message.id)
                        }
                    }
                    .padding(16)
                }
                .refreshable { await load() }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last?.id {
                        if reduceMotion {
                            proxy.scrollTo(last, anchor: .bottom)
                        } else {
                            withAnimation(KutanaMotion.reveal) { proxy.scrollTo(last, anchor: .bottom) }
                        }
                    }
                }
            }
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red).padding(.horizontal, 16)
            }
            Divider()
            HStack(alignment: .bottom, spacing: 12) {
                TextField("Votre message", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textInputAutocapitalization(.sentences)
                    .accessibilityLabel("Message privé")
                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 32))
                }
                .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Envoyer le message")
                .sensoryFeedback(.success, trigger: messages.count)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(.regularMaterial)
        }
        .navigationTitle("Discussion privée")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func isMine(_ message: MessageRecord) -> Bool {
        guard let token = identity.active?.token.access_token,
              let subject = AccessTokenMetadata.subject(token) else { return false }
        // This is presentation-only. Actual authorization is enforced by Supabase RLS.
        return message.sender_id == subject
    }

    @MainActor private func load() async {
        guard let configuration = identity.configuration,
              let token = await identity.freshAccessToken() else { return }
        loading = true
        errorMessage = nil
        defer { loading = false }
        do {
            messages = try await KutanaAPI(configuration: configuration)
                .conversationMessages(conversationID: conversationID, accessToken: token)
        } catch {
            errorMessage = "Impossible de charger les messages."
        }
    }

    @MainActor private func send() async {
        guard let configuration = identity.configuration,
              let token = await identity.freshAccessToken() else {
            errorMessage = "Connectez-vous pour envoyer un message."
            return
        }
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, body.count <= 4_000 else {
            errorMessage = "Le message doit contenir entre 1 et 4 000 caractères."
            return
        }
        sending = true
        errorMessage = nil
        defer { sending = false }
        do {
            _ = try await KutanaAPI(configuration: configuration)
                .sendMessage(conversationID: conversationID, text: body, accessToken: token)
            draft = ""
            await load()
        } catch {
            errorMessage = "Envoi impossible. Vérifiez la connexion et réessayez."
        }
    }
}
