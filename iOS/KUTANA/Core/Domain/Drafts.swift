import Foundation

/// Immutable, local-only publication input. Ownership and the draft status are
/// assigned by an authenticated KUTANA-only PostgreSQL function, not by iOS.
enum DraftValidationError: LocalizedError {
    case title, company, city, description, category, contract, price

    var errorDescription: String? {
        switch self {
        case .title: "Le titre doit contenir entre 5 et 160 caractères."
        case .company: "Indiquez le nom de l'entreprise."
        case .city: "Indiquez une ville au Congo."
        case .description: "La description doit contenir entre 30 et 12 000 caractères pour un emploi, ou entre 10 et 12 000 pour une annonce."
        case .category: "Choisissez une catégorie."
        case .contract: "Choisissez un type de contrat."
        case .price: "Indiquez un prix valide en FCFA."
        }
    }
}

struct JobDraftInput: Encodable, Sendable {
    let p_title: String
    let p_company: String
    let p_city: String
    let p_contract_type: String
    let p_description: String

    init(title: String, company: String, city: String, contract: String, description: String) throws {
        let title = Self.clean(title)
        let company = Self.clean(company)
        let city = Self.clean(city)
        let contract = Self.clean(contract)
        let description = Self.clean(description)
        guard (5...160).contains(title.count) else { throw DraftValidationError.title }
        guard (2...160).contains(company.count) else { throw DraftValidationError.company }
        guard (2...120).contains(city.count) else { throw DraftValidationError.city }
        guard ["CDI", "CDD", "Stage", "Alternance", "Intérim", "Freelance", "Autre"].contains(contract) else {
            throw DraftValidationError.contract
        }
        guard (30...12000).contains(description.count) else { throw DraftValidationError.description }
        p_title = title; p_company = company; p_city = city
        p_contract_type = contract; p_description = description
    }

    private static func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ListingDraftInput: Encodable, Sendable {
    let p_category: String
    let p_title: String
    let p_description: String
    let p_city: String
    let p_price_xaf: Int64

    init(category: String, title: String, description: String, city: String, price: String) throws {
        let category = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let city = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ["Téléphones", "Informatique", "Électroménager", "Meubles", "Véhicules", "Mode", "Maison", "Matériel professionnel", "Autres"].contains(category) else {
            throw DraftValidationError.category
        }
        guard (3...160).contains(title.count) else { throw DraftValidationError.title }
        guard (10...12000).contains(description.count) else { throw DraftValidationError.description }
        guard (2...120).contains(city.count) else { throw DraftValidationError.city }
        let digits = price.replacingOccurrences(of: " ", with: "")
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              let amount = Int64(digits), (0...100_000_000_000).contains(amount) else {
            throw DraftValidationError.price
        }
        p_category = category; p_title = title; p_description = description
        p_city = city; p_price_xaf = amount
    }
}
