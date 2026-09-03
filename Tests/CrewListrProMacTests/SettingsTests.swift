import Foundation
import XCTest
@testable import CrewListrProMac

/// The defaults an operator sets once, and the guards that stop a setting from
/// producing a crew list that cannot be written or read.
@MainActor
final class SettingsTests: XCTestCase {

    private var homes: [URL] = []

    override func tearDownWithError() throws {
        for home in homes { try? FileManager.default.removeItem(at: home) }
        homes = []
    }

    private func makeStore() throws -> CrewStore {
        CrewStore(secureStore: try TemporaryStore.make(in: &homes))
    }

    // MARK: - Shipped defaults

    /// The behaviour the operator asked for is what an untouched install does.
    func testTheShippedDefaultsAreASaturdayCharterWeek() {
        let settings = AppSettings()
        XCTAssertEqual(settings.charterStartWeekday, 7)
        XCTAssertEqual(settings.charterLengthDays, 7)
        XCTAssertTrue(settings.writesCSV)
        XCTAssertTrue(settings.writesPDF)
        XCTAssertEqual(settings.fileNamePrefix, "crew-list")
    }

    // MARK: - Guards

    func testAnImpossibleWeekdayIsBroughtBackIntoRange() {
        var settings = AppSettings()
        settings.charterStartWeekday = 0
        XCTAssertEqual(settings.normalised().charterStartWeekday, 7)

        settings.charterStartWeekday = 99
        XCTAssertEqual(settings.normalised().charterStartWeekday, 7)
    }

    func testACharterCannotBeZeroDaysOrAbsurdlyLong() {
        var settings = AppSettings()
        settings.charterLengthDays = 0
        XCTAssertEqual(settings.normalised().charterLengthDays, 1)

        settings.charterLengthDays = 5_000
        XCTAssertEqual(settings.normalised().charterLengthDays, AppSettings.longestCharterDays)
    }

    /// Turning both off would make Export a button that writes nothing.
    func testAtLeastOneFileIsAlwaysWritten() {
        var settings = AppSettings()
        settings.writesCSV = false
        settings.writesPDF = false

        let normalised = settings.normalised()
        XCTAssertTrue(normalised.writesPDF, "the printed form is the one a port authority is handed")
        XCTAssertFalse(normalised.writesCSV)
    }

    func testAFileNamePrefixIsMadeSafeForTheFilesystem() {
        var settings = AppSettings()
        settings.fileNamePrefix = "../../etc/passwd"
        let prefix = settings.normalised().fileNamePrefix

        XCTAssertFalse(prefix.contains("/"))
        XCTAssertFalse(prefix.contains(".."))
    }

    func testAnEmptyFileNamePrefixFallsBackRatherThanNamingAFileNothing() {
        var settings = AppSettings()
        settings.fileNamePrefix = "   "
        XCTAssertEqual(settings.normalised().fileNamePrefix, "crew-list")
    }

    func testTheVersionHistoryHasAFloorAndACeiling() {
        var settings = AppSettings()
        settings.versionsKept = 0
        XCTAssertGreaterThanOrEqual(settings.normalised().versionsKept, AppSettings.fewestVersionsKept)

        settings.versionsKept = 100_000
        XCTAssertLessThanOrEqual(settings.normalised().versionsKept, AppSettings.mostVersionsKept,
                                 "snapshots hold identity data; the history must not grow without limit")
    }

    /// Every write goes through `normalised()`, so a value that would break an
    /// export cannot reach the store even if something sets it directly.
    func testTheStoreNormalisesWhatItIsGiven() throws {
        let store = try makeStore()
        var settings = store.settings
        settings.charterLengthDays = -3
        settings.fileNamePrefix = ""

        store.updateSettings(settings)

        XCTAssertEqual(store.settings.charterLengthDays, 1)
        XCTAssertEqual(store.settings.fileNamePrefix, "crew-list")
    }

    // MARK: - What the settings actually change

