import Foundation
import CryptoKit

/// Signs Yandex Music audio stream URLs using MD5 hashing according to official client specification.
public enum YMAudioURLSigner {
    /// Secret salt constant used by official Yandex Music clients
    public static let secretSalt = "XGRlBW9FXlekgbPrRHuSiA"

    /// Android client key (используется для /tracks/{id}/lyrics и legacy Android /get-file-info).
    public static let fileInfoSecretKey = "p93jhgh689SBReK6ghtw62"
    public static let lyricsSecretKey = "p93jhgh689SBReK6ghtw62"

    /// Desktop client key + header (основной протокол для /get-file-info с raw lossless/HQ потоками).
    public static let desktopFileInfoSecretKey = "kzqU4XhfCaY6B6JTHODeq5"
    public static let desktopClientHeader = "YandexMusicDesktopAppWindows/5.95.0"

    /// Computes HMAC-SHA256 signature for GET /get-file-info
    /// Formula: HMAC<SHA256>(secretKey, "\(ts)\(cleanTrackId)\(quality)\(codecsWithoutCommas)\(transportsWithoutCommas)")
    /// Signature: Base64 representation without trailing '=' (first 43 characters).
    public static func computeFileInfoSign(
        ts: String,
        trackId: String,
        quality: String,
        codecs: String = "flac,flac-mp4,mp3,aac,he-aac,aac-mp4",
        transports: String = "raw",
        secretKey: String = YMAudioURLSigner.desktopFileInfoSecretKey
    ) -> String {
        let cleanTrackId = trackId.components(separatedBy: ":").first ?? trackId
        let codecsWithoutCommas = codecs.replacingOccurrences(of: ",", with: "")
        let transportsWithoutCommas = transports.replacingOccurrences(of: ",", with: "")
        let stringToSign = "\(ts)\(cleanTrackId)\(quality)\(codecsWithoutCommas)\(transportsWithoutCommas)"
        let key = SymmetricKey(data: Data(secretKey.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: key)
        let base64 = Data(signature).base64EncodedString()
        return String(base64.prefix(43))
    }

    /// Convenience overload for GET /get-file-info with default parameters
    public static func computeFileInfoSign(
        trackId: String,
        quality: String = "lossless",
        codecs: String = "flac",
        transports: String = "direct",
        ts: Int = Int(Date().timeIntervalSince1970),
        secretKey: String = YMAudioURLSigner.desktopFileInfoSecretKey
    ) -> String {
        computeFileInfoSign(
            ts: String(ts),
            trackId: trackId,
            quality: quality,
            codecs: codecs,
            transports: transports,
            secretKey: secretKey
        )
    }

    /// Computes HMAC-SHA256 signature for GET /tracks/{trackId}/lyrics?format=LRC
    /// Formula: HMAC<SHA256>(secretKey, "\(numericTrackId)\(timestamp)")
    /// Signature: standard Base64 representation.
    public static func computeLyricsSign(trackId: String, timestamp: Int) -> String {
        let numericTrackId = trackId.components(separatedBy: ":").first ?? trackId
        let message = "\(numericTrackId)\(timestamp)"
        let key = SymmetricKey(data: Data(lyricsSecretKey.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        return Data(signature).base64EncodedString()
    }

    /// Computes MD5 hex digest string (lowercase) from raw string data.
    public static func md5Hex(_ string: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Computes sign hash from path and salt 's' according to formula:
    /// "XGRlBW9FXlekgbPrRHuSiA" + String(path.dropFirst()) + s
    public static func computeSign(path: String, s: String) -> String {
        let strippedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let stringToHash = secretSalt + strippedPath + s
        return md5Hex(stringToHash)
    }

    /// Generates the direct HTTPS download/streaming URL for the track.
    /// Format: `https://\(host)/get-mp3/\(sign)/\(ts)\(path)`
    public static func signStream(host: String, path: String, ts: String, s: String) -> URL? {
        let sign = computeSign(path: path, s: s)
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        let urlString = "https://\(host)/get-mp3/\(sign)/\(ts)\(normalizedPath)"
        return URL(string: urlString)
    }

    /// Convenience overload using `YMStreamData`
    public static func signStream(from streamData: YMStreamData) -> URL? {
        signStream(
            host: streamData.host,
            path: streamData.path,
            ts: streamData.ts,
            s: streamData.s
        )
    }
}
