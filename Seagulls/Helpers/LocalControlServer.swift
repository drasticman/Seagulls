//
//  LocalControlServer.swift
//  Seagulls
//
//  Created by Andy Bader on 2/18/26.
//

import Foundation
import Network

/// Minimal localhost-only HTTP server.
/// Endpoints:
///   GET  /status
///   POST /workflow/start
///   POST /drive/trust
///   POST /drive/trustByName   (JSON: {"name":"My Drive"})
///
/// Notes:
/// - Binds to 127.0.0.1 only (not exposed on LAN).
/// - Adds permissive CORS headers (useful for plugin dev).
final class LocalControlServer {
    static let shared = LocalControlServer()

    private let queue = DispatchQueue(label: "seagulls.localcontrol.server")
    private var listener: NWListener?
    private(set) var port: UInt16 = 7070

    private init() {}

    func start(port: UInt16 = 7070) {
        queue.async { [weak self] in
            guard let self else { return }
            if self.listener != nil { return } // idempotent

            self.port = port

            do {
                let params = NWParameters.tcp
                params.allowLocalEndpointReuse = true

                let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
                self.listener = listener

                listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        print("🟢 LocalControlServer ready on http://127.0.0.1:\(port)")
                    case .failed(let error):
                        print("🔴 LocalControlServer failed: \(error)")
                        self.stop()
                    default:
                        break
                    }
                }

                listener.newConnectionHandler = { [weak self] conn in
                    self?.handle(conn)
                }

                listener.start(queue: self.queue)
            } catch {
                print("🔴 LocalControlServer could not start: \(error)")
                self.listener = nil
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.listener?.cancel()
            self.listener = nil
            print("🟡 LocalControlServer stopped")
        }
    }

    // MARK: - Connection handling

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        receiveRequest(on: conn, buffer: Data())
    }

    private func receiveRequest(on conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let error {
                print("⚠️ LocalControlServer receive error: \(error)")
                conn.cancel()
                return
            }

            var buf = buffer
            if let data { buf.append(data) }

            // Try to parse when we have headers (and body, if Content-Length)
            if let response = self.tryParseAndHandle(buf) {
                self.sendResponseAndClose(response, on: conn)
                return
            }

            if isComplete {
                // No parseable request
                let resp = self.httpResponse(
                    status: 400,
                    contentType: "application/json",
                    body: #"{"ok":false,"error":"Bad Request"}"#.data(using: .utf8) ?? Data()
                )
                self.sendResponseAndClose(resp, on: conn)
                return
            }

            // Continue receiving
            self.receiveRequest(on: conn, buffer: buf)
        }
    }

    // MARK: - Request parsing + routing

    private struct Request {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    private func tryParseAndHandle(_ data: Data) -> Data? {
        // Look for header terminator: \r\n\r\n
        guard let headerRange = data.range(of: Data([13, 10, 13, 10])) else {
            return nil
        }

        let headerData = data.subdata(in: 0..<headerRange.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return httpResponse(
                status: 400,
                contentType: "application/json",
                body: #"{"ok":false,"error":"Invalid header encoding"}"#.data(using: .utf8)!
            )
        }

        let lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else {
            return httpResponse(
                status: 400,
                contentType: "application/json",
                body: #"{"ok":false,"error":"Missing request line"}"#.data(using: .utf8)!
            )
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            return httpResponse(
                status: 400,
                contentType: "application/json",
                body: #"{"ok":false,"error":"Malformed request line"}"#.data(using: .utf8)!
            )
        }

        let method = String(parts[0]).uppercased()
        let path = String(parts[1])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.isEmpty { continue }
            if let idx = line.firstIndex(of: ":") {
                let key = line[..<idx].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: idx)...].trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        // Determine body length, if any
        let contentLength = Int(headers["content-length"] ?? "") ?? 0
        let bodyStart = headerRange.upperBound
        let availableBodyBytes = data.count - bodyStart

        // Wait until we have the full body if Content-Length is set
        if contentLength > availableBodyBytes {
            return nil
        }

        let body: Data
        if contentLength > 0 {
            body = data.subdata(in: bodyStart..<(bodyStart + contentLength))
        } else {
            body = Data()
        }

        let req = Request(method: method, path: path, headers: headers, body: body)
        return route(req)
    }

    private func route(_ req: Request) -> Data {
        // Basic CORS preflight
        if req.method == "OPTIONS" {
            return httpResponse(status: 204, contentType: "text/plain", body: Data())
        }

        switch (req.method, req.path) {
        case ("GET", "/status"):
            return handleStatus()

        case ("POST", "/workflow/start"):
            return handlePost(name: .sdStartWorkflow)

        case ("POST", "/drive/trust"):
            return handlePost(name: .sdTrustFirstUntrusted)

        case ("POST", "/drive/trustByName"):
            return handleTrustByName(body: req.body)
            
        case ("POST", "/drive/trustByUUID"):
            return handleTrustByUUID(body: req.body)
            
        case ("POST", "/prompt/answer"):
            return handlePromptAnswer(body: req.body)

        case ("POST", "/prompt/cancel"):
            return handlePromptCancel(body: req.body)

        default:
            return httpResponse(
                status: 404,
                contentType: "application/json",
                body: #"{"ok":false,"error":"Not Found"}"#.data(using: .utf8) ?? Data()
            )
        }
    }

    // MARK: - Handlers

    private func handlePromptAnswer(body: Data) -> Data {
        var kind: String?
        var token: String?
        var value: String?

        if let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            kind = obj["kind"] as? String
            token = obj["token"] as? String
            value = obj["value"] as? String
        }

        guard let k = kind, let t = token, let v = value else {
            return httpResponse(
                status: 400,
                contentType: "application/json",
                body: #"{"ok":false,"error":"Missing kind/token/value"}"#.data(using: .utf8) ?? Data()
            )
        }

        let accepted = PromptBroker.shared.submitRemoteAnswer(promptToken: t, promptID: k, value: v)

        if !accepted {
            return httpResponse(
                status: 409,
                contentType: "application/json",
                body: #"{"ok":false,"error":"not_accepted"}"#.data(using: .utf8) ?? Data()
            )
        }

        return httpResponse(
            status: 200,
            contentType: "application/json",
            body: #"{"ok":true}"#.data(using: .utf8) ?? Data()
        )
    }
    
    private func handlePromptCancel(body: Data) -> Data {
        var kind: String?
        var token: String?

        if let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            kind = obj["kind"] as? String
            token = obj["token"] as? String
        }

        guard let k = kind, let t = token else {
            return httpResponse(
                status: 400,
                contentType: "application/json",
                body: #"{"ok":false,"error":"Missing kind/token"}"#.data(using: .utf8) ?? Data()
            )
        }

        let accepted = PromptBroker.shared.submitRemoteCancel(promptToken: t, promptID: k)

        if !accepted {
            return httpResponse(
                status: 409,
                contentType: "application/json",
                body: #"{"ok":false,"error":"not_accepted"}"#.data(using: .utf8) ?? Data()
            )
        }

        return httpResponse(
            status: 200,
            contentType: "application/json",
            body: #"{"ok":true}"#.data(using: .utf8) ?? Data()
        )
    }
    
    private func handleStatus() -> Data {
        let data = StreamDeckBridge.shared.cachedStatusJSON()
        return httpResponse(status: 200, contentType: "application/json", body: data)
    }
    
    private func handlePost(name: Notification.Name) -> Data {
        Task { @MainActor in
            NotificationCenter.default.post(name: name, object: nil)
        }
        return httpResponse(
            status: 200,
            contentType: "application/json",
            body: #"{"ok":true}"#.data(using: .utf8) ?? Data()
        )
    }

    private func handleTrustByName(body: Data) -> Data {
        // Expect JSON: {"name":"..."}
        var driveName: String?
        if let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            driveName = obj["name"] as? String
        }

        guard let name = driveName, !name.isEmpty else {
            return httpResponse(
                status: 400,
                contentType: "application/json",
                body: #"{"ok":false,"error":"Missing name"}"#.data(using: .utf8) ?? Data()
            )
        }

        Task { @MainActor in
            NotificationCenter.default.post(name: .sdTrustByName, object: nil, userInfo: ["name": name])
        }

        return httpResponse(
            status: 200,
            contentType: "application/json",
            body: #"{"ok":true}"#.data(using: .utf8) ?? Data()
        )
    }
    
    private func handleTrustByUUID(body: Data) -> Data {
        var uuidString: String?
        if let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            uuidString = obj["uuid"] as? String
        }

        guard let uuid = uuidString, !uuid.isEmpty else {
            return httpResponse(
                status: 400,
                contentType: "application/json",
                body: #"{"ok":false,"error":"Missing uuid"}"#.data(using: .utf8) ?? Data()
            )
        }

        Task { @MainActor in
            NotificationCenter.default.post(name: .sdTrustByUUID, object: nil, userInfo: ["uuid": uuid])
        }

        return httpResponse(
            status: 200,
            contentType: "application/json",
            body: #"{"ok":true}"#.data(using: .utf8) ?? Data()
        )
    }

    // MARK: - Response formatting

    private func sendResponseAndClose(_ data: Data, on conn: NWConnection) {
        conn.send(content: data, completion: .contentProcessed { error in
            if let error {
                print("⚠️ LocalControlServer send error: \(error)")
            }
            conn.cancel()
        })
    }

    private func httpResponse(status: Int, contentType: String, body: Data) -> Data {
        let reason = reasonPhrase(for: status)
        var headers = ""
        headers += "HTTP/1.1 \(status) \(reason)\r\n"
        headers += "Connection: close\r\n"
        headers += "Content-Type: \(contentType)\r\n"
        headers += "Content-Length: \(body.count)\r\n"

        // CORS (helpful for local development)
        headers += "Access-Control-Allow-Origin: *\r\n"
        headers += "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
        headers += "Access-Control-Allow-Headers: Content-Type\r\n"

        headers += "\r\n"

        var out = Data(headers.utf8)
        out.append(body)
        return out
    }

    private func reasonPhrase(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        case 503: return "Service Unavailable"
        default:  return "OK"
        }
    }
}
