import Foundation

struct GuangyaDriveItem: Equatable, Sendable {
    let id: String
    let name: String
    let isFolder: Bool
    let size: Int64
    let raw: Data
}

struct GuangyaShareContext: Equatable, Sendable {
    let shareID: String
    let accessToken: String
    let code: String
}

struct GuangyaPlayback: Equatable, Sendable {
    let url: URL
    let headers: [String: String]
}

protocol GuangyaAuthorizationProviding {
    func authorizationHeader() async throws -> String
}

extension GuangyaSession: GuangyaAuthorizationProviding {}

struct GuangyaDriveService {
    static let apiBase = "https://api.guangyapan.com"
    private let client: GuangyaHTTPClientProtocol
    private let authorizationProvider: GuangyaAuthorizationProviding

    init(client: GuangyaHTTPClientProtocol = GuangyaHTTPClient(), authorizationProvider: GuangyaAuthorizationProviding = GuangyaSession.shared) {
        self.client = client
        self.authorizationProvider = authorizationProvider
    }

    func myFiles(parentID: String = "", page: Int = 1) async throws -> [GuangyaDriveItem] {
        let result = try await api(primary: "/userres/v1/file/get_file_list", fallback: "/nd.bizuserres.s/v1/file/get_file_list", body: [
            "parentId": parentID, "page": max(0, page - 1), "pageSize": 50, "orderBy": 3, "sortType": 1
        ], authorized: true)
        return try items(result)
    }

    func shareAccessToken(shareID: String, code: String = "") async throws -> String {
        var body: [String: Any] = ["shareId": shareID]
        if !code.isEmpty { body["code"] = code }
        let result = try await api(primary: "/userres/v1/get_share_access_token", fallback: "/nd.bizuserres.s/v1/get_share_access_token", body: body, authorized: false)
        let root = try dictionary(result)
        let data = root["data"] as? [String: Any] ?? root
        guard let token = firstString(data, root, keys: ["accessToken", "access_token"]) else { throw GuangyaDriveError.invalidResponse }
        return token
    }

    func shareFiles(_ share: GuangyaShareContext, parentID: String = "", page: Int = 1) async throws -> [GuangyaDriveItem] {
        let result = try await api(primary: "/userres/v1/get_share_page_files_list", fallback: "/nd.bizuserres.s/v1/get_share_page_files_list", body: [
            "parentId": parentID, "page": max(0, page - 1), "pageSize": 50,
            "orderBy": 3, "sortType": 1, "accessToken": share.accessToken
        ], authorized: false)
        return try items(result)
    }

    func ensureTransferFolder(named name: String = "FishGuangYa") async throws -> String {
        if let existing = try await myFiles().first(where: { $0.isFolder && $0.name == name }) { return existing.id }
        let result = try await api(primary: "/userres/v1/file/create_dir", fallback: "/nd.bizuserres.s/v1/file/create_dir", body: [
            "parentId": "", "dirName": name, "fileName": name, "failIfNameExist": false
        ], authorized: true)
        let root = try dictionary(result)
        let data = root["data"] as? [String: Any] ?? root
        if let id = firstString(data, root, keys: ["fileId", "id"]) { return id }
        if let existing = try await myFiles().first(where: { $0.isFolder && $0.name == name }) { return existing.id }
        throw GuangyaDriveError.transferFileNotFound
    }

    func restore(fileIDs: [String], shareAccessToken: String, parentID: String) async throws -> String? {
        let result = try await api(primary: "/userres/v1/restore_share", fallback: "/nd.bizuserres.s/v1/restore_share", body: [
            "accessToken": shareAccessToken, "fileIds": fileIDs, "parentId": parentID
        ], authorized: true)
        let root = try dictionary(result)
        let data = root["data"] as? [String: Any] ?? root
        return firstString(data, root, keys: ["taskId", "taskID", "id"])
    }

