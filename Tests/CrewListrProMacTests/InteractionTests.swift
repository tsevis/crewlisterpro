import AppKit
import SwiftUI
import XCTest
@testable import CrewListrProMac

/// The interactions themselves: a value typed into a field and tabbed out of, a
/// control clicked, and what the screen shows afterwards.
///
/// Every other suite here calls the store directly, which proves the store is
/// right and proves nothing about whether the control is wired to it. These
/// press the control. See `Harness` for what that can and cannot reach.
@MainActor
final class InteractionTests: XCTestCase {

    /// `CrewStore(secureStore: nil)` deliberately, and it is the only store
    /// shape these tests can use.
    ///
    /// A store with a database behind it finishes opening on a `Task` spawned
    /// in its initialiser, and this harness spins the run loop between every
    /// input — so that load lands in the middle of a test and replaces the
    /// seeded `data` with the empty database, after the test has already put a
    /// yacht in it. With no store there is no load and no `persist`, the state
    /// transitions are exactly the ones the screen reads, and nothing touches
    /// disk.
    private func makeStore() -> CrewStore {
        CrewStore(secureStore: nil)
    }

    // MARK: - Editing a yacht in the Fleet

    private func fleetHarness(_ store: CrewStore, boatID: UUID) -> Harness<some View> {
        Harness(FleetDetailProbe(boatID: boatID).environment(store))
    }

    func testTypingAYachtNameAndLeavingTheFieldSavesIt() throws {
        let store = makeStore()
        let id = store.addBoat(named: "S/Y ELPIDA")
        let harness = fleetHarness(store, boatID: id)

        harness.type("S/Y ANEMOS", intoFieldAt: 0)

        XCTAssertEqual(store.boat(withID: id)?.name, "S/Y ANEMOS")
    }

    /// The flag is uppercased on the way out, and the box has to show the
    /// uppercased value rather than what was typed.
    func testAFlagIsSquaredUpWhenTheFieldIsLeft() throws {
        let store = makeStore()
        let id = store.addBoat(named: "S/Y ELPIDA")
        let harness = fleetHarness(store, boatID: id)

        harness.type("grc", intoFieldAt: 1)

        XCTAssertEqual(store.boat(withID: id)?.flag, "GRC")
        XCTAssertEqual(harness.text(ofFieldAt: 1), "GRC")
    }

    /// The bug this harness exists for. `CrewStore.updateBoat` refuses a blank
    /// name, so the store is right — but the field showed the empty box it was
    /// left in, beside a preview still printing the real name, and the operator
    /// had every reason to think the name was gone.
    func testEmptyingAYachtNameLeavesTheBoxShowingTheNameThatIsStored() throws {
        let store = makeStore()
        let id = store.addBoat(named: "S/Y ELPIDA")
        let harness = fleetHarness(store, boatID: id)

        harness.type("", intoFieldAt: 0)

        XCTAssertEqual(store.boat(withID: id)?.name, "S/Y ELPIDA", "a blank name must not overwrite a real one")
        XCTAssertEqual(harness.text(ofFieldAt: 0), "S/Y ELPIDA", "the box is showing a name that was never stored")
    }

    func testWhitespaceTypedAroundAValueIsNotLeftInTheBox() throws {
        let store = makeStore()
        let id = store.addBoat(named: "S/Y ELPIDA")
        let harness = fleetHarness(store, boatID: id)

        harness.type("   PIRAEUS   ", intoFieldAt: 2)

        XCTAssertEqual(store.boat(withID: id)?.registrationPort, "PIRAEUS")
        XCTAssertEqual(harness.text(ofFieldAt: 2), "PIRAEUS")
    }

    // MARK: - Editing a document in the review pane

    private func reviewHarness(_ store: CrewStore) -> (Harness<some View>, CrewDocument) {
        let tripID = store.createTrip()
        let personID = UUID()
        var document = CrewDocument(tripID: tripID, personID: personID, originalName: "a.jpeg", encryptedFileName: "")
        document[.fullName] = "GIULIA ROSSI"
        document[.documentNumber] = "YA9876543"
        document[.nationality] = "ITALIAN"
        document[.birthDate] = "1995-07-04"
        document[.sex] = "F"
        store.data.people.append(CrewPerson(id: personID, fullName: "GIULIA ROSSI"))
        store.data.documents.append(document)
        store.data.assignments.append(CrewAssignment(tripID: tripID, personID: personID, role: .skipper))
        store.selectedDocumentID = document.id
        return (Harness(ReviewPaneProbe(documentID: document.id).environment(store),
                        size: CGSize(width: 640, height: 900)), document)
    }

    /// Field order follows `CrewField.reviewOrder`: full name, document no.,
    /// document type, nationality, date of birth, sex, date of expiry.
    private let birthDateField = 4

    func testADateTypedTheWayThePassportPrintsItIsStoredAsISO() throws {
        let store = makeStore()
        let (harness, document) = reviewHarness(store)

        harness.type("20 oct 1972", intoFieldAt: birthDateField)

        XCTAssertEqual(store.data.documents.first { $0.id == document.id }?[.birthDate], "1972-10-20")
    }

    func testADateTypedInLowercaseIsShownBackTheWayThisAppWritesIt() throws {
        let store = makeStore()
        let (harness, _) = reviewHarness(store)

        harness.type("20 oct 1972", intoFieldAt: birthDateField)

        XCTAssertEqual(harness.text(ofFieldAt: birthDateField), "20 OCT 1972")
    }

