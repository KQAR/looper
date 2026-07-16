import XCTest

@testable import Looper

final class JSONLineParserTests: XCTestCase {
    func testUnknownSystemSubtypeIsSkippedNotFatal() throws {
        // Regression: claude CLI 2.1.211 emits system/thinking_tokens, which
        // this vendored SDK predates. One unknown line must not kill the
        // whole message stream (it used to fail the run instantly).
        let line = #"{"type":"system","subtype":"thinking_tokens","tokens":128,"session_id":"s"}"#
        XCTAssertNil(try JSONLineParser.parse(line))
    }

    func testUnknownTopLevelTypeIsSkippedNotFatal() throws {
        let line = #"{"type":"totally_new_event","payload":{"x":1}}"#
        XCTAssertNil(try JSONLineParser.parse(line))
    }

    func testKnownMessagesStillParse() throws {
        let line = #"{"type":"system","subtype":"status","status":"thinking","session_id":"s","uuid":"u"}"#
        let parsed = try JSONLineParser.parse(line)
        guard case .message(.system) = parsed else {
            return XCTFail("expected a system message, got \(String(describing: parsed))")
        }
    }

    func testMalformedJSONStillThrows() {
        // Garbage that fails the type peek is a real protocol error and
        // should still surface.
        XCTAssertThrowsError(try JSONLineParser.parse("not json at all"))
    }
}
