@preconcurrency import Foundation
@preconcurrency import Network
import Testing
@testable import ClipDock

struct MetadataHTTPTransportTests {
    @Test
    func responseWithoutMIMEIsBoundedAtHTMLBudgetBeforeEOF() async throws {
        let server = try await MetadataHTTPFixture.start()
        defer { server.stop() }
        let url = server.url
        let budget = 512 * 1024
        server.install(url, fixture: .init(chunks: [Data(repeating: 0x61, count: budget + 1)],
            waitsForCancellation: true, contentType: nil))
        var request = URLRequest(url: url)
        request.timeoutInterval = 1
        do {
            _ = try await client().data(for: request, maxBytes: budget, maxRedirects: 5)
            Issue.record("Expected byte limit without MIME or EOF")
        } catch MetadataHTTPError.byteLimit {}
    }

    @Test
    func streamingEnforcesActualBytesWithoutContentLength() async throws {
        let server = try await MetadataHTTPFixture.start()
        defer { server.stop() }
        let url = server.url
        server.install(url, fixture: .init(chunks: [Data(repeating: 1, count: 32)], waitsForCancellation: true))
        var request = URLRequest(url: url)
        request.timeoutInterval = 1
        do {
            _ = try await client().data(for: request, maxBytes: 20, maxRedirects: 5)
            Issue.record("Expected byte limit")
        } catch MetadataHTTPError.byteLimit {}
    }

    @Test
    func declaredOversizeIsRejectedBeforeEndOfBody() async throws {
        let server = try await MetadataHTTPFixture.start()
        defer { server.stop() }
        let url = server.url
        server.install(url, fixture: .init(headers: ["Content-Length": "100"], chunks: [Data([1])], waitsForCancellation: true))
        var request = URLRequest(url: url)
        request.timeoutInterval = 1
        do {
            _ = try await client().data(for: request, maxBytes: 20, maxRedirects: 5)
            Issue.record("Expected byte limit from response headers")
        } catch MetadataHTTPError.byteLimit {}
    }

    @Test
    func httpFailureReturnsHeadersBeforeEndOfBody() async throws {
        let server = try await MetadataHTTPFixture.start()
        defer { server.stop() }
        let url = server.url
        server.install(url, fixture: .init(status: 404, chunks: [Data([1])], waitsForCancellation: true))
        var request = URLRequest(url: url)
        request.timeoutInterval = 1
        let (data, response) = try await client().data(for: request, maxBytes: 20, maxRedirects: 5)
        #expect(data.isEmpty)
        #expect((response as? HTTPURLResponse)?.statusCode == 404)
    }

    @Test
    func cancellationTerminatesBodyWithoutEOF() async throws {
        let server = try await MetadataHTTPFixture.start()
        defer { server.stop() }
        let url = server.url
        server.install(url, fixture: .init(chunks: [Data([1])], waitsForCancellation: true))
        let client = client()
        let task = Task {
            var request = URLRequest(url: url)
            request.timeoutInterval = 2
            return try await client.data(for: request, maxBytes: 20, maxRedirects: 5)
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while server.chunksSent(url) == 0, ContinuousClock.now < deadline {
            await Task.yield()
        }
        #expect(server.chunksSent(url) == 1)
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {}
    }

    @Test
    func alreadyCancelledRequestDoesNotStartTransport() async throws {
        let server = try await MetadataHTTPFixture.start()
        defer { server.stop() }
        let url = server.url
        server.install(url, fixture: .init(waitsForCancellation: true))
        let client = client()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await client.data(for: URLRequest(url: url), maxBytes: 20, maxRedirects: 5)
        }
        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {}
        #expect(server.requests(url) == 0)
    }

