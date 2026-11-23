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

}
