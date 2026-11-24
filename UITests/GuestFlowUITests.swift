import XCTest

final class GuestFlowUITests: XCTestCase {
    func testGuestCanBrowseAndOpenSignIn() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.navigationBars["Emploi"].waitForExistence(timeout: 20),
                      "L'accueil public Emploi doit apparaître après le splash.")
        let listingTab = app.tabBars.buttons["Annonces"]
        XCTAssertTrue(listingTab.waitForExistence(timeout: 5))
        listingTab.tap()
        XCTAssertTrue(app.navigationBars["Annonces"].waitForExistence(timeout: 5))

        let publishTab = app.tabBars.buttons["Publier"]
        XCTAssertTrue(publishTab.waitForExistence(timeout: 5))
        publishTab.tap()
        let signIn = app.buttons["Se connecter"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 5))
        signIn.tap()
        XCTAssertTrue(app.textFields["Adresse e-mail"].waitForExistence(timeout: 5))
    }
    func testRegistrationKeyboardMovesBetweenNameFields() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.navigationBars["Emploi"].waitForExistence(timeout: 20))
        let profile = app.tabBars.buttons["Profil"]
        XCTAssertTrue(profile.waitForExistence(timeout: 20))
        profile.tap()
        let signIn = app.buttons["Se connecter"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 5))
        signIn.tap()
        let create = app.buttons["Créer un compte"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.tap()
        let firstName = app.textFields["Prénom"]
        let lastName = app.textFields["Nom"]
        XCTAssertTrue(firstName.waitForExistence(timeout: 5))
        firstName.tap()
        firstName.typeText("Marie\n")
        app.typeText("Bakala")
        XCTAssertEqual(lastName.value as? String, "Bakala")
    }

    func testVisitorCanReadCommentsAndRequestSignIn() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.navigationBars["Emploi"].waitForExistence(timeout: 20))
        let jobs = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "luka-job-"))
        guard jobs.firstMatch.waitForExistence(timeout: 20) else {
            throw XCTSkip("Aucune offre publique disponible pour le test des commentaires.")
        }
        jobs.firstMatch.tap()
        let comments = app.staticTexts["Commentaires"]
        for _ in 0..<5 {
            if comments.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(comments.waitForExistence(timeout: 10))
        let draft = app.descendants(matching: .any).matching(identifier: "luka-comment-draft").firstMatch
        XCTAssertTrue(draft.waitForExistence(timeout: 15), "Les commentaires publics doivent se charger.")
        if !draft.isHittable { app.swipeUp() }
        draft.tap()
        draft.typeText("Test de parcours")
        let publish = app.buttons["Publier le commentaire"]
        if !publish.isHittable { app.swipeUp() }
        XCTAssertTrue(publish.waitForExistence(timeout: 5))
        publish.tap()
        XCTAssertTrue(app.textFields["Adresse e-mail"].waitForExistence(timeout: 5),
                      "Le visiteur doit pouvoir se connecter sans quitter la publication.")
    }


}
