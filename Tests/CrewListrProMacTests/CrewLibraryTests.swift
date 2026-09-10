import Foundation
import XCTest
@testable import CrewListrProMac

/// People this operator has cleared before, kept apart from any one charter.
///
/// A charter base runs the same skippers all season. Every trip made them
/// photograph the same passport again, upload it again and confirm the same
/// seven fields again — and the previous copy was erased with the trip it
/// belonged to, so the work was not merely repeated, it was repeated from
/// nothing. The library is where a person outlives a charter: their confirmed
/// details and their scan, in a folder of their own, ready to be put on the
/// next trip without the operator going back to WhatsApp for a photograph they
/// already had.
///
/// What it deliberately does NOT do is skip the review. A person added from the
/// library arrives with their document attached and every field waiting to be
/// confirmed, exactly as an imported one does — the saving is the upload, not
/// the checking.
@MainActor
final class CrewLibraryTests: XCTestCase {

    private var homes: [URL] = []

    override func tearDownWithError() throws {
        for home in homes { try? FileManager.default.removeItem(at: home) }
        homes = []
    }

    private func makeStore() throws -> (CrewStore, SecureStore) {
        let secure = try TemporaryStore.make(in: &homes)
        return (CrewStore(secureStore: secure), secure)
    }

    /// A trip with one fully confirmed passport on it.
    @discardableResult
    private func reviewedDocument(in store: CrewStore, secure: SecureStore,
                                  name: String = "YUKI NAKAMURA",
                                  number: String = "TR1234567") async throws -> CrewDocument {
        let tripID = store.selectedTripID ?? store.createTrip()
        let scan = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).jpeg")
        try Data("a passport photograph".utf8).write(to: scan)
        defer { try? FileManager.default.removeItem(at: scan) }

        let person = CrewPerson(fullName: name)
        var document = CrewDocument(tripID: tripID, personID: person.id,
                                    originalName: "passport.jpeg", encryptedFileName: "")
        document.encryptedFileName = try await secure.importOriginal(from: scan, documentID: document.id)
        document[.fullName] = name
        document[.documentNumber] = number
        document[.documentType] = "passport"
        document[.nationality] = "JPN"
        document[.birthDate] = "1984-12-16"
        document[.sex] = "F"
        document[.expiryDate] = "2034-12-16"
        document.verifiedFields = Set(CrewField.requiredForExport.map(\.rawValue))
        document.risk = .low

