import SwiftUI

// KUTANA only. This flow is deliberately independent of all other Yaro products.
private enum WelcomePage: Hashable { case splash, introduction, login, registration, reset }

struct WelcomeFlow: View {
    @EnvironmentObject private var identity: KutanaSessionStore
    @AppStorage("kutana.hasSeenIntroduction") private var hasSeenIntroduction = false
    @State private var route: WelcomePage = .splash
    @State private var didCompleteLaunch = false
    @State private var showingPreview = false

    var body: some View {
        NavigationStack {
            Group {
              if identity.authenticated {
                RootView()
              } else {
                switch route {
                case .splash:
                    KutanaSplashView()
                case .introduction:
                    KutanaIntroductionView(
                        skip: { hasSeenIntroduction = true; route = .login },
                        continueAction: { hasSeenIntroduction = true; route = .login }
                    )
                case .login:
                    KutanaLoginView(
                        createAccount: { route = .registration },
                        resetPassword: { route = .reset },
                        preview: { showingPreview = true }
                    )
                case .registration:
                    KutanaRegistrationView(back: { route = .login })
                case .reset:
                    KutanaResetPasswordView(back: { route = .login })
                }
              }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingPreview) {
                NavigationStack {
                    RootView()
                        .toolbar { ToolbarItem(placement: .topBarTrailing) {
                            Button("Fermer") { showingPreview = false }
                        }}
                }
            }
        }
        .tint(KutanaTheme.blue)
        // The approved splash is now part of the actual launch path, not just an unused view.
        .task {
            guard !didCompleteLaunch else { return }
            didCompleteLaunch = true
            await identity.restore()
            try? await Task.sleep(for: .milliseconds(950))
            guard !Task.isCancelled else { return }
            route = hasSeenIntroduction ? .login : .introduction
        }
    }
}

private struct KutanaLogo: View {
    var large = false
    var body: some View {
        VStack(spacing: large ? 10 : 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: large ? 23 : 12)
                        .fill(LinearGradient(colors: [Color(red: 0.06, green: 0.39, blue: 0.99), Color(red: 0.02, green: 0.22, blue: 0.79)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text("K").font(.system(size: large ? 76 : 32, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
                .frame(width: large ? 110 : 48, height: large ? 110 : 48)
                if !large { Text("KUTANA").font(.system(size: 25, weight: .heavy)).foregroundStyle(KutanaTheme.ink) }
            }
            if large { Text("KUTANA").font(.system(size: 44, weight: .heavy)).foregroundStyle(KutanaTheme.ink) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("KUTANA")
    }
}

struct KutanaSplashView: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.white.ignoresSafeArea()
                VStack(spacing: 8) {
                    KutanaLogo(large: true)
                    Text("Emploi · Annonces · Congo")
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                }
                Path { path in
                    path.move(to: CGPoint(x: 0, y: proxy.size.height))
                    path.addCurve(to: CGPoint(x: proxy.size.width, y: proxy.size.height * 0.76), control1: CGPoint(x: proxy.size.width * 0.43, y: proxy.size.height * 0.92), control2: CGPoint(x: proxy.size.width * 0.72, y: proxy.size.height * 0.76))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height))
                    path.closeSubpath()
                }
                .fill(KutanaTheme.blue)
                .ignoresSafeArea(edges: .bottom)
            }
        }
    }
}

