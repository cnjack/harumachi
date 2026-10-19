import XCTest
@testable import MioCore

final class DecisionTests: XCTestCase {
    func response(mood: String = "happy", reaction: String = "notice", confidence: Double = 0.9, model: String = "clef-omni") -> Data {
        try! JSONSerialization.data(withJSONObject: ["model": model, "answers": [
            "mood": ["choice": mood, "confidence": confidence],
            "reaction": ["choice": reaction, "confidence": confidence]]])
    }
    func testRejectsUntrustedActionsAndWrongModel() {
        XCTAssertThrowsError(try ClefClient.decode(response(reaction: "run_shell")))
        XCTAssertThrowsError(try ClefClient.decode(response(model: "something-else")))
        XCTAssertThrowsError(try ClefClient.decode(Data("{}".utf8)))
    }
    func testLowConfidenceStaysQuiet() throws {
        let decision = try ClefClient.decode(response(confidence: 0.54))
        XCTAssertEqual(decision.reaction, .none)
        XCTAssertEqual(decision.mood, .neutral)
        XCTAssertThrowsError(try ClefClient.decode(response(confidence: 1.1)))
        XCTAssertThrowsError(try ClefClient.decode(response(confidence: -0.1)))
    }
    func testRejectsCredentialURLsAndPreservesPathPrefix() throws {
        for value in ["file:///tmp/model", "https://user:secret@host", "http://host/?key=secret", "http://host/#secret", "relative"] {
            XCTAssertThrowsError(try ClefConfiguration(baseURL: value).endpoint())
        }
        XCTAssertEqual(try ClefConfiguration(baseURL: "http://localhost:4910/clef/").endpoint().path, "/clef/v1/systemone")
        XCTAssertThrowsError(try ClefConfiguration(timeout: .infinity).endpoint())
    }
    func testPermissionFreeModeNeverContactsLANOrDNSNames() throws {
        for host in ["192.168.10.202", "10.0.0.1", "machine.local", "example.com", "localhost"] {
            XCTAssertThrowsError(try ClefConfiguration(baseURL: "http://\(host):8098").permissionFreeEndpoint())
        }
        XCTAssertEqual(try ClefConfiguration(baseURL: "http://127.0.0.1:8098").permissionFreeEndpoint().host, "127.0.0.1")
        XCTAssertNoThrow(try ClefConfiguration(baseURL: "http://[::1]:8098").permissionFreeEndpoint())
    }
    func testEventDedupeExpiryAndDistinctMessages() {
        let now = Date()
        var gate = EventGate()
        let event = SystemEvent(kind: "network", summary: "online", metadata: ["status": "online"], date: now)
        XCTAssertTrue(gate.accepts(event, now: now))
        XCTAssertFalse(gate.accepts(event, now: now.addingTimeInterval(1)))
        XCTAssertTrue(gate.accepts(event, now: now.addingTimeInterval(16)))
        XCTAssertFalse(gate.accepts(event, now: now.addingTimeInterval(61)))
        XCTAssertFalse(gate.accepts(SystemEvent(kind: "wake", summary: "future", date: now.addingTimeInterval(20)), now: now))
        XCTAssertTrue(gate.accepts(SystemEvent(kind: "message", summary: "a", date: now), now: now))
        XCTAssertTrue(gate.accepts(SystemEvent(kind: "message", summary: "b", date: now), now: now))
    }
    func testPayloadExcludesAppNamesAndBoundsMessage() throws {
        let client = ClefClient(configuration: ClefConfiguration())
        let event = SystemEvent(kind: "app.active", summary: "Secret Document - My App", metadata: ["bundle_id": "com.example.editor"])
        let body = String(data: try client.requestBody(for: event), encoding: .utf8)!
        XCTAssertFalse(body.contains("Secret Document"))
        XCTAssertTrue(body.contains("com.example.editor"))
        XCTAssertEqual(SystemEvent(kind: "message", summary: String(repeating: "好", count: 5000)).summary.count, 1000)
    }
    func testBlinkAndGazeConstraints() {
        XCTAssertEqual(RigPose(time: 4.25).blink, 1, accuracy: 0.001)
        XCTAssertEqual(RigPose(time: 1).blink, 0)
        XCTAssertEqual(RigPose(time: 1, mood: .sleepy).blink, 1)
        let pose = RigPose(time: 0, lookX: 100, lookY: -100)
        XCTAssertEqual(pose.lookX, 1); XCTAssertEqual(pose.lookY, -1)
    }
    func testRealHTTPTransportAgainstPostmanSimulation() async throws {
        guard let baseURL = ProcessInfo.processInfo.environment["MIO_TEST_SIM_URL"] else {
            throw XCTSkip("Run tools/test_simulation.sh to exercise real HTTP transport")
        }
        let client = ClefClient(configuration: ClefConfiguration(baseURL: baseURL))
        let result = try await client.decide(SystemEvent(kind: "message", summary: "hello"))
        XCTAssertEqual(result.source, "Clef 决策"); XCTAssertEqual(result.mood, .happy)
        let quiet = try await client.decide(SystemEvent(kind: "message", summary: "__lowconfidence__"))
        XCTAssertEqual(quiet.reaction, .none)
        for message in ["__unknown__", "__wrongmodel__", "__invalid__", "__status500__", "__html__", "__redirect__"] {
            do {
                _ = try await client.decide(SystemEvent(kind: "message", summary: message))
                XCTFail("Invalid upstream response was accepted: \(message)")
            } catch { /* Expected rejection through the production URLSession path. */ }
        }
        let fast = ClefClient(configuration: ClefConfiguration(baseURL: baseURL, timeout: 0.3))
        let start = Date()
        do {
            _ = try await fast.decide(SystemEvent(kind: "message", summary: "__timeout__"))
            XCTFail("The transport must time out")
        } catch { XCTAssertLessThan(Date().timeIntervalSince(start), 2) }
    }
}
