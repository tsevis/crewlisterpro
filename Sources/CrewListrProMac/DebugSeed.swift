import Foundation

#if DEBUG
/// Fictional data for a UI test to click on, and for nothing else.
///
/// A UI test drives the real binary, and the parts of this app worth clicking —
/// the confirm controls, the client checkbox, the role picker — only exist once
/// a trip has documents on it. Those arrive by importing photographs of
/// passports, which a test cannot conjure and must not use real ones for.
///
/// So the app can be asked to start from a known fleet instead. Compiled only
/// into a debug build, which `xcodebuild test` produces and the shipped disk
/// image never is, and applied only to a store that is empty — it can add to
/// nothing and overwrite nothing.
///
/// The people are invented. The document numbers are the ICAO specimen values
/// already used by this project's fixtures, so no real identity document is
/// written into a test store either.
enum DebugSeed {
    static let variable = "CREWLISTR_SEED"

    static var isRequested: Bool {
        ProcessInfo.processInfo.environment[variable] == "demo"
    }

    /// Returns seeded data, or nil when there is nothing to do.
    static func seeded(onto existing: AppData) -> AppData? {
        guard isRequested, existing.trips.isEmpty, existing.boats.isEmpty else { return nil }

        let elpida = Boat(name: "S/Y ELPIDA", flag: "GRC", registrationPort: "PIRAEUS", registrationNumber: "GR-1187-P")
        let aurora = Boat(name: "M/Y AURORA", flag: "GRC", registrationPort: "LAVRIO", registrationNumber: "GR-4471-P")
        let week = VoyageDate.charterWeek()
        let trip = Trip(boatID: elpida.id, departureDate: week.departure, returnDate: week.arrival)

        let crew = [
            ("ANNA MARIA ERIKSSON", "L898902C3", "UTOPIAN", "1974-08-12", "F", "2032-04-15"),
            ("NIKOLAOS PAPADOPOULOS", "AB1234567", "GREEK", "1983-02-19", "M", "2031-06-30"),
        ]

        var people: [CrewPerson] = []
        var documents: [CrewDocument] = []
        var assignments: [CrewAssignment] = []
        for (index, member) in crew.enumerated() {
            let person = CrewPerson(fullName: member.0)
            var document = CrewDocument(tripID: trip.id, personID: person.id,
                                        originalName: "specimen-\(member.1).png", encryptedFileName: "")
            document[.fullName] = member.0
            document[.documentNumber] = member.1
            document[.documentType] = "passport"
            document[.nationality] = member.2
            document[.birthDate] = member.3
            document[.sex] = member.4
            document[.expiryDate] = member.5
            people.append(person)
            documents.append(document)
            assignments.append(CrewAssignment(tripID: trip.id, personID: person.id,
                                              role: index == 0 ? .skipper : .passenger))
        }

        return AppData(boats: [elpida, aurora], trips: [trip], people: people,
                       documents: documents, assignments: assignments)
    }
}
#endif
