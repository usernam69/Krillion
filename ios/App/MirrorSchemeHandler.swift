import Foundation
import WebKit

/// Serves the bundled Krillion mirror through a custom `krillion://` scheme.
/// Mirrors the routing logic of the repository's server.js: static files,
/// directory index.html fallbacks, RSC payloads and an API proxy to krillion.io.
final class MirrorSchemeHandler: NSObject, WKURLSchemeHandler {
    private let root: URL

    init(root: URL) {
        self.root = root
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let request = urlSchemeTask.request
        guard let url = request.url else {
            fail(urlSchemeTask, status: 400, message: "bad request")
            return
        }

        let pathname = url.path.isEmpty ? "/" : url.path
        let query = url.query ?? ""

        if pathname == "/healthz" {
            respond(urlSchemeTask, url: url, status: 200,
                    data: Data("{\"ok\":true}".utf8), type: "application/json; charset=utf-8")
            return
        }

        if pathname == "/api" || pathname.hasPrefix("/api/") {
            proxy(request, originalURL: url, task: urlSchemeTask)
            return
        }

        let decoded = pathname.removingPercentEncoding ?? pathname
        let name = decoded.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let isRSC = query.split(separator: "&").contains { $0.hasPrefix("_rsc") }
        if isRSC {
            let rscName = (name.isEmpty ? "index" : name).replacingOccurrences(of: "/", with: "__")
            let file = root.appendingPathComponent("rsc", isDirectory: true)
                           .appendingPathComponent(rscName + ".rsc")
            serve(file, url: url, task: urlSchemeTask, status: 200,
                  type: "text/x-component; charset=utf-8")
            return
        }

        var file = root.appendingPathComponent(name.isEmpty ? "index.html" : name)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                file = file.appendingPathComponent("index.html")
            }
        } else {
            file = file.appendingPathComponent("index.html")
        }

        if FileManager.default.fileExists(atPath: file.path) {
            serve(file, url: url, task: urlSchemeTask, status: 200, type: Self.mime(for: file.pathExtension))
        } else {
            let notFound = root.appendingPathComponent("404.html")
            serve(notFound, url: url, task: urlSchemeTask, status: 404, type: "text/html; charset=utf-8")
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func serve(_ file: URL, url: URL, task: WKURLSchemeTask, status: Int, type: String) {
        guard let data = try? Data(contentsOf: file) else {
            fail(task, status: status == 404 ? 404 : 500, message: "not found")
            return
        }
        respond(task, url: url, status: status, data: data, type: type)
    }

    private func respond(_ task: WKURLSchemeTask, url: URL, status: Int, data: Data, type: String) {
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": type, "Cache-Control": "no-store"])!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    private func fail(_ task: WKURLSchemeTask, status: Int, message: String) {
        respond(task, url: task.request.url ?? URL(string: "krillion://local/")!, status: status,
                data: Data(message.utf8), type: "text/plain; charset=utf-8")
    }

    private func proxy(_ request: URLRequest, originalURL: URL, task: WKURLSchemeTask) {
        guard var components = URLComponents(url: originalURL, resolvingAgainstBaseURL: false),
              let target = { () -> URL? in
                  components.scheme = "https"
                  components.host = "krillion.io"
                  components.port = nil
                  return components.url
              }() else {
            fail(task, status: 400, message: "bad request")
            return
        }

        var proxied = URLRequest(url: target)
        proxied.httpMethod = request.httpMethod
        proxied.httpBody = request.httpBody
        for (key, value) in request.allHTTPHeaderFields ?? [:] {
            let lower = key.lowercased()
            if ["host", "origin", "referer", "content-length"].contains(lower) { continue }
            proxied.setValue(value, forHTTPHeaderField: key)
        }

        URLSession.shared.dataTask(with: proxied) { data, response, error in
            guard error == nil, let data = data else {
                self.fail(task, status: 502,
                          message: "proxy error: \(error?.localizedDescription ?? "unknown")")
                return
            }
            let http = response as? HTTPURLResponse
            let type = (http?.allHeaderFields["Content-Type"] as? String) ?? "application/octet-stream"
            self.respond(task, url: originalURL, status: http?.statusCode ?? 200,
                         data: data, type: type)
        }.resume()
    }

    private static func mime(for ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "js": return "application/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        case "svg": return "image/svg+xml"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "ico": return "image/x-icon"
        case "txt": return "text/plain; charset=utf-8"
        case "xml": return "application/xml; charset=utf-8"
        default: return "application/octet-stream"
        }
    }
}
