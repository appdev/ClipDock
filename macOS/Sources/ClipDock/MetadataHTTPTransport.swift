@preconcurrency import Foundation
import ClipboardPanelApp

enum MetadataHTTPError: Error { case byteLimit, redirectLimit, invalidRedirect, disallowedURL }

final class URLSessionLinkMetadataHTTPClient: LinkMetadataHTTPClient, @unchecked Sendable {
    private let configuration: URLSessionConfiguration

    init(configuration: URLSessionConfiguration = .ephemeral) {
        self.configuration = configuration
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let limits = try ClipboardPanelApp.RustMetadataPolicy.limits()
        return try await data(for: request, maxBytes: limits.maxImageBytes, maxRedirects: limits.maxRedirects)
    }

    func data(for request: URLRequest, maxBytes: Int, maxRedirects: Int) async throws -> (Data, URLResponse) {
        // One deadline covers redirects and streaming, even when bytes trickle in.
        try await withThrowingTaskGroup(of: (Data, URLResponse).self) { group in
            group.addTask { try await self.followRedirects(request, maxBytes: maxBytes, maxRedirects: maxRedirects) }
            group.addTask {
                try await Task.sleep(for: .seconds(max(0.001, request.timeoutInterval)))
                throw LinkMetadataFetchError.timedOut
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    private func followRedirects(_ original: URLRequest, maxBytes: Int, maxRedirects: Int) async throws -> (Data, URLResponse) {
        var request = original
        for hop in 0...max(0, maxRedirects) {
            try Task.checkCancellation()
            guard let url = request.url,
                  LinkMetadataURLPolicy.isSupportedRemoteURL(url),
                  !LinkMetadataURLPolicy.isPrivacySensitive(url) else { throw MetadataHTTPError.disallowedURL }
            let response = try await fetchHop(request, maxBytes: maxBytes)
            if let http = response.1 as? HTTPURLResponse, [301, 302, 303, 307, 308].contains(http.statusCode) {
                guard hop < maxRedirects else { throw MetadataHTTPError.redirectLimit }
                guard let location = http.value(forHTTPHeaderField: "Location"),
                      let next = URL(string: location, relativeTo: url)?.absoluteURL else { throw MetadataHTTPError.invalidRedirect }
                request.url = next
                continue
            }
            return response
        }
        throw MetadataHTTPError.redirectLimit
    }

    private func fetchHop(_ request: URLRequest, maxBytes: Int) async throws -> (Data, URLResponse) {
        guard maxBytes >= 0 else { throw MetadataHTTPError.byteLimit }
        let receiver = MetadataResponseReceiver(maxBytes: maxBytes)
        let session = URLSession(configuration: configuration, delegate: receiver, delegateQueue: nil)
        let task = session.dataTask(with: request)
        defer { session.invalidateAndCancel() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                receiver.start(task, continuation: continuation)
            }
        } onCancel: { receiver.finish(.failure(CancellationError())) }
    }
}

/// Bound the body at the delegate callback, before an async sequence can buffer it.
/// Cancellation may precede continuation installation; the first terminal result wins.
private final class MetadataResponseReceiver: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private typealias Response = (Data, URLResponse)
    private let maxBytes: Int
    private let lock = NSLock()
    private var response: URLResponse?
    private var body = Data()
    private var terminal: Result<Response, Error>?
    private var continuation: CheckedContinuation<Response, Error>?
    private var task: URLSessionDataTask?

    init(maxBytes: Int) { self.maxBytes = maxBytes }

    func start(_ task: URLSessionDataTask, continuation: CheckedContinuation<(Data, URLResponse), Error>) {
        let previous = lock.withLock { () -> Result<Response, Error>? in
            if let terminal { return terminal }
            self.task = task
            self.continuation = continuation
            return nil
        }
        if let previous {
            task.cancel()
            continuation.resume(with: previous)
        } else {
            // A concurrent cancellation already cancels this task; resume cannot revive it.
            task.resume()
        }
    }

    func finish(_ result: Result<(Data, URLResponse), Error>) {
        let pending = lock.withLock { () -> (CheckedContinuation<Response, Error>?, URLSessionDataTask?) in
            guard terminal == nil else { return (nil, nil) }
            terminal = result
            let pending = (continuation, task)
            continuation = nil
            task = nil
            body = Data()
            return pending
        }
        pending.1?.cancel()
        pending.0?.resume(with: result)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            finish(.success((Data(), response)))
            completionHandler(.cancel)
            return
        }
        guard response.expectedContentLength < 0 || response.expectedContentLength <= maxBytes else {
            finish(.failure(MetadataHTTPError.byteLimit))
            completionHandler(.cancel)
            return
        }
        let active = lock.withLock {
            guard terminal == nil else { return false }
            self.response = response
            return true
        }
        completionHandler(active ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let exceeded = lock.withLock {
            guard terminal == nil else { return false }
            guard data.count <= maxBytes - body.count else { return true }
            body.append(data)
            return false
        }
        if exceeded { finish(.failure(MetadataHTTPError.byteLimit)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)); return }
        let result = lock.withLock { () -> Result<Response, Error> in
            guard let response else { return .failure(URLError(.badServerResponse)) }
            return .success((body, response))
        }
        finish(result)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        // Foundation already exposes the redirect here. Declining automatic
        // following alone can still wait for this response's unfinished body.
        finish(.success((Data(), response)))
        completionHandler(nil)
    }
}
