// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "ProjectApexCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ProjectApexCore", targets: ["ProjectApexCore"])
    ],
    targets: [
        .target(name: "ProjectApexCore"),
        // Backend publisher: generates + exhaustively solves N days of
        // challenges and writes them to Firestore via REST. Runs on the
        // Mac (Phase 5, Decision 1) — the ONLY target allowed Foundation.
        .executableTarget(
            name: "apex-publish",
            dependencies: ["ProjectApexCore"]
        ),
        .testTarget(
            name: "ProjectApexCoreTests",
            dependencies: ["ProjectApexCore"]
        )
    ]
)