    func testTheCharterWeekdayDecidesWhenANewTripStarts() throws {
        let store = try makeStore()
        var settings = store.settings
        settings.charterStartWeekday = 4   // Wednesday
        settings.charterLengthDays = 10
        store.updateSettings(settings)

        let id = store.createTrip()
        let trip = try XCTUnwrap(store.data.trips.first { $0.id == id })

        XCTAssertEqual(Calendar.current.component(.weekday, from: trip.departureDate), 4)
        XCTAssertEqual(Calendar.current.dateComponents([.day], from: trip.departureDate, to: trip.returnDate).day, 10)
    }

    func testTheFileNamePrefixReachesTheExportedFileName() {
        let boat = Boat(name: "S/Y ELPIDA")
        let trip = Trip(boatID: boat.id, departureDate: .now, returnDate: .now)

        let stem = ExportService.fileNameStem(boat: boat, trip: trip, prefix: "manifest")

        XCTAssertTrue(stem.hasPrefix("manifest-"), stem)
    }

    /// A store with one exportable trip, so the export settings can be tried
    /// against the thing they actually govern.
    private func makeExportableStore() throws -> (CrewStore, URL) {
        let store = try makeStore()
        let boatID = store.addBoat(named: "S/Y ELPIDA")
        var boat = try XCTUnwrap(store.boat(withID: boatID))
        boat.flag = "GRC"
        store.updateBoat(boat)
        let tripID = store.createTrip(boatID: boatID)

        let person = UUID()
        var document = CrewDocument(tripID: tripID, personID: person, originalName: "a.jpeg", encryptedFileName: "")
        document[.fullName] = "ANNA ERIKSSON"
        document[.documentNumber] = "L898902C3"
        document[.nationality] = "UTOPIAN"
        document[.birthDate] = "1974-08-12"
        document[.sex] = "F"
        for field in CrewField.requiredForExport { document.verifiedFields.insert(field.rawValue) }
        document.risk = .low
        store.data.people.append(CrewPerson(id: person, fullName: "ANNA ERIKSSON"))
        store.data.documents.append(document)
        store.data.assignments.append(CrewAssignment(tripID: tripID, personID: person, role: .skipper))

        let directory = FileManager.default.temporaryDirectory.appending(path: "crewlistr-settings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        homes.append(directory)
        return (store, directory)
    }

    func testTurningOffTheCSVWritesOnlyThePDF() throws {
        let (store, directory) = try makeExportableStore()
        var settings = store.settings
        settings.writesCSV = false
        store.updateSettings(settings)

        let written = try store.exportSelectedTrip(to: directory)

        XCTAssertEqual(written.map(\.pathExtension), ["pdf"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appending(path: "x.csv").path()))
    }

    func testTurningOffThePDFWritesOnlyTheCSV() throws {
        let (store, directory) = try makeExportableStore()
        var settings = store.settings
        settings.writesPDF = false
        store.updateSettings(settings)

        let written = try store.exportSelectedTrip(to: directory)

        XCTAssertEqual(written.map(\.pathExtension), ["csv"])
    }

    func testTheFileNamePrefixReachesTheWrittenFiles() throws {
        let (store, directory) = try makeExportableStore()
        var settings = store.settings
        settings.fileNamePrefix = "manifest"
        store.updateSettings(settings)

        let written = try store.exportSelectedTrip(to: directory)

        XCTAssertFalse(written.isEmpty)
        for url in written {
            XCTAssertTrue(url.lastPathComponent.hasPrefix("manifest-"), url.lastPathComponent)
        }
    }

    // MARK: - The standing export folder

    /// A path typed into a setting weeks ago. An unplugged drive or a renamed
    /// folder must send the export back to asking, not fail at the write.
    func testAnExportFolderThatIsNoLongerThereIsNotUsed() throws {
        let store = try makeStore()
        var settings = store.settings
        settings.exportFolderPath = "/Volumes/NoSuchDisk/CrewLists"
        store.updateSettings(settings)

        XCTAssertNil(store.standingExportFolder)
    }

    func testAFileIsNotAnExportFolder() throws {
        let store = try makeStore()
        let file = FileManager.default.temporaryDirectory.appending(path: "crewlistr-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        var settings = store.settings
        settings.exportFolderPath = file.path(percentEncoded: false)
        store.updateSettings(settings)

        XCTAssertNil(store.standingExportFolder)
    }

    func testAWritableFolderIsUsed() throws {
        let store = try makeStore()
        let directory = FileManager.default.temporaryDirectory.appending(path: "crewlistr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        homes.append(directory)

        var settings = store.settings
        settings.exportFolderPath = directory.path(percentEncoded: false)
        store.updateSettings(settings)

        XCTAssertEqual(store.standingExportFolder?.standardizedFileURL, directory.standardizedFileURL)
    }

    func testNoFolderSetMeansAskEveryTime() throws {
        let store = try makeStore()
        XCTAssertNil(store.standingExportFolder)
    }

    // MARK: - Persistence

    func testSettingsSurviveAReopen() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "CrewListrSettings-\(UUID().uuidString)")
        homes.append(root)

        let store = CrewStore(secureStore: try TemporaryStore.reopen(root))
        await store.load()
        var settings = store.settings
        settings.defaultFlag = "GRC"
        settings.charterLengthDays = 14
        store.updateSettings(settings)
        await store.flushForTesting()

        let reopened = CrewStore(secureStore: try TemporaryStore.reopen(root))
        await reopened.load()

        XCTAssertEqual(reopened.settings.defaultFlag, "GRC")
        XCTAssertEqual(reopened.settings.charterLengthDays, 14)
    }

    /// The hard rule of this store: a payload written before a field existed
    /// must still open. Settings are absent from every store written so far.
    func testAStoreWrittenBeforeSettingsExistedStillOpens() throws {
        let legacy = """
        {"schemaVersion":2,"boats":[],"trips":[],"people":[],"documents":[],"assignments":[]}
        """
        let data = try JSONDecoder().decode(AppData.self, from: Data(legacy.utf8))

        XCTAssertEqual(data.settings, AppSettings())
        XCTAssertTrue(data.decodingLosses.isEmpty)
    }

    /// The hand-written decoder is load-bearing and easy to lose: `AppData`
    /// wraps it in `try?`, so if a future field used a bare `decode` the whole
    /// blob would throw, be replaced with defaults, and the next save would
    /// write those over the operator's export folder, prefix, default yacht and
    /// version depth — silently. A payload holding one key proves each field
    /// falls back on its own rather than the object failing as a whole.
    func testAPartialSettingsPayloadKeepsWhatItHasAndDefaultsTheRest() throws {
        let legacy = """
        {"schemaVersion":3,"settings":{"charterLengthDays":10},"boats":[],"trips":[],"people":[],"documents":[],"assignments":[]}
        """
        let data = try JSONDecoder().decode(AppData.self, from: Data(legacy.utf8))

        XCTAssertEqual(data.settings.charterLengthDays, 10, "the one value present was lost")
        XCTAssertEqual(data.settings.charterStartWeekday, 7)
        XCTAssertEqual(data.settings.versionsKept, AppSettings.defaultVersionsKept)
        XCTAssertEqual(data.settings.fileNamePrefix, AppSettings.defaultFileNamePrefix)
        XCTAssertTrue(data.settings.writesPDF)
        XCTAssertNil(data.settings.defaultBoatID)
    }

    /// Out-of-range values in a hand-edited or half-written payload are brought
    /// back on the way in, not trusted at the point of use.
    func testASettingsPayloadWithAnImpossibleValueIsNormalisedOnDecode() throws {
        let legacy = """
        {"schemaVersion":3,"settings":{"charterLengthDays":-4,"charterStartWeekday":42,"fileNamePrefix":"../../etc"},"boats":[],"trips":[],"people":[],"documents":[],"assignments":[]}
        """
        let data = try JSONDecoder().decode(AppData.self, from: Data(legacy.utf8))

        XCTAssertEqual(data.settings.charterLengthDays, 1)
        XCTAssertEqual(data.settings.charterStartWeekday, 7)
        XCTAssertFalse(data.settings.fileNamePrefix.contains("/"))
    }

    /// An unreadable settings blob costs the settings, not the operator's trips.
    func testUnreadableSettingsDoNotTakeTheStoreDown() throws {
        let legacy = """
        {"schemaVersion":3,"settings":"nonsense","boats":[],"trips":[],"people":[],"documents":[],"assignments":[]}
        """
        let data = try JSONDecoder().decode(AppData.self, from: Data(legacy.utf8))

        XCTAssertEqual(data.settings, AppSettings())
    }
}