    @Test
    func redirectPolicyBlocksSensitiveDestinationBeforeRequest() async throws {
        let server = try await MetadataHTTPFixture.start()
        defer { server.stop() }
        let url = server.url
        let next = url.appendingPathComponent("next").appending(queryItems: [URLQueryItem(name: "access_token", value: "fixture")])
        server.install(url, fixture: .init(status: 302, headers: ["Location": next.absoluteString], chunks: [Data([1])], waitsForCancellation: true))
        server.install(next, fixture: .init())
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 1
            _ = try await client().data(for: request, maxBytes: 32, maxRedirects: 5)
            Issue.record("Expected privacy rejection")
        } catch MetadataHTTPError.disallowedURL {}
        #expect(server.requests(next) == 0)
    }

    @Test
    func redirectBudgetIsBoundedAndRelativeLocationResolves() async throws {
        let server = try await MetadataHTTPFixture.start()
        defer { server.stop() }
        let url = server.url
        let next = url.appendingPathComponent("next")
        server.install(url, fixture: .init(status: 302, headers: ["Location": "/next"]))
        server.install(next, fixture: .init(chunks: [Data("ok".utf8)]))
        let (data, response) = try await client().data(for: URLRequest(url: url), maxBytes: 32, maxRedirects: 1)
        #expect(data == Data("ok".utf8))
        #expect(response.url == next)
        do {
            _ = try await client().data(for: URLRequest(url: url), maxBytes: 32, maxRedirects: 0)
            Issue.record("Expected redirect limit")
        } catch MetadataHTTPError.redirectLimit {}
    }

    @Test
    func totalDeadlineCancelsTrickledBody() async throws {
        let server = try await MetadataHTTPFixture.start()
        defer { server.stop() }
        let url = server.url
        server.install(url, fixture: .init(chunks: Array(repeating: Data([1]), count: 50), delayMs: 15))
        var request = URLRequest(url: url)
        request.timeoutInterval = 0.045
        do {
            _ = try await client().data(for: request, maxBytes: 100, maxRedirects: 5)
            Issue.record("Expected total deadline")
        } catch LinkMetadataFetchError.timedOut {}
        catch let error as URLError { #expect(error.code == .timedOut || error.code == .cancelled) }
        #expect(server.chunksSent(url) < 50)
    }

    private func client() -> URLSessionLinkMetadataHTTPClient {
        URLSessionLinkMetadataHTTPClient(configuration: .ephemeral)
    }
}

