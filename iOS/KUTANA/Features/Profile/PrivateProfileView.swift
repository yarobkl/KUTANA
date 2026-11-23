import SwiftUI
import PhoneNumberKit

/// Private account details. The server enforces that only the owner can read or update them.
struct LukaPrivateProfileView: View {
    var completionMode = false
    var onSaved: (() -> Void)?

    init(completionMode: Bool = false, onSaved: (() -> Void)? = nil) {
        self.completionMode = completionMode
        self.onSaved = onSaved
    }
    @EnvironmentObject private var identity: KutanaSessionStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: Field?
    private enum Field: Hashable { case first, last, phone, city, commune }
    private static let phoneUtility = PhoneNumberUtility()
    private static let regions: [String] = Locale.Region.isoRegions.map(\.identifier)
        .filter { $0.count == 2 }
        .sorted { (Locale.current.localizedString(forRegionCode: $0) ?? $0) <
                  (Locale.current.localizedString(forRegionCode: $1) ?? $1) }
    private static let phoneRegions = regions.filter { phoneUtility.countryCode(for: $0) != nil }

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var birthDate: Date?
    @State private var phone = ""
    @State private var phoneRegion = "CG"
    @State private var country = "CG"
    @State private var city = ""
    @State private var commune = ""
    @State private var shareLocation = false
    @State private var loading = false
    @State private var loaded = false
    @State private var saving = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            if loading {
                ProgressView("Chargement du profil…")
            } else if loaded {
                Section("Identité") {
                    TextField("Prénom", text: $firstName)
                        .textContentType(.givenName).textInputAutocapitalization(.words)
                        .submitLabel(.next).focused($focus, equals: .first)
                        .onSubmit { focus = .last }
                    TextField("Nom", text: $lastName)
                        .textContentType(.familyName).textInputAutocapitalization(.words)
                        .submitLabel(.next).focused($focus, equals: .last)
                        .onSubmit { focus = .phone }
                    if birthDate != nil {
                        DatePicker("Date de naissance", selection: Binding(
                            get: { birthDate ?? Self.defaultBirthDate },
                            set: { birthDate = $0 }),
                            in: Self.earliestBirthDate...Date(), displayedComponents: .date)
                    } else {
                        Button("Indiquer ma date de naissance") { birthDate = Self.defaultBirthDate }
                    }
                }

                Section("Téléphone") {
                    Picker("Indicatif", selection: $phoneRegion) {
                        ForEach(Self.phoneRegions, id: \.self) { region in
                            if let code = Self.phoneUtility.countryCode(for: region) {
                                Text("\(Self.regionName(region)) +\(code)").tag(region)
                            }
                        }
                    }
                    TextField("Numéro de téléphone", text: $phone)
                        .keyboardType(.phonePad).textContentType(.telephoneNumber)
                        .focused($focus, equals: .phone)
                }

                Section("Localisation") {
                    Picker("Pays", selection: $country) {
                        ForEach(Self.regions, id: \.self) { region in
                            Text(Self.regionName(region)).tag(region)
                        }
                    }
                    TextField("Ville", text: $city)
                        .textInputAutocapitalization(.words).submitLabel(.next)
                        .focused($focus, equals: .city).onSubmit { focus = .commune }
                    TextField("Commune", text: $commune)
                        .textInputAutocapitalization(.words).submitLabel(.done)
                        .focused($focus, equals: .commune).onSubmit { focus = nil }
                }

                Section {
                    Toggle("Partager ma localisation avec les recruteurs", isOn: $shareLocation)
                } footer: {
                    Text("Pour vos candidatures, le recruteur peut voir le pays, la ville et la commune si vous l'autorisez. Votre téléphone et votre date de naissance restent privés.")
                }

                if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                Section {
                    Button(saving ? "Enregistrement…" : "Enregistrer") { Task { await save() } }
                        .disabled(saving)
                }
            } else {
                if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                Button("Réessayer") { Task { await load() } }
            }
        }
        .navigationTitle("Informations personnelles")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if completionMode {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Continuer en visiteur") { identity.signOut(); dismiss() }
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Suivant") {
                    switch focus {
                    case .first: focus = .last
                    case .last: focus = .phone
                    case .phone: focus = .city
                    case .city: focus = .commune
                    default: focus = nil
                    }
                }
            }
        }
        .task { await load() }
    }

    private static var defaultBirthDate: Date {
        Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
    }
    private static var earliestBirthDate: Date {
        Calendar.current.date(from: DateComponents(year: 1901, month: 1, day: 1)) ?? .distantPast
    }
    private static func regionName(_ code: String) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }
    private static func dateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    @MainActor private func load() async {
        guard let config = identity.configuration, let token = await identity.freshAccessToken() else {
            errorMessage = "Reconnectez-vous pour accéder à votre profil."
            return
        }
        loading = true
        errorMessage = nil
        defer { loading = false }
        do {
            if let profile = try await KutanaAPI(configuration: config).privateProfile(accessToken: token) {
                firstName = profile.first_name
                lastName = profile.last_name
                birthDate = Self.dateFormatter().date(from: profile.birth_date)
                phone = profile.phone_e164
                phoneRegion = profile.phone_region
                country = profile.country_code
                city = profile.city
                commune = profile.commune
                shareLocation = profile.share_location_with_recruiters
            } else {
                firstName = identity.suggestedFirstName
                lastName = identity.suggestedLastName
                if firstName.isEmpty && lastName.isEmpty,
                   let basic = try? await KutanaAPI(configuration: config).basicProfile(accessToken: token) {
                    let pieces = basic.display_name.split(separator: " ", maxSplits: 1)
                    if let first = pieces.first { firstName = String(first) }
                    if pieces.count > 1 { lastName = String(pieces[1]) }
                }
            }
            loaded = true
        } catch {
            errorMessage = "Impossible de charger votre profil. Réessayez."
        }
    }

    @MainActor private func save() async {
        let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCommune = commune.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...80).contains(first.count), (1...80).contains(last.count),
              (1...120).contains(cleanCity.count), (1...120).contains(cleanCommune.count),
              let birthDate else {
            errorMessage = "Renseignez votre identité, votre date de naissance, votre ville et votre commune."
            return
        }
        let normalizedPhone: String
        do {
            let parsed = try Self.phoneUtility.parse(phone, withRegion: phoneRegion)
            guard let selectedCode = Self.phoneUtility.countryCode(for: phoneRegion),
                  parsed.countryCode == selectedCode else {
                errorMessage = "Le numéro ne correspond pas à l'indicatif choisi."
                return
            }
            normalizedPhone = Self.phoneUtility.format(parsed, toType: .e164)
        } catch {
            errorMessage = "Indiquez un numéro de téléphone valide pour l'indicatif choisi."
            return
        }
        guard let config = identity.configuration, let token = await identity.freshAccessToken(),
              let userID = AccessTokenMetadata.subject(token) else {
            errorMessage = "Reconnectez-vous pour enregistrer votre profil."
            return
        }
        let profile = LukaPrivateProfile(user_id: userID, first_name: first, last_name: last,
            birth_date: Self.dateFormatter().string(from: birthDate), phone_e164: normalizedPhone,
            phone_region: phoneRegion, country_code: country, city: cleanCity, commune: cleanCommune,
            share_location_with_recruiters: shareLocation)
        saving = true
        errorMessage = nil
        defer { saving = false }
        do {
            try await KutanaAPI(configuration: config).savePrivateProfile(profile, accessToken: token)
            onSaved?()
            dismiss()
        } catch { errorMessage = "Impossible d'enregistrer votre profil. Réessayez." }
    }
}
