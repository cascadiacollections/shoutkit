import Foundation

/// Decodes ICY text (metadata blocks and in-body headers).
///
/// The ICY protocol never specified an encoding. Newer servers send UTF-8, but
/// many (KEXP among them) still send Latin-1 / Windows-1252, so `Sólstöður`
/// arrived as `S�lst��ur` when decoded as UTF-8 alone. Try strict UTF-8 first
/// (valid UTF-8 is almost never accidental), then Windows-1252, then Latin-1,
/// which maps every byte and so never fails.
enum ICYText {
    static func decode(_ data: Data) -> String {
        String(validating: data, as: UTF8.self)
            ?? String(bytes: data, encoding: .windowsCP1252)
            ?? String(bytes: data, encoding: .isoLatin1)
            ?? "" // Unreachable: Latin-1 maps every byte.
    }
}
