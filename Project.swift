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
            "ASSETCATALOG_COMPILER_GENERATE_ASSET_SYMBOLS": "YES",
            "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
            "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
            "ENABLE_MODULE_VERIFIER": "YES",
            "MODULE_VERIFIER_SUPPORTED_LANGUAGES": "objective-c objective-c++",
            "SWIFT_EMIT_LOC_STRINGS": "YES",
            "STRING_CATALOG_GENERATE_SYMBOLS": "YES",
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
                "SUFeedURL": "https://github.com/KQAR/looper/releases/latest/download/appcast.xml",
                "SUPublicEDKey": "HOQ0tDtw/nV9GXRIMUtzImgNssckFEj5fFLe2Lp0LDY=",
                "SUEnableAutomaticChecks": true,
            ]),
            sources: ["Looper/Sources/**"],
            resources: ["Looper/Resources/**"],
            dependencies: [
                .external(name: "ComposableArchitecture"),
                .external(name: "GRDB"),
                .external(name: "GhosttyTerminal"),
                .external(name: "Sparkle"),
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
