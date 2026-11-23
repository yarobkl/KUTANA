import SwiftUI
import AuthenticationServices
import UIKit

// KUTANA only. This flow is deliberately independent of all other Yaro products.
private enum WelcomePage: Hashable { case introduction, login, registration, reset }

struct WelcomeFlow: View {
    @EnvironmentObject private var identity: KutanaSessionStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("kutana.hasSeenIntroduction") private var hasSeenIntroduction = false
    @State private var route: WelcomePage = .login
    @State private var splashFinished = false
    @State private var showingPreview = false

    var body: some View {
        Group {
            if identity.authenticated {
                RootView(allowNotificationPrompt: splashFinished)
            } else {
                NavigationStack {
                    switch route {
                    case .login:
                        KutanaLoginView(
                            createAccount: { route = .registration },
                            resetPassword: { route = .reset },
                            preview: { showingPreview = true }
                        )
                    case .introduction:
                        KutanaIntroductionView(
                            skip: { hasSeenIntroduction = true; route = .login },
                            continueAction: { hasSeenIntroduction = true; route = .login }
                        )
                    case .registration:
                        KutanaRegistrationView(back: { route = .login })
                    case .reset:
                        KutanaResetPasswordView(back: { route = .login })
                    }
                }
                .toolbar(.hidden, for: .navigationBar)
            }
        }
        .sheet(isPresented: $showingPreview) {
            NavigationStack {
                RootView()
                    .toolbar { ToolbarItem(placement: .topBarTrailing) {
                        Button("Fermer") { showingPreview = false }
                    }}
            }
        }
        .tint(KutanaTheme.blue)
        .overlay {
            if !splashFinished {
                KutanaSplashView {
                    if !identity.authenticated {
                        route = hasSeenIntroduction ? .login : .introduction
                    }
                    if reduceMotion {
                        splashFinished = true
                    } else {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            splashFinished = true
                        }
                    }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .task { await identity.restore() }
    }
}

private struct KutanaLogo: View {
    var large = false
    var body: some View {
        VStack(spacing: large ? 10 : 0) {
            HStack(spacing: 12) {
                Image("kutana_mark")
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: large ? 23 : 12, style: .continuous))
                    .frame(width: large ? 110 : 48, height: large ? 110 : 48)
                if !large {
                    Text("KUTANA")
                        .font(.system(size: 25, weight: .heavy))
                        .foregroundStyle(KutanaTheme.ink)
                }
            }
            if large {
                Text("KUTANA").font(.system(size: 44, weight: .heavy))
                    .foregroundStyle(KutanaTheme.ink)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("KUTANA")
    }
}

private struct KutanaSplashView: View {
    let onFinished: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var logoOffset: CGFloat = -650
    @State private var logoScale: CGFloat = 0.82
    @State private var textOpacity = 0.0
    @State private var textOffset: CGFloat = 14

    var body: some View {
        GeometryReader { proxy in
            let side = min(110.0, max(88.0, proxy.size.width * 0.28))
            ZStack {
                Color.white.ignoresSafeArea()
                BottomWaveShape()
                    .fill(LinearGradient(
                        colors: [KutanaTheme.blue, Color(red: 0.02, green: 0.25, blue: 0.85)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(height: min(240, max(155, proxy.size.height * 0.28)))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .ignoresSafeArea(edges: .bottom)

                VStack(spacing: 19) {
                    Image("kutana_mark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: side, height: side)
                        .clipShape(RoundedRectangle(cornerRadius: side * 0.23, style: .continuous))
                        .shadow(color: KutanaTheme.blue.opacity(0.22), radius: 15, x: 0, y: 9)
                        .offset(y: logoOffset)
                        .scaleEffect(logoScale)

                    VStack(spacing: 8) {
                        Text("KUTANA")
                            .font(.system(size: 32, weight: .black))
                            .tracking(2)
                            .foregroundStyle(KutanaTheme.ink)
                        Text("Emploi · Annonces · Congo")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                            .minimumScaleFactor(0.8)
                            .lineLimit(1)
                    }
                    .opacity(textOpacity)
                    .offset(y: textOffset)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 18)
                .offset(y: -min(35, proxy.size.height * 0.05))
            }
        }
        .task {
            if reduceMotion {
                logoOffset = 0
                logoScale = 1
                textOpacity = 1
                textOffset = 0
                try? await Task.sleep(for: .milliseconds(350))
            } else {
                let landingFeedback = UIImpactFeedbackGenerator(style: .rigid)
                landingFeedback.prepare()
                withAnimation(.spring(response: 0.68, dampingFraction: 0.63)) {
                    logoOffset = 0
                    logoScale = 1
                }
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                landingFeedback.impactOccurred(intensity: 1)
                withAnimation(.easeOut(duration: 0.45)) {
                    textOpacity = 1
                    textOffset = 0
                }
                try? await Task.sleep(for: .milliseconds(1400))
            }
            guard !Task.isCancelled else { return }
            onFinished()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("KUTANA. Emploi, annonces, Congo.")
    }
}

private struct BottomWaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height))
        path.addCurve(to: CGPoint(x: rect.width, y: rect.height * 0.15),
                      control1: CGPoint(x: rect.width * 0.45, y: rect.height * 0.85),
                      control2: CGPoint(x: rect.width * 0.65, y: rect.height * 0.1))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.closeSubpath()
        return path
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
                KutanaSocialSignInButtons()
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
                    .padding(.top, 30)
                Text("Mot de passe : 12 caractères minimum.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("ou vous inscrire avec")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.top, 12)
                KutanaSocialSignInButtons()
                    .padding(.bottom, 4)
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

private struct KutanaSocialSignInButtons: View {
    @EnvironmentObject private var identity: KutanaSessionStore
    @State private var appleNonce: String?

    var body: some View {
        VStack(spacing: 12) {
            // Apple's official native button includes the required Apple mark and consent sheet.
            SignInWithAppleButton(.continue, onRequest: { request in
                do {
                    let nonce = try KutanaAuthNonce.generate()
                    appleNonce = nonce
                    request.requestedScopes = [.email, .fullName]
                    request.nonce = KutanaAuthNonce.appleHash(nonce)
                } catch {
                    appleNonce = nil
                    identity.reportSocialSignInFailure(error)
                }
            }, onCompletion: { result in
                switch result {
                case .success(let result):
                    guard let credential = result.credential as? ASAuthorizationAppleIDCredential,
                          let data = credential.identityToken,
                          let token = String(data: data, encoding: .utf8),
                          let nonce = appleNonce else {
                        identity.reportSocialSignInFailure(KutanaSocialAuthError.missingAppleToken)
                        return
                    }
                    appleNonce = nil
                    Task { await identity.signInWithApple(idToken: token, nonce: nonce) }
                case .failure(let error):
                    appleNonce = nil
                    identity.reportSocialSignInFailure(error)
                }
            })
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 13))
            .accessibilityLabel("Continuer avec Apple")

            Button {
                Task { await identity.signInWithGoogle() }
            } label: {
                HStack(spacing: 12) {
                    KutanaGoogleMark().frame(width: 23, height: 23)
                    Text("Continuer avec Google")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(KutanaTheme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.white)
                .overlay(RoundedRectangle(cornerRadius: 13)
                    .stroke(Color.gray.opacity(0.28), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Continuer avec Google")
        }
        .disabled(identity.busy || !identity.isConfigured)
    }
}

/// Four-color Google G mark drawn natively, without a remote image or font.
private struct KutanaGoogleMark: View {
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = size.width * 0.35
            let segments: [(Color, Double, Double)] = [
                (Color(red: 0.92, green: 0.26, blue: 0.21), 42, 134),
                (Color(red: 0.98, green: 0.74, blue: 0.05), 134, 181),
                (Color(red: 0.21, green: 0.66, blue: 0.33), 181, 257),
                (Color(red: 0.26, green: 0.52, blue: 0.96), 257, 342)
            ]
            for (color, start, end) in segments {
                var arc = Path()
                arc.addArc(center: center, radius: radius,
                           startAngle: .degrees(start), endAngle: .degrees(end),
                           clockwise: false)
                context.stroke(arc, with: .color(color),
                               style: StrokeStyle(lineWidth: size.width * 0.20))
            }
            var bar = Path()
            bar.move(to: CGPoint(x: size.width * 0.50, y: size.height * 0.51))
            bar.addLine(to: CGPoint(x: size.width * 0.94, y: size.height * 0.51))
            context.stroke(bar, with: .color(Color(red: 0.26, green: 0.52, blue: 0.96)),
                           style: StrokeStyle(lineWidth: size.width * 0.20))
        }
        .accessibilityHidden(true)
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