    func testADateStillTypedAsISOIsAccepted() throws {
        let store = makeStore()
        let (harness, document) = reviewHarness(store)

        harness.type("1972-10-20", intoFieldAt: birthDateField)

        XCTAssertEqual(store.data.documents.first { $0.id == document.id }?[.birthDate], "1972-10-20")
        XCTAssertEqual(harness.text(ofFieldAt: birthDateField), "20 OCT 1972")
    }

    /// A value that parses as no date at all is stored as typed, so the
    /// validation line under the field can object to it — rather than the field
    /// quietly discarding what the operator entered.
    func testAnUnreadableDateIsKeptSoValidationCanObjectToIt() throws {
        let store = makeStore()
        let (harness, document) = reviewHarness(store)

        harness.type("20 XXX 1972", intoFieldAt: birthDateField)

        let stored = try XCTUnwrap(store.data.documents.first { $0.id == document.id })
        XCTAssertEqual(stored[.birthDate], "20 XXX 1972")
        XCTAssertTrue(stored.validation(of: .birthDate).isBlocking)
    }

    /// Editing a confirmed value has to retract its confirmation, or a
    /// correction reaches a crew list unchecked.
    func testEditingAConfirmedFieldRetractsItsConfirmation() throws {
        let store = makeStore()
        let (harness, document) = reviewHarness(store)
        store.setVerified(true, field: .birthDate, on: document.id)
        XCTAssertTrue(try XCTUnwrap(store.data.documents.first { $0.id == document.id }).isVerified(.birthDate))

        harness.type("16 dec 1984", intoFieldAt: birthDateField)

        XCTAssertFalse(try XCTUnwrap(store.data.documents.first { $0.id == document.id }).isVerified(.birthDate))
    }

    func testTypingTheSkippersEmailSavesIt() throws {
        let store = makeStore()
        let (harness, document) = reviewHarness(store)

        // The email field is the last editable one on the skipper's pane.
        let last = harness.fields().count - 1
        harness.type("anna@example.com", intoFieldAt: last)

        XCTAssertEqual(store.email(forPersonID: document.personID), "anna@example.com")
    }
}

extension InteractionTests {

    // MARK: - Editing the defaults in Settings
    //
    // Field order on that screen: the new-yacht flag, its port of registry,
    // then the export file-name prefix.

    func testTypingADefaultFlagInLowercaseStoresItUppercased() throws {
        let store = makeStore()
        let harness = Harness(SettingsScreen().environment(store), size: CGSize(width: 900, height: 1400))

        harness.type("grc", intoFieldAt: 0)

        XCTAssertEqual(store.settings.defaultFlag, "GRC")
        XCTAssertEqual(harness.text(ofFieldAt: 0), "GRC")
    }

    /// The second place the stale-box bug lived. "crew list" is normalised to
    /// "crew-list", which is what was already stored — so nothing changes,
    /// nothing fires, and the field used to sit there reading "crew list" next
    /// to an example file name reading `crew-list-…pdf`.
    func testAFileNamePrefixThatNormalisesToWhatIsStoredStillShowsTheStoredForm() throws {
        let store = makeStore()
        let harness = Harness(SettingsScreen().environment(store), size: CGSize(width: 900, height: 1400))

        harness.type("crew list", intoFieldAt: 2)

        XCTAssertEqual(store.settings.fileNamePrefix, "crew-list")
        XCTAssertEqual(harness.text(ofFieldAt: 2), "crew-list", "the box is showing a value that was never stored")
    }

    func testAFileNamePrefixIsMadeSafeBeforeItIsStored() throws {
        let store = makeStore()
        let harness = Harness(SettingsScreen().environment(store), size: CGSize(width: 900, height: 1400))

        harness.type("../../etc/passwd", intoFieldAt: 2)

        let prefix = store.settings.fileNamePrefix
        XCTAssertFalse(prefix.contains("/"))
        XCTAssertFalse(prefix.contains(".."))
        XCTAssertEqual(harness.text(ofFieldAt: 2), prefix)
    }

    // MARK: - A name the crew list cannot carry

    /// Typed, stored and objected to — rather than dropped on the way in, which
    /// would leave the operator staring at the old value wondering what they
    /// did wrong.
    func testANameWithDigitsIsKeptAndBlocksTheExport() throws {
        let store = makeStore()
        let (harness, document) = reviewHarness(store)

        harness.type("ANNA 3RIKSSON", intoFieldAt: 0)

        let stored = try XCTUnwrap(store.data.documents.first { $0.id == document.id })
        XCTAssertEqual(stored[.fullName], "ANNA 3RIKSSON")
        XCTAssertTrue(stored.validation(of: .fullName).isBlocking)
        XCTAssertFalse(stored.canExport())
    }
}

// MARK: - Views under test

/// Re-reads the yacht from the store on every render, exactly as `FleetScreen`
/// does.
///
/// Handing `FleetDetail` a `Boat` captured once would test something the app
/// never does: the value would never change, so the field could not be
/// corrected from the store and every "what does the box show afterwards" test
/// would be measuring the harness instead of the screen.
private struct FleetDetailProbe: View {
    @Environment(CrewStore.self) private var store
    let boatID: UUID

    var body: some View {
        if let boat = store.boat(withID: boatID) {
            FleetDetail(boat: boat, onRetire: {}, onRestore: {}, onDuplicate: {}, onDelete: {})
        }
    }
}

/// The same for the review pane, which `PeopleScreen` also feeds from
/// `store.selectedDocument` on each render.
private struct ReviewPaneProbe: View {
    @Environment(CrewStore.self) private var store
    let documentID: UUID

    var body: some View {
        if let document = store.data.documents.first(where: { $0.id == documentID }) {
            FieldReviewPane(document: document)
        }
    }
}