private final class MetadataHTTPFixture: @unchecked Sendable {
    struct Fixture: Sendable {
        var status = 200
        var headers: [String: String] = [:]
        var chunks: [Data] = []
        var delayMs = 0
        var waitsForCancellation = false
        var contentType: String? = "application/octet-stream"
    }
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "clipdock.metadata.http-fixture")
    private let listener: NWListener
    private var fixtures: [String: Fixture] = [:]
    private var requestCounts: [String: Int] = [:]
    private var chunkCounts: [String: Int] = [:]
    private var connections: [UUID: NWConnection] = [:]
    private var ready: CheckedContinuation<Void, Error>?
    private var stopped = false

    private init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
    }

    static func start() async throws -> MetadataHTTPFixture {
        let server = try MetadataHTTPFixture()
        try await withCheckedThrowingContinuation { continuation in
            server.lock.withLock { server.ready = continuation }
            server.listener.stateUpdateHandler = { [weak server] state in
                guard let server else { return }
                switch state {
                case .ready: server.finishStarting(nil)
                case .failed(let error): server.finishStarting(error)
                case .cancelled: server.finishStarting(CancellationError())
                default: break
                }
            }
            server.listener.newConnectionHandler = { [weak server] connection in server?.accept(connection) }
            server.listener.start(queue: server.queue)
        }
        return server
    }

    var url: URL { URL(string: "http://127.0.0.1:\(listener.port!.rawValue)/")! }
    private func key(_ url: URL) -> String { url.path + (url.query.map { "?\($0)" } ?? "") }
    func install(_ url: URL, fixture: Fixture) { lock.withLock { fixtures[key(url)] = fixture } }
    func requests(_ url: URL) -> Int { lock.withLock { requestCounts[key(url), default: 0] } }
    func chunksSent(_ url: URL) -> Int { lock.withLock { chunkCounts[key(url), default: 0] } }

    private func finishStarting(_ error: Error?) {
        let continuation = lock.withLock { let current = ready; ready = nil; return current }
        if let error { continuation?.resume(throwing: error) }
        else { continuation?.resume() }
    }

    func stop() {
        let current = lock.withLock {
            stopped = true
            let current = Array(connections.values)
            connections.removeAll()
            return current
        }
        listener.cancel()
        for connection in current { connection.cancel() }
    }

    private func accept(_ connection: NWConnection) {
        let id = UUID()
        let shouldStart = lock.withLock {
            guard !stopped else { return false }
            connections[id] = connection
            return true
        }
        guard shouldStart else { connection.cancel(); return }
        connection.stateUpdateHandler = { [weak self] state in
            if case .cancelled = state { self?.remove(id) }
            if case .failed = state { self?.remove(id) }
        }
        connection.start(queue: queue)
        readRequest(connection, accumulated: Data())
    }

    private func remove(_ id: UUID) { _ = lock.withLock { connections.removeValue(forKey: id) } }

    private func readRequest(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, complete, error in
            guard let self else { connection.cancel(); return }
            var accumulated = accumulated
            if let data { accumulated.append(data) }
            guard accumulated.count <= 32 * 1024 else { connection.cancel(); return }
            if let end = accumulated.range(of: Data("\r\n\r\n".utf8)) {
                let header = String(decoding: accumulated[..<end.lowerBound], as: UTF8.self)
                guard let first = header.components(separatedBy: "\r\n").first,
                      first.split(separator: " ").count >= 2 else { connection.cancel(); return }
                let path = String(first.split(separator: " ")[1])
                let fixture = lock.withLock { requestCounts[path, default: 0] += 1; return fixtures[path] }
                guard let fixture else { connection.cancel(); return }
                observeClose(connection)
                sendResponse(connection, path: path, fixture: fixture)
            } else if complete || error != nil { connection.cancel() }
            else { readRequest(connection, accumulated: accumulated) }
        }
    }

    private func observeClose(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] _, _, complete, error in
            if complete || error != nil { connection.cancel() }
            else { self?.observeClose(connection) }
        }
    }

    private func sendResponse(_ connection: NWConnection, path: String, fixture: Fixture) {
        let chunked = fixture.headers["Content-Length"] == nil
        var header = "HTTP/1.1 \(fixture.status) Fixture\r\nConnection: close\r\n"
        if let contentType = fixture.contentType {
            header += "Content-Type: \(contentType)\r\nX-Content-Type-Options: nosniff\r\n"
        }
        if chunked { header += "Transfer-Encoding: chunked\r\n" }
        for (key, value) in fixture.headers { header += "\(key): \(value)\r\n" }
        header += "\r\n"
        connection.send(content: Data(header.utf8), completion: .contentProcessed { [weak self] error in
            guard error == nil else { connection.cancel(); return }
            self?.sendChunk(connection, path: path, fixture: fixture, index: 0, chunked: chunked)
        })
    }

    private func sendChunk(_ connection: NWConnection, path: String, fixture: Fixture, index: Int, chunked: Bool) {
        guard !lock.withLock({ stopped }) else { return }
        guard index < fixture.chunks.count else {
            // Foundation can defer response delivery until the first body byte.
            // Withholding both the zero chunk and FIN proves the client does
            // not depend on EOF to reject a header/body or honor cancellation.
            guard !fixture.waitsForCancellation else { return }
            let ending = chunked ? Data("0\r\n\r\n".utf8) : nil
            connection.send(content: ending, contentContext: .finalMessage, isComplete: true,
                completion: .contentProcessed { _ in connection.cancel() })
            return
        }
        queue.asyncAfter(deadline: .now() + .milliseconds(fixture.delayMs)) { [weak self] in
            guard let self, !lock.withLock({ stopped }) else { return }
            let chunk = fixture.chunks[index]
            var wire = Data()
            if chunked { wire.append(Data("\(String(chunk.count, radix: 16))\r\n".utf8)) }
            wire.append(chunk)
            if chunked { wire.append(Data("\r\n".utf8)) }
            connection.send(content: wire, completion: .contentProcessed { [weak self] error in
                guard let self, error == nil else { return }
                lock.withLock { chunkCounts[path, default: 0] += 1 }
                sendChunk(connection, path: path, fixture: fixture, index: index + 1, chunked: chunked)
            })
        }
    }
}
