// swift-tools-version: 5.10
import PackageDescription
import Foundation

// Tools that read or rewrite the operator's live encrypted store — seeding it
// for screenshots, rebuilding it, applying a review pass, auditing its files.
// They are XCTest cases only to reach the module's internals, and none of them
// checks anything, so a plain `swift test` does not compile them at all:
//
//     CREWLISTR_MAINTENANCE=1 swift test --filter <class>
//
// Each still refuses to run without its own variable as well.
let includeMaintenance = ProcessInfo.processInfo.environment["CREWLISTR_MAINTENANCE"] == "1"

let package = Package(
    name: "CrewListrProMac",
    platforms: [.macOS("15.0")],
    products: [.executable(name: "CrewListrProMac", targets: ["CrewListrProMac"])],
    targets: [
        .systemLibrary(name: "CSQLCipher", pkgConfig: "sqlcipher", providers: [.brew(["sqlcipher"])]),
        .executableTarget(
            name: "CrewListrProMac",
            dependencies: ["CSQLCipher"],
            // The brand marks shown in the window corner and the info screen.
            // `scripts/release.sh` copies the generated bundle into the app so
            // `Bundle.module` resolves from a packaged build as well as `swift run`.
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "CrewListrProMacTests",
            dependencies: ["CrewListrProMac", "CSQLCipher"],
            exclude: includeMaintenance ? [] : ["Maintenance"]
        ),
    ]
)
