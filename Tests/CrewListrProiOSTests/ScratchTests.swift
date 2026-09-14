import XCTest
@testable import CrewListrPro

/// The three places this app writes a passport, or a crew list, in the clear.
///
/// Every one of them is a file that must not outlive the few seconds it is
/// needed for, and the failures that leave one behind are not the obvious ones:
/// not "the code forgot", but an error between writing and erasing, and the app
/// being killed while the share sheet is open — which iOS does routinely.
final class ScratchTests: XCTestCase {

    override func tearDown() {
        Scratch.sweepAll()
        super.tearDown()
    }

    func testEachItemGetsADirectoryOfItsOwn() throws {
        let first = try Scratch.make(.intake)
        let second = try Scratch.make(.intake)
        XCTAssertNotEqual(first, second, "two passports both called IMG_0042.jpg would collide")
    }

    /// The class the encrypted store's own directory takes. `.complete` would
    /// fail a write arriving from a share while the screen is off.
    ///
    /// Device only. The Simulator has no Data Protection — there is no
    /// passcode-derived key on a Mac — so it accepts the attribute and reports
    /// nothing back. Asserting here would be asserting that the Simulator is a
    /// phone, and passing would mean nothing.
    func testAScratchDirectoryIsEncryptedAtRest() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Data Protection is not implemented in the Simulator; run this on a device.")
        #else
        let directory = try Scratch.make(.crewList)
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path(percentEncoded: false))
        XCTAssertEqual(attributes[.protectionKey] as? FileProtectionType, .completeUnlessOpen)
        #endif
    }

    func testDiscardingTakesTheWholeDirectory() throws {
        let directory = try Scratch.make(.intake)
        let file = directory.appending(path: "passport.jpg")
        try Data("bytes".utf8).write(to: file)

        Scratch.discard(directory)

        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)))
    }

    /// The case the crew-list export is written against: two files are produced
    /// and the second can fail, so naming only the files that succeeded would
    /// leave the other one — a crew list carrying every passport number on the
    /// trip — beside it.
    func testDiscardingByFileTakesWhatWasWrittenBesideIt() throws {
        let directory = try Scratch.make(.crewList)
        let csv = directory.appending(path: "crew-list.csv")
        let stray = directory.appending(path: "crew-list-partial.pdf")
        try Data("names,numbers".utf8).write(to: csv)
        try Data("%PDF".utf8).write(to: stray)

        Scratch.discardContainers(of: [csv])

        XCTAssertFalse(FileManager.default.fileExists(atPath: stray.path(percentEncoded: false)),
                       "a partial write survived the cleanup of its own export")
    }

    func testDiscardingSomethingAlreadyGoneIsNotAFailure() throws {
        let directory = try Scratch.make(.intake)
        Scratch.discard(directory)
        Scratch.discard(directory)
    }

    /// What runs at launch. Everything in every scratch kind, because an import
    /// that was in flight did not survive the process either.
    func testTheLaunchSweepClearsEveryKind() throws {
        var files: [URL] = []
        for kind in Scratch.Kind.allCases {
            let file = try Scratch.make(kind).appending(path: "left-behind")
            try Data("bytes".utf8).write(to: file)
            files.append(file)
        }

        Scratch.sweepAll()

        for file in files {
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)),
                           "\(file.lastPathComponent) survived the launch sweep")
        }
    }

    func testSweepingWhenThereIsNothingToSweepIsNotAFailure() {
        Scratch.sweepAll()
        Scratch.sweepAll()
    }
}
