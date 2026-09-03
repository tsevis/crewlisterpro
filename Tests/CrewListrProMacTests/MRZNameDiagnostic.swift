import Foundation
import XCTest
@testable import CrewListrProMac

/// Why a name did not come out of a document already in the live store.
///
/// Every field except the name comes from line 2 of the machine-readable zone;
/// the name is the only thing line 1 carries. So a document with a perfect
/// number, nationality, birth date, sex and expiry — and no name — is a
/// document whose line 2 read cleanly and whose line 1 was rejected. This says
/// which rejection it was.
///
/// Reports structure only: how long each candidate line was, how many digits it
/// contained, whether it had the `<<` that separates surname from given names.
/// It never prints a name, a document number or any line's text. The operator's
/// passports stay theirs.
///
/// Opt-in and read-only: set CREWLISTR_DIAGNOSE_NAMES=1.
final class MRZNameDiagnostic: XCTestCase {

    func testWhyNamesAreMissing() async throws {
        guard ProcessInfo.processInfo.environment["CREWLISTR_DIAGNOSE_NAMES"] == "1" else {
            throw XCTSkip("Set CREWLISTR_DIAGNOSE_NAMES=1 to diagnose the live store's name extraction.")
        }
        let store = try SecureStore()
        let data = try await store.load()
        let alphabet = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789<")

        print("documents: \(data.documents.count)")
        for (index, document) in data.documents.enumerated() {
            guard !document.encryptedFileName.isEmpty,
                  let bytes = try? await store.readOriginal(named: document.encryptedFileName),
                  let result = try? OCRService.extract(from: bytes)
            else {
                print("[\(index)] could not be re-read")
                continue
            }

            let hasName = !(result.fields["full_name"] ?? "").isEmpty
            // Ground truth: what the operator confirmed against the image.
            // Compared, never printed — a recovered name that does not match
            // one a person checked is worse than no name at all.
            let confirmed = document[.fullName].uppercased().trimmingCharacters(in: .whitespaces)
            let recovered = (result.fields["full_name"] ?? "").uppercased().trimmingCharacters(in: .whitespaces)
            if !confirmed.isEmpty, !recovered.isEmpty {
                let verdict = confirmed == recovered
                    ? "MATCHES the confirmed name"
                    : (Set(confirmed.split(separator: " ")) == Set(recovered.split(separator: " "))
                        ? "same words, different order"
                        : "DIFFERS from the confirmed name")
                print("     name check: \(verdict)")
            } else if !recovered.isEmpty {
                print("     name check: nothing confirmed to compare against")
            }
            let lines = result.rawText
                .components(separatedBy: .newlines)
                .map { $0.uppercased().filter { alphabet.contains($0) } }
                .filter { $0.count >= 28 }

            print("[\(index)] name: \(hasName ? "read" : "MISSING")  fields: \(result.fields.keys.sorted().joined(separator: ","))")
            print("     lines >=28 chars after filtering: \(lines.count)")
            for (position, line) in lines.enumerated() {
                let digits = line.filter(\.isNumber).count
                let hasSeparator = line.contains("<<")
                let looksLikeLine2 = line.count >= 28 && digits > 10
                // Masked: every letter becomes A and every digit 9, so the
                // shape of the line is legible and the name in it is not.
                let masked = String(line.map { character -> Character in
                    if character.isNumber { return "9" }
                    if character == "<" { return "<" }
                    return "A"
                })
                print("     line \(position): length \(line.count), digits \(digits), has '<<' \(hasSeparator)"
                      + (looksLikeLine2 ? "   <- looks like line 2" : "")
                      + (!looksLikeLine2 && digits > 0 ? "   <- digits present" : ""))
                if !looksLikeLine2 { print("        shape: \(masked)") }
                if !looksLikeLine2, let parsed = MRZ.names(line) {
                    print("        would parse as a name of \(parsed.split(separator: " ").count) part(s)")
                } else if !looksLikeLine2 {
                    print("        names() rejects this line")
                }
            }
        }
    }
}
