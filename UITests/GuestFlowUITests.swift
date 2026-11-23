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
}
