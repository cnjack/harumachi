import XCTest
@testable import MioCore

final class DecisionTests: XCTestCase {
    func testRequestIncludesTimePersonaConversationAndConcreteReplyChoice() throws {
        let client = ClefClient(configuration: ClefConfiguration())
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: client.requestBody(for:
            SystemEvent(kind: "message", summary: "今晚还有一点工作"))) as? [String: Any])
        let state = try XCTUnwrap(body["state"] as? [String: Any])
        XCTAssertNotNil(state["context"], "Decisions need local time and bounded conversation context")
        XCTAssertTrue(String(describing: state["persona"]).contains("澪"))
        let questions = try XCTUnwrap(body["questions"] as? [String: Any])
        XCTAssertNotNil(questions["utterance"], "Clef must choose a concrete contextual line, not just one of five reactions")
        let utterance = try XCTUnwrap(questions["utterance"] as? [String:Any])
        let criteria = try XCTUnwrap(utterance["criteria"] as? [String:String])
        XCTAssertNil(criteria["quiet"], "Recent replies must not suppress a new direct question")
    }
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
    func testConfiguredHTTPSEndpointsAllowDomainsAndLAN() throws {
        for address in ["https://clef.scgzyun.com", "http://192.168.10.202:8098", "http://machine.local:8098", "http://localhost:4910/clef", "http://127.0.0.1:8098", "http://[::1]:8098"] {
            let endpoint = try ClefConfiguration(baseURL:address).endpoint()
            XCTAssertTrue(endpoint.path.hasSuffix("/v1/systemone"))
        }
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
        XCTAssertNotNil(result.utteranceID)
        let direct = try await client.decide(SystemEvent(kind:"message",summary:"__lowconfidence__"))
        XCTAssertEqual(direct.reaction,.notice)
        let quiet = try await client.decide(SystemEvent(kind:"app.active",summary:"",metadata:["bundle_id":"__lowconfidence__"]))
        XCTAssertEqual(quiet.reaction, .none)
        for message in ["__unknown__", "__unknown_utterance__", "__wrongmodel__", "__invalid__", "__status500__", "__html__", "__redirect__"] {
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
    func testConfiguredHostnameIsContactedThroughProductionTransport() async throws {
        guard let baseURL = ProcessInfo.processInfo.environment["MIO_TEST_SIM_URL"] else {
            throw XCTSkip("Run tools/test_simulation.sh to exercise configured hostnames")
        }
        var components = try XCTUnwrap(URLComponents(string:baseURL))
        components.host = "localhost"
        let client = ClefClient(configuration:ClefConfiguration(baseURL:try XCTUnwrap(components.string)))
        let decision = try await client.decide(SystemEvent(kind:"message",summary:"configured-hostname-regression"))
        XCTAssertEqual(decision.source,"Clef 决策")
        XCTAssertEqual(decision.reaction,.notice)
    }
}