private struct KutanaIntroductionView: View {
    let skip: () -> Void
    let continueAction: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Spacer(); Button("Passer", action: skip).fontWeight(.semibold) }.padding(.top, 12)
            Spacer(minLength: 32)
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(red: 0.94, green: 0.96, blue: 0.99))
                    .frame(width: 215, height: 265)
                    .rotationEffect(.degrees(-6))
                    .overlay(alignment: .topLeading) {
                        Label("Emploi", systemImage: "briefcase")
                            .font(.subheadline.bold())
                            .padding(11).background(.white, in: Capsule())
                            .offset(x: -4, y: 17)
                    }
                Image("kutana_employee")
                    .resizable().scaledToFill().frame(width: 205, height: 245)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .rotationEffect(.degrees(-6))
                    .accessibilityLabel("Jeune professionnel dans un bureau")
                RoundedRectangle(cornerRadius: 23)
                    .fill(Color(red: 0.91, green: 0.92, blue: 0.94))
                    .frame(width: 151, height: 195)
                    .rotationEffect(.degrees(7))
                    .overlay {
                        VStack(spacing: 15) {
                            Image(systemName: "shippingbox.fill").font(.system(size: 55)).foregroundStyle(.brown)
                            Label("Annonces", systemImage: "tag")
                                .font(.caption.bold()).padding(10).background(.white, in: Capsule())
                        }
                    }
                    .offset(x: 95, y: 33)
            }
            .frame(maxWidth: .infinity).frame(height: 320)
            HStack(spacing: 9) {
                Circle().fill(KutanaTheme.blue).frame(width: 9, height: 9)
                Circle().fill(.gray.opacity(0.25)).frame(width: 9, height: 9)
                Circle().fill(.gray.opacity(0.25)).frame(width: 9, height: 9)
            }.frame(maxWidth: .infinity).padding(.top, 14)
            Spacer(minLength: 34)
            Text("Emploi et annonces\nau Congo")
                .font(.system(size: 32, weight: .bold)).tracking(-0.8)
                .foregroundStyle(KutanaTheme.ink)
            Text("Trouvez un emploi, recrutez des talents et vendez ou achetez tout ce dont vous avez besoin, en toute simplicité.")
                .font(.system(size: 16)).foregroundStyle(.secondary)
                .padding(.top, 14)
            Spacer(minLength: 35)
            KutanaPrimaryButton(title: "Commencer", action: continueAction)
                .padding(.bottom, 28)
        }
        .padding(.horizontal, 25)
        .background(.white)
    }
}

private struct KutanaAuthHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            KutanaLogo().frame(maxWidth: .infinity).padding(.bottom, 24)
            Text(title).font(.system(size: 30, weight: .bold)).foregroundStyle(KutanaTheme.ink)
            Text(subtitle).font(.system(size: 15)).foregroundStyle(.secondary)
        }
    }
}

private struct KutanaLoginView: View {
    let createAccount: () -> Void
    let resetPassword: () -> Void
    let preview: () -> Void
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @EnvironmentObject private var identity: KutanaSessionStore
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                KutanaAuthHeader(title: "Se connecter", subtitle: "Accédez à votre compte pour publier, postuler et échanger.")
                    .padding(.top, 66)
                Group {
                    TextField("Adresse e-mail", text: $email)
                        .textContentType(.emailAddress).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    HStack {
                        Group { if showPassword { TextField("Mot de passe", text: $password) }
                        else { SecureField("Mot de passe", text: $password) } }
                        .textContentType(.password)
                        Button { showPassword.toggle() } label: {
                            Image(systemName: showPassword ? "eye" : "eye.slash")
                        }.accessibilityLabel(showPassword ? "Masquer le mot de passe" : "Afficher le mot de passe")
                    }
                }
                .kutanaField()
                .padding(.top, 12)
                Button("Mot de passe oublié ?", action: resetPassword)
                    .font(.footnote.bold()).frame(maxWidth: .infinity, alignment: .trailing).padding(.top, 16)
                if let notice = identity.notice {
                    Text(notice).font(.footnote).foregroundStyle(.green)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
                }
                if let error = identity.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
                }
                KutanaPrimaryButton(title: identity.busy ? "Connexion en cours…" : "Se connecter") {
                    Task { await identity.signIn(email: email, password: password) }
                }
                    .disabled(!identity.isConfigured || identity.busy || email.isEmpty || password.isEmpty)
                    .padding(.top, 31)
                Text("ou continuer avec").font(.footnote).foregroundStyle(.secondary).padding(.vertical, 24)
                KutanaSocialButton(title: "Continuer avec Apple", icon: "apple.logo")
                KutanaSocialButton(title: "Continuer avec Google", icon: "g.circle.fill").padding(.top, 12)
                HStack(spacing: 4) {
                    Text("Vous n'avez pas encore de compte ?").foregroundStyle(.secondary)
                    Button("Créer un compte", action: createAccount).fontWeight(.semibold)
                }.font(.system(size: 12)).padding(.top, 30)
                Button("Prévisualiser l'application sans compte", action: preview)
                    .font(.footnote).padding(.top, 26)
            }.padding(.horizontal, 25)
        }
        .background(.white)
    }
}