        store.data.people.append(person)
        store.data.documents.append(document)
        store.data.assignments.append(CrewAssignment(tripID: tripID, personID: person.id,
                                                     role: .skipper, email: "yuki@example.com"))
        return document
    }

    // MARK: - Keeping someone

    func testKeepingSomeoneRemembersWhatWasConfirmed() async throws {
        let (store, secure) = try makeStore()
        let document = try await reviewedDocument(in: store, secure: secure)

        let kept = await store.keepInCrewLibrary(documentID: document.id)
        XCTAssertTrue(kept)

        let saved = try XCTUnwrap(store.crewLibrary.first)
        XCTAssertEqual(saved.fullName, "YUKI NAKAMURA")
        XCTAssertEqual(saved.documentNumber, "TR1234567")
        XCTAssertEqual(saved[.nationality], "JPN")
        XCTAssertEqual(saved[.birthDate], "1984-12-16")
        XCTAssertEqual(saved.role, .skipper, "the library is mostly skippers; it has to remember which")
        XCTAssertEqual(saved.email, "yuki@example.com")
        XCTAssertNotNil(saved.confirmedAt, "a fully confirmed document was kept as though it were not")
    }

    /// Keeping someone mid-review saves the typing, and says nothing about a
    /// checking that has not happened. The pane of a document added from an
    /// entry like this must not read "confirmed on 3 August".
    func testSomeoneKeptBeforeTheReviewWasFinishedClaimsNoConfirmation() async throws {
        let (store, secure) = try makeStore()
        var document = try await reviewedDocument(in: store, secure: secure)
        document.verifiedFields = []
        store.updateDocument(document)

        let kept = await store.keepInCrewLibrary(documentID: document.id)
        XCTAssertTrue(kept, "half-confirmed is still worth keeping — it saves the typing")

        XCTAssertNil(store.crewLibrary.first?.confirmedAt)

        let next = store.createTrip()
        let saved = try XCTUnwrap(store.crewLibrary.first)
        _ = await store.addFromCrewLibrary(saved.id)
        let added = try XCTUnwrap(store.data.documents.first { $0.tripID == next })
        XCTAssertFalse(added.riskReasons.contains { $0.contains("were confirmed against this scan on") },
                       "the pane vouched for a check nobody made")
    }

    /// The point of the whole feature: the scan is kept, in the library's own
    /// folder, so the next charter does not ask for the photograph again.
    func testKeepingSomeoneKeepsTheirScan() async throws {
        let (store, secure) = try makeStore()
        let document = try await reviewedDocument(in: store, secure: secure)

        let kept = await store.keepInCrewLibrary(documentID: document.id)
        XCTAssertTrue(kept)

        let saved = try XCTUnwrap(store.crewLibrary.first)
        XCTAssertFalse(saved.encryptedFileName.isEmpty)
        let scan = try await secure.readCrewOriginal(named: saved.encryptedFileName)
        XCTAssertEqual(String(decoding: scan, as: UTF8.self), "a passport photograph")
    }

    /// The library's copy is its own. Erasing a charter's documents is a thing
    /// an operator does at the end of a season, and it must not empty the
    /// library along with it.
    func testDeletingTheTripLeavesTheLibraryCopyAlone() async throws {
        let (store, secure) = try makeStore()
        let document = try await reviewedDocument(in: store, secure: secure)
        _ = await store.keepInCrewLibrary(documentID: document.id)
        let saved = try XCTUnwrap(store.crewLibrary.first)

        store.deleteTrip(document.tripID)

        XCTAssertEqual(store.crewLibrary.count, 1)
        let scan = try await secure.readCrewOriginal(named: saved.encryptedFileName)
        XCTAssertEqual(String(decoding: scan, as: UTF8.self), "a passport photograph")
    }

    /// The same passport kept twice is one person, not two rows saying the same
    /// thing with the older one slowly going out of date.
    func testKeepingTheSamePassportAgainUpdatesTheOneEntry() async throws {
        let (store, secure) = try makeStore()
        let first = try await reviewedDocument(in: store, secure: secure)
        _ = await store.keepInCrewLibrary(documentID: first.id)

        store.createTrip()
        let again = try await reviewedDocument(in: store, secure: secure, name: "YUKI NAKAMURA-JONES")
        _ = await store.keepInCrewLibrary(documentID: again.id)

        XCTAssertEqual(store.crewLibrary.count, 1)
        XCTAssertEqual(store.crewLibrary.first?.fullName, "YUKI NAKAMURA-JONES", "the newer confirmation lost")
    }

    /// Nothing worth reusing. A row with no name and no number is a row nobody
    /// can pick out of a list, and re-adding it would put an empty document on
    /// a trip.
    func testADocumentWithNoNameOrNumberIsNotKept() async throws {
        let (store, secure) = try makeStore()
        var document = try await reviewedDocument(in: store, secure: secure)
        document[.fullName] = ""
        document[.documentNumber] = ""
        store.updateDocument(document)

        let refused = await store.keepInCrewLibrary(documentID: document.id)
        XCTAssertFalse(refused)
        XCTAssertTrue(store.crewLibrary.isEmpty)
        XCTAssertNotNil(store.errorMessage, "the operator was told nothing")
    }

    // MARK: - Using someone again

    func testAddingSomeoneToATripBringsTheirFieldsAndTheirScan() async throws {
        let (store, secure) = try makeStore()
        let document = try await reviewedDocument(in: store, secure: secure)
        _ = await store.keepInCrewLibrary(documentID: document.id)
        let saved = try XCTUnwrap(store.crewLibrary.first)

        let next = store.createTrip()
        let wasAdded = await store.addFromCrewLibrary(saved.id)
        XCTAssertTrue(wasAdded)

        let added = try XCTUnwrap(store.data.documents.first { $0.tripID == next })
        XCTAssertEqual(added[.fullName], "YUKI NAKAMURA")
        XCTAssertEqual(added[.documentNumber], "TR1234567")
        XCTAssertEqual(added[.birthDate], "1984-12-16")
        XCTAssertFalse(added.encryptedFileName.isEmpty, "the scan did not come with them")
        let image = try await secure.readOriginal(named: added.encryptedFileName)
        XCTAssertEqual(String(decoding: image, as: UTF8.self), "a passport photograph")
    }

    /// The gate is the whole product. A person who has been confirmed before is
    /// a person whose fields are already typed — not a person whose crew list
    /// nobody has to look at.
    func testSomeoneAddedFromTheLibraryStillHasToBeConfirmed() async throws {
        let (store, secure) = try makeStore()
        let document = try await reviewedDocument(in: store, secure: secure)
        _ = await store.keepInCrewLibrary(documentID: document.id)
        let saved = try XCTUnwrap(store.crewLibrary.first)

        let next = store.createTrip()
        _ = await store.addFromCrewLibrary(saved.id)

        let added = try XCTUnwrap(store.data.documents.first { $0.tripID == next })
        XCTAssertTrue(added.verifiedFields.isEmpty)
        XCTAssertFalse(added.canExport())
        XCTAssertFalse(added.riskReasons.isEmpty, "the pane must say where these values came from")
    }

    /// A separate copy, so deleting the trip afterwards shreds that copy and
    /// leaves the library's.
    func testTheTripGetsItsOwnCopyOfTheScan() async throws {
        let (store, secure) = try makeStore()
        let document = try await reviewedDocument(in: store, secure: secure)
        _ = await store.keepInCrewLibrary(documentID: document.id)
        let saved = try XCTUnwrap(store.crewLibrary.first)
        let next = store.createTrip()
        _ = await store.addFromCrewLibrary(saved.id)
        let added = try XCTUnwrap(store.data.documents.first { $0.tripID == next })

        store.deleteTrip(next)

        let scan = try await secure.readCrewOriginal(named: saved.encryptedFileName)
        XCTAssertEqual(String(decoding: scan, as: UTF8.self), "a passport photograph")
        await XCTAssertThrowsErrorAsync(try await secure.readOriginal(named: added.encryptedFileName),
                                        "the trip's copy outlived the trip")
    }

    func testTheSamePersonIsNotAddedToATripTwice() async throws {
        let (store, secure) = try makeStore()
        let document = try await reviewedDocument(in: store, secure: secure)
        _ = await store.keepInCrewLibrary(documentID: document.id)
        let saved = try XCTUnwrap(store.crewLibrary.first)
        let next = store.createTrip()
        _ = await store.addFromCrewLibrary(saved.id)

        let refused = await store.addFromCrewLibrary(saved.id)
        XCTAssertFalse(refused)
        XCTAssertEqual(store.data.documents.count { $0.tripID == next }, 1)
    }

    func testAddingSomeoneWithNoTripSelectedSaysSo() async throws {
        let (store, secure) = try makeStore()
        let document = try await reviewedDocument(in: store, secure: secure)
        _ = await store.keepInCrewLibrary(documentID: document.id)
        let saved = try XCTUnwrap(store.crewLibrary.first)
        store.deleteTrip(document.tripID)
        store.selectedTripID = nil

        let refused = await store.addFromCrewLibrary(saved.id)
        XCTAssertFalse(refused)
        XCTAssertNotNil(store.errorMessage)
    }

    /// The skipper of the last charter is the skipper of the next one, unless
    /// the operator says otherwise — the library remembers which.
    func testSomeoneSavedAsSkipperComesBackAsSkipper() async throws {
        let (store, secure) = try makeStore()
        let document = try await reviewedDocument(in: store, secure: secure)
        _ = await store.keepInCrewLibrary(documentID: document.id)
        let saved = try XCTUnwrap(store.crewLibrary.first)

        let next = store.createTrip()
        _ = await store.addFromCrewLibrary(saved.id)

        let added = try XCTUnwrap(store.data.documents.first { $0.tripID == next })
        XCTAssertEqual(store.role(forPersonID: added.personID), .skipper)
        XCTAssertEqual(store.data.assignments.first { $0.personID == added.personID }?.email,
                       "yuki@example.com")
    }

    // MARK: - Forgetting someone

    /// An app that holds passport scans has to be able to forget them, and the
    /// library is now a second place they are held.
    func testRemovingSomeoneErasesTheirScan() async throws {
        let (store, secure) = try makeStore()
        let document = try await reviewedDocument(in: store, secure: secure)
        _ = await store.keepInCrewLibrary(documentID: document.id)
        let saved = try XCTUnwrap(store.crewLibrary.first)

        await store.removeFromCrewLibrary(saved.id)

        XCTAssertTrue(store.crewLibrary.isEmpty)
        await XCTAssertThrowsErrorAsync(try await secure.readCrewOriginal(named: saved.encryptedFileName),
                                        "the library's scan is still on disk")
    }

    // MARK: - Storage

    func testTheLibrarySurvivesAReopen() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "CrewListrTest-\(UUID().uuidString)")
        homes.append(root)
        let secure = try TemporaryStore.reopen(root)
        let store = CrewStore(secureStore: secure)
        // `persist()` refuses until the store has read itself off disk, so an
        // empty in-memory state can never be written over real data.
        await store.load()
        let document = try await reviewedDocument(in: store, secure: secure)
        _ = await store.keepInCrewLibrary(documentID: document.id)
        await store.flushForTesting()

        let reopened = try await TemporaryStore.reopen(root).load()

        XCTAssertEqual(reopened.savedCrew.count, 1)
        XCTAssertEqual(reopened.savedCrew.first?.fullName, "YUKI NAKAMURA")
    }

    /// A store written before the library existed opens with an empty one, not
    /// as a store that cannot be read.
    func testAPayloadWrittenBeforeTheLibraryExistedStillDecodes() throws {
        let legacy = """
        {"schemaVersion":3,"boats":[],"trips":[],"people":[],"documents":[],"assignments":[]}
        """
        let data = try JSONDecoder().decode(AppData.self, from: Data(legacy.utf8))

        XCTAssertTrue(data.savedCrew.isEmpty)
        XCTAssertTrue(data.decodingLosses.isEmpty, "an absent library is not damage")
    }
}

/// `XCTAssertThrowsError` has no async form.
func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail(message.isEmpty ? "expected an error" : message, file: file, line: line)
    } catch {
        // Expected.
    }
}
