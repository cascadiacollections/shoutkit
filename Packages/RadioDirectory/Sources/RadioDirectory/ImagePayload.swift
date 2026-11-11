import Foundation

/// Whether a successful (2xx) image response is actually a web page.
///
/// Station artwork URLs are third-party and long-lived. When a broadcaster's
/// site goes into maintenance, or a domain lapses into a parking page, the old
/// image path keeps answering 200 with HTML. KEXP did exactly this in November
/// 2026 after a power outage: every path under kexp.org served the same
/// "Listen Live" page. Handed to ImageIO, that payload fails a thumbnail decode
/// for every surface and every size that asks for it.
///
/// Deliberately narrow: radio-browser favicons routinely arrive as
/// `application/octet-stream`, `text/plain`, or with no content type at all, so
/// only an explicit HTML type or an HTML document body is rejected. Anything
/// else is left for the decoder to judge. Mirrors `WebPageArtworkGuard` in
/// shoutkit-android.
public enum ImagePayload {
    public static func isWebPage(mimeType: String?, data: Data) -> Bool {
        if let mimeType = mimeType?.lowercased(),
           mimeType == "text/html" || mimeType == "application/xhtml+xml" {
            return true
        }
        return bodyLooksLikeHTML(data)
    }

    private static let htmlPrefixes = ["<!doctype html", "<html"]

    private static func bodyLooksLikeHTML(_ data: Data) -> Bool {
        // Only the head of the payload matters; skip a UTF-8 BOM and leading
        // whitespace, which servers commonly emit before the doctype.
        var head = data.prefix(64)
        if head.starts(with: [0xEF, 0xBB, 0xBF]) {
            head = head.dropFirst(3)
        }
        guard let text = String(bytes: head, encoding: .utf8) ?? String(bytes: head, encoding: .isoLatin1) else {
            return false
        }
        let trimmed = text.drop(while: \.isWhitespace).lowercased()
        return htmlPrefixes.contains { trimmed.hasPrefix($0) }
    }
}

public extension HTTPTransporting {
    /// ``data(for:)`` for image requests: also fails a 2xx response that is a
    /// web page (see ``ImagePayload``) with `URLError(.cannotDecodeContentData)`,
    /// so every artwork loader treats a maintenance page like a dead link instead
    /// of handing it to the decoder.
    func imageData(for request: URLRequest) async throws -> Data {
        let (data, response) = try await send(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPTransportError.invalidResponse
        }
        guard 200 ..< 300 ~= httpResponse.statusCode else {
            throw HTTPTransportError.httpStatus(httpResponse.statusCode)
        }
        guard ImagePayload.isWebPage(mimeType: httpResponse.mimeType, data: data) == false else {
            throw URLError(.cannotDecodeContentData)
        }
        return data
    }
}
