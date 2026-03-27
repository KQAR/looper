import ProjectDescription

let project = Project(
    name: "Looper",
    options: .options(
        automaticSchemesOptions: .disabled,
        defaultKnownRegions: ["en", "zh-Hans"],
        developmentRegion: "en"
    ),
    settings: .settings(
        base: [
            "SWIFT_VERSION": "6.0",
            "MACOSX_DEPLOYMENT_TARGET": "26.0",
            "SWIFT_STRICT_CONCURRENCY": "complete",
        ],
        configurations: [
            .debug(name: "Debug"),
            .release(name: "Release"),
        ]
    ),
    targets: [
        .target(
            name: "Looper",
            destinations: .macOS,
            product: .app,
            bundleId: "com.jarvis.looper",
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Looper",
                "CFBundleShortVersionString": "0.0.1",
                "CFBundleVersion": "1",
                "LSMinimumSystemVersion": "26.0",
            ]),
            sources: ["Looper/Sources/**"],
            resources: ["Looper/Resources/**"],
            dependencies: [
                .external(name: "ComposableArchitecture"),
                .external(name: "GRDB"),
                .external(name: "GhosttyTerminal"),
            ]
        ),
        .target(
            name: "LooperTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.jarvis.looper.tests",
            infoPlist: .default,
            sources: ["LooperTests/**"],
            dependencies: [
                .target(name: "Looper"),
            ]
        ),
    ],
    schemes: [
        .scheme(
            name: "Looper",
            buildAction: .buildAction(targets: ["Looper"]),
            runAction: .runAction(executable: "Looper")
        ),
        .scheme(
            name: "Looper-Testing",
            buildAction: .buildAction(targets: ["Looper", "LooperTests"]),
            testAction: .targets(
                ["LooperTests"],
                expandVariableFromTarget: "Looper"
            ),
            runAction: .runAction(executable: "Looper")
        ),
    ]
)
