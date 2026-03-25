// swift-tools-version: 6.0
@preconcurrency import PackageDescription

let package = Package(
    name: "Looper",
    dependencies: [
        .package(
            url: "https://github.com/pointfreeco/swift-composable-architecture.git",
            from: "1.25.2"
        ),
        .package(
            url: "https://github.com/groue/GRDB.swift.git",
            from: "7.8.0"
        ),
        .package(
            url: "https://github.com/Lakr233/libghostty-spm.git",
            from: "1.0.1774295826"
        ),
    ]
)
