// swift-tools-version: 5.10
import PackageDescription

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
        .testTarget(name: "CrewListrProMacTests", dependencies: ["CrewListrProMac", "CSQLCipher"]),
    ]
)