    func waitForTask(_ taskID: String) async throws {
        guard !taskID.isEmpty else { return }
        for _ in 0..<30 {
            let result = try await api(primary: "/userres/v1/get_task_status", fallback: "/nd.bizuserres.s/v1/get_task_status", body: ["taskId": taskID], authorized: true)
            let root = try dictionary(result)
            let data = root["data"] as? [String: Any] ?? root
            let state = firstString(data, root, keys: ["status", "taskStatus", "state"])?.lowercased() ?? ""
            if ["success", "done", "2"].contains(state) || (data["finished"] as? Bool == true) { return }
            if ["failed", "error"].contains(state) { throw GuangyaDriveError.taskFailed }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        throw GuangyaDriveError.taskTimeout
    }

    func transferAndPlayback(fileID: String, fileName: String, shareAccessToken: String) async throws -> GuangyaPlayback {
        let folderID = try await ensureTransferFolder()
        let task = try await restore(fileIDs: [fileID], shareAccessToken: shareAccessToken, parentID: folderID)
        if let task { try await waitForTask(task) }
        let files = try await myFiles(parentID: folderID)
        guard let restored = files.first(where: { $0.name == fileName }) ?? files.first else {
            throw GuangyaDriveError.transferFileNotFound
        }
        return try await myPlayback(fileID: restored.id)
    }

    func myPlayback(fileID: String) async throws -> GuangyaPlayback {
        try await playback(path: "/userres/v1/get_res_download_url", fallback: "/nd.bizuserres.s/v1/get_res_download_url", body: ["fileId": fileID], authorized: true)
    }

    func sharePlayback(fileID: String, accessToken: String) async throws -> GuangyaPlayback {
        try await playback(path: "/userres/v1/get_share_download_url", fallback: "/nd.bizuserres.s/v1/get_share_download_url", body: ["fileId": fileID, "accessToken": accessToken], authorized: false)
    }

    private func playback(path: String, fallback: String, body: [String: Any], authorized: Bool) async throws -> GuangyaPlayback {
        let result = try await api(primary: path, fallback: fallback, body: body, authorized: authorized)
        let root = try dictionary(result)
        let data = root["data"] as? [String: Any] ?? root
        guard let text = firstString(data, root, keys: ["signedURL", "signedUrl", "downloadUrl", "downloadURL", "url"]),
              let url = URL(string: text) else { throw GuangyaDriveError.noPlayableURL }
        return GuangyaPlayback(url: url, headers: [
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
            "Referer": "https://www.guangyapan.com/"
        ])
    }

    private func api(primary: String, fallback: String, body: [String: Any], authorized: Bool) async throws -> Data {
        let authorization = authorized ? try await authorizationProvider.authorizationHeader() : nil
        var result = try await post(path: primary, body: body, authorization: authorization)
        if [400, 404].contains(result.response.statusCode) {
            result = try await post(path: fallback, body: body, authorization: authorization)
        }
        guard result.response.statusCode < 400 else { throw GuangyaDriveError.http(result.response.statusCode) }
        return result.data
    }

    private func post(path: String, body: [String: Any], authorization: String?) async throws -> (data: Data, response: HTTPURLResponse) {
        guard let url = URL(string: Self.apiBase + path) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://www.guangyapan.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.guangyapan.com/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        if let authorization { request.setValue(authorization, forHTTPHeaderField: "Authorization") }
        return try await client.data(for: request)
    }

    private func items(_ response: Data) throws -> [GuangyaDriveItem] {
        let root = try dictionary(response)
        let data = root["data"] as? [String: Any] ?? root
        let arrays = [data["list"], data["files"], data["items"], root["list"], root["files"]]
        let values = arrays.compactMap { $0 as? [[String: Any]] }.first ?? []
        return try values.compactMap { item in
            guard let id = firstString(item, item, keys: ["fileId", "id", "resId"]) else { return nil }
            let name = firstString(item, item, keys: ["fileName", "name", "title"]) ?? id
            let type = firstString(item, item, keys: ["type", "obj_category"])?.lowercased()
            let number = (item["resType"] as? NSNumber)?.intValue ?? (item["fileType"] as? NSNumber)?.intValue
            let folder = number == 2 || type == "folder" || type == "dir" || item["isFolder"] as? Bool == true
            let size = (item["size"] as? NSNumber)?.int64Value ?? (item["fileSize"] as? NSNumber)?.int64Value ?? 0
            return GuangyaDriveItem(id: id, name: name, isFolder: folder, size: size,
                                    raw: try JSONSerialization.data(withJSONObject: item, options: [.sortedKeys]))
        }
    }

    private func dictionary(_ data: Data) throws -> [String: Any] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw GuangyaDriveError.invalidResponse }
        return root
    }

    private func firstString(_ primary: [String: Any], _ fallback: [String: Any], keys: [String]) -> String? {
        for key in keys {
            for object in [primary, fallback] {
                if let value = object[key] as? String {
                    let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !clean.isEmpty { return clean }
                }
            }
        }
        return nil
    }
}

enum GuangyaDriveError: LocalizedError, Equatable {
    case invalidResponse
    case http(Int)
    case noPlayableURL
    case taskFailed
    case taskTimeout
    case transferFileNotFound

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "光鸭网盘响应无效"
        case .http(let status): return "光鸭网盘请求失败（HTTP \(status)）"
        case .noPlayableURL: return "光鸭未返回可播放地址"
        case .taskFailed: return "光鸭转存任务失败"
        case .taskTimeout: return "光鸭转存任务超时"
        case .transferFileNotFound: return "光鸭转存文件未找到"
        }
    }
}
