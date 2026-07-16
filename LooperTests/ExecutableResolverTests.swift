import XCTest

@testable import Looper

final class ExecutableResolverTests: XCTestCase {
    func testPinnedPathVerifiesDirectlyAndHardMisses() {
        // A user-pinned path must never be silently substituted.
        XCTAssertEqual(
            ExecutableResolver.resolveStatically(
                "/opt/tools/claude",
                path: "/usr/bin",
                isExecutable: { $0 == "/opt/tools/claude" }
            ),
            "/opt/tools/claude"
        )
        XCTAssertNil(
            ExecutableResolver.resolveStatically(
                "/opt/tools/claude",
                path: "/usr/bin",
                isExecutable: { _ in false }
            )
        )
    }

    func testBareNameScansPathInOrder() {
        let resolved = ExecutableResolver.resolveStatically(
            "claude",
            path: "/first/bin:/second/bin",
            isExecutable: { $0 == "/second/bin/claude" }
        )
        XCTAssertEqual(resolved, "/second/bin/claude")

        XCTAssertNil(
            ExecutableResolver.resolveStatically(
                "claude",
                path: "/first/bin:/second/bin",
                isExecutable: { _ in false }
            )
        )
    }

    func testAugmentedPATHDeduplicatesAndKeepsBaseFirst() {
        let path = ExecutableResolver.augmentedPATH(base: "/opt/homebrew/bin:/usr/bin", home: "/Users/me")
        let entries = path.split(separator: ":").map(String.init)

        XCTAssertEqual(entries.first, "/opt/homebrew/bin")
        XCTAssertEqual(entries.count(where: { $0 == "/opt/homebrew/bin" }), 1)
        XCTAssertTrue(entries.contains("/Users/me/.local/bin"))
        XCTAssertTrue(entries.contains("/Users/me/.local/share/mise/shims"))
    }

    func testUnsafeNamesAreExcludedFromShellScript() {
        XCTAssertTrue(ExecutableResolver.isSafeCommandName("claude"))
        XCTAssertTrue(ExecutableResolver.isSafeCommandName("cursor-agent"))
        XCTAssertFalse(ExecutableResolver.isSafeCommandName("claude; rm -rf /"))
        XCTAssertFalse(ExecutableResolver.isSafeCommandName("$(evil)"))
        XCTAssertFalse(ExecutableResolver.isSafeCommandName(""))

        let script = ExecutableResolver.loginShellResolveScript(names: ["claude", "bad; name"])
        XCTAssertTrue(script.contains("unalias claude"))
        XCTAssertTrue(script.contains("unset -f claude"))
        XCTAssertTrue(script.contains("command -v claude"))
        XCTAssertFalse(script.contains("bad; name"))
    }

    func testParseLoginShellOutputRequiresAbsoluteExecutablePaths() {
        let output = """
        claude\t/Users/me/.local/bin/claude
        git\tgit: aliased to hub
        tmux\t/gone/bin/tmux
        malformed-line
        """
        let resolved = ExecutableResolver.parseLoginShellResolveOutput(
            output,
            isExecutable: { $0 == "/Users/me/.local/bin/claude" }
        )

        XCTAssertEqual(resolved, ["claude": "/Users/me/.local/bin/claude"])
    }
}
