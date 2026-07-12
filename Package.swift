// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScarlettMixControl",
    platforms: [.macOS(.v14)],
    products: [
        // Library that other Swift targets can link against.
        .library(name: "ScarlettCore", targets: ["ScarlettCore"]),
        // Executables — product names stay kebab-case (Unix-style binary
        // names) while target/folder names are PascalCase (Swift convention).
        .executable(name: "scarlett-cli", targets: ["ScarlettCLI"]),
        .executable(name: "scarlett-app", targets: ["ScarlettApp"]),
    ],
    targets: [
        .target(name: "ScarlettCore", path: "Sources/ScarlettCore"),
        .executableTarget(
            name: "ScarlettCLI",
            dependencies: ["ScarlettCore"],
            path: "Sources/ScarlettCLI"
        ),
        .executableTarget(
            name: "ScarlettApp",
            dependencies: ["ScarlettCore"],
            path: "Sources/ScarlettApp"
            // AppIcon.png lives under Sources/ScarlettApp/Resources/ for
            // scripts/make-app.sh only — do NOT declare .process("Resources")
            // here.  That embeds Bundle.module in the binary, which fatalErrors
            // when the CI-built .app ships without the SPM resource bundle.
        ),
        .testTarget(
            name: "ScarlettCoreTests",
            dependencies: ["ScarlettCore"],
            path: "Tests/ScarlettCoreTests"
        ),
    ]
)