private struct KutanaRegistrationView: View {
    let back: () -> Void
    @State private var fullName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var validationError: String?
    @EnvironmentObject private var identity: KutanaSessionStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Button(action: back) { Image(systemName: "chevron.left").font(.title3) }
                KutanaAuthHeader(title: "Créer un compte", subtitle: "Rejoignez KUTANA pour trouver un emploi, publier vos annonces et échanger facilement.")
                    .padding(.top, 33)
                TextField("Nom et prénom", text: $fullName).textContentType(.name).kutanaField()
                TextField("Adresse e-mail", text: $email)
                    .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled().kutanaField()
                SecureField("Mot de passe", text: $password).textContentType(.newPassword).kutanaField()
                SecureField("Confirmer le mot de passe", text: $confirmation).textContentType(.newPassword).kutanaField()
                if let error = validationError ?? identity.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
                KutanaPrimaryButton(title: identity.busy ? "Création en cours…" : "Créer mon compte") {
                    guard password == confirmation else {
                        validationError = "Les deux mots de passe ne correspondent pas."
                        return
                    }
                    validationError = nil
                    Task {
                        if await identity.signUp(email: email, password: password, fullName: fullName) {
                            back()
                        }
                    }
                }
                    .disabled(!identity.isConfigured || identity.busy || fullName.isEmpty || email.isEmpty || password.isEmpty || confirmation.isEmpty)
                    .padding(.top, 40)
                HStack {
                    Spacer()
                    Text("Vous avez déjà un compte ?").foregroundStyle(.secondary)
                    Button("Se connecter", action: back).fontWeight(.semibold)
                    Spacer()
                }.font(.footnote).padding(.top, 65)
            }.padding(.horizontal, 25).padding(.top, 20)
        }.background(.white)
    }
}

private struct KutanaResetPasswordView: View {
    let back: () -> Void
    @State private var email = ""
    @State private var sent = false
    @EnvironmentObject private var identity: KutanaSessionStore
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button("Retour", action: back)
            KutanaAuthHeader(title: "Mot de passe oublié ?", subtitle: "Indiquez votre adresse e-mail pour recevoir un lien de réinitialisation.")
            TextField("Adresse e-mail", text: $email).textInputAutocapitalization(.never).keyboardType(.emailAddress).kutanaField()
            if let error = identity.errorMessage { Text(error).font(.footnote).foregroundStyle(.red) }
            if sent { Text(identity.notice ?? "Demande reçue.").font(.footnote).foregroundStyle(.green) }
            KutanaPrimaryButton(title: identity.busy ? "Envoi en cours…" : "Envoyer le lien") {
                Task { sent = await identity.resetPassword(email: email) }
            }.disabled(!identity.isConfigured || identity.busy || email.isEmpty)
            Spacer()
        }.padding(25)
    }
}

private struct KutanaSocialButton: View {
    let title: String
    let icon: String
    var body: some View {
        Button {} label: {
            Label(title, systemImage: icon).font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity).frame(height: 50)
                .foregroundStyle(KutanaTheme.ink)
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.gray.opacity(0.23)))
        }
        .disabled(true) // OAuth provider not yet configured.
    }
}

private struct KutanaFieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 15))
            .padding(.horizontal, 16)
            .frame(height: 52)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.25)))
    }
}

private extension View {
    func kutanaField() -> some View { modifier(KutanaFieldModifier()) }
}
