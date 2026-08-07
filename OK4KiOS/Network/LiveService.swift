import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct LiveService {
    private let client: APIClientProtocol

    init(client: APIClientProtocol = APIClient()) {
        self.client = client
    }
    enum LiveError: LocalizedError {
        case invalidURL
        case invalidPlaylist
        var errorDescription: String? {
            switch self {
            case .invalidURL: return "直播源地址无效"
            case .invalidPlaylist: return "无法解析 M3U 直播源"
            }
        }
    }

    func load(urlString: String) async throws -> [LiveGroup] {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw LiveError.invalidURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("OK4KiOS/1.0", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await client.data(for: request)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .unicode) else {
            throw LiveError.invalidPlaylist
        }
        return parse(text)
    }

    func parse(_ text: String) -> [LiveGroup] {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var channels: [LiveChannel] = []
        var pendingName = ""
        var pendingGroup = "未分组"
        for line in lines {
            guard !line.isEmpty else { continue }
            if line.hasPrefix("#EXTINF") {
                pendingName = line.split(separator: ",", maxSplits: 1).dropFirst().first.map(String.init) ?? "未命名频道"
                if let range = line.range(of: "group-title=\"") {
                    let tail = line[range.upperBound...]
                    pendingGroup = String(tail.split(separator: "\"", maxSplits: 1).first ?? "未分组")
                }
            } else if !line.hasPrefix("#"), let url = URL(string: line), !pendingName.isEmpty {
                channels.append(LiveChannel(id: UUID().uuidString, name: pendingName, url: url, group: pendingGroup))
                pendingName = ""
            }
        }
        return Dictionary(grouping: channels, by: { $0.group })
            .map { LiveGroup(id: $0.key, name: $0.key, channels: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
