import Foundation

struct PlaybackRequest: Equatable {
    let urlString: String
    let headers: [String: String]

    static func parse(_ value: String, additionalHeaders: [String: String] = [:]) -> PlaybackRequest {
        let parts = value.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let url = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        var headers = additionalHeaders
        guard parts.count > 1 else { return PlaybackRequest(urlString: url, headers: headers) }

        for pair in parts[1].split(separator: "&", omittingEmptySubsequences: true) {
            let fields = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard fields.count == 2 else { continue }
            let rawKey = String(fields[0]).replacingOccurrences(of: "+", with: " ")
            let rawValue = String(fields[1]).replacingOccurrences(of: "+", with: " ")
            let key = rawKey.removingPercentEncoding ?? rawKey
            let value = rawValue.removingPercentEncoding ?? rawValue
            if !key.isEmpty { headers[normalizedHeader(key)] = value }
        }
        return PlaybackRequest(urlString: url, headers: headers)
    }

    private static func normalizedHeader(_ key: String) -> String {
        switch key.lowercased() {
        case "user-agent", "user_agent": return "User-Agent"
        case "referer", "referrer": return "Referer"
        case "origin": return "Origin"
        case "cookie": return "Cookie"
        default: return key
        }
    }
}
