import Darwin
import Foundation
import os

/// A minimal loopback HTTP server using POSIX sockets for receiving Google OAuth callbacks.
/// Google Desktop OAuth clients automatically allow http://127.0.0.1:{port} as redirect URIs.
final class OAuthCallbackServer: @unchecked Sendable {
    let port: UInt16
    private var serverSocket: Int32
    private var closed = false

    /// Creates and starts the server on a random available port, bound to 127.0.0.1 only.
    init() throws {
        let sock = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else {
            throw MahisoftGALSyncError.oauthFlowFailed("Could not create socket: \(String(cString: strerror(errno)))")
        }

        // Allow port reuse
        var reuse: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        // Bind to 127.0.0.1 on port 0 (auto-assign)
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(sock, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            Darwin.close(sock)
            throw MahisoftGALSyncError.oauthFlowFailed("Could not bind socket: \(String(cString: strerror(errno)))")
        }

        // Start listening
        guard Darwin.listen(sock, 1) == 0 else {
            Darwin.close(sock)
            throw MahisoftGALSyncError.oauthFlowFailed("Could not listen on socket: \(String(cString: strerror(errno)))")
        }

        // Get the assigned port
        var boundAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &boundAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                getsockname(sock, sockPtr, &addrLen)
            }
        }

        self.serverSocket = sock
        self.port = UInt16(bigEndian: boundAddr.sin_port)

        Logger.auth.info("OAuth loopback server listening on 127.0.0.1:\(self.port)")
    }

    var redirectURI: String {
        "http://127.0.0.1:\(port)"
    }

    /// Waits for a single HTTP request (the OAuth callback), sends a response, and returns the request URL.
    func awaitCallback() async throws -> URL {
        let sock = self.serverSocket
        let port = self.port

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // Set a timeout so we don't hang forever (5 minutes)
                var timeout = timeval(tv_sec: 300, tv_usec: 0)
                setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

                // Accept one connection
                var clientAddr = sockaddr_in()
                var clientAddrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                let clientSock = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                        Darwin.accept(sock, sockPtr, &clientAddrLen)
                    }
                }

                guard clientSock >= 0 else {
                    continuation.resume(throwing: MahisoftGALSyncError.oauthFlowFailed(
                        "Timed out waiting for OAuth callback (or accept failed)"))
                    return
                }

                // Read the HTTP request
                var buffer = [UInt8](repeating: 0, count: 8192)
                let bytesRead = Darwin.read(clientSock, &buffer, buffer.count)

                guard bytesRead > 0,
                      let request = String(bytes: buffer[..<bytesRead], encoding: .utf8) else {
                    Darwin.close(clientSock)
                    continuation.resume(throwing: MahisoftGALSyncError.oauthFlowFailed("Empty request from browser"))
                    return
                }

                // Parse "GET /path?query HTTP/1.1" from the first line
                guard let firstLine = request.components(separatedBy: "\r\n").first,
                      let pathPart = firstLine.split(separator: " ").dropFirst().first else {
                    Darwin.close(clientSock)
                    continuation.resume(throwing: MahisoftGALSyncError.oauthFlowFailed("Malformed HTTP request"))
                    return
                }

                let fullURLString = "http://127.0.0.1:\(port)\(pathPart)"
                let hasError = fullURLString.contains("error=")

                // Send response HTML
                let body: String
                if hasError {
                    body = """
                    <html><body style="font-family:-apple-system,sans-serif;text-align:center;padding:60px;\
                    background:#1a1a1a;color:#fff"><h2>Authentication Failed</h2>\
                    <p>Something went wrong. Please try again from Mahisoft GAL Sync.</p>\
                    <p style="color:#888;font-size:13px">You can close this tab.</p></body></html>
                    """
                } else {
                    body = """
                    <html><body style="font-family:-apple-system,sans-serif;text-align:center;padding:60px;\
                    background:#1a1a1a;color:#fff"><h2>\u{2713} Signed in successfully</h2>\
                    <p>You can close this tab and return to Mahisoft GAL Sync.</p></body></html>
                    """
                }

                let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n\(body)"
                _ = response.withCString { ptr in
                    Darwin.write(clientSock, ptr, strlen(ptr))
                }
                Darwin.close(clientSock)

                if let url = URL(string: fullURLString) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: MahisoftGALSyncError.oauthFlowFailed("Could not parse callback URL"))
                }
            }
        }
    }

    func stop() {
        guard !closed else { return }
        closed = true
        Darwin.close(serverSocket)
        serverSocket = -1
        Logger.auth.info("OAuth loopback server stopped")
    }

    deinit {
        if !closed {
            Darwin.close(serverSocket)
        }
    }
}
