import Foundation

/// VodServiceProtocol adapter that dispatches to the Go spider engine
/// (libok4kspider.a) via GoSpiderBridge. Handles the wogg site rules and
/// type 4 rule sites until the Swift-side equivalents are complete.
struct GoSiteAdapter: VodServiceProtocol {
    let site: TVBoxSite

    private var host: String? { site.nativeBaseURLs.first?.absoluteString }

    func home(page: Int) async throws -> VodResult {
        let data = try await call(params: ["pg": String(page)])
        return try decodeItems(data, page: page)
    }

    func search(_ keyword: String, page: Int) async throws -> VodResult {
        let data = try await call(params: ["wd": keyword, "pg": String(page)])
        return try decodeItems(data, page: page)
    }

    func category(id: String, page: Int) async throws -> VodResult {
        let data = try await call(params: ["cateId": id, "pg": String(page)])
        return try decodeItems(data, page: page)
    }

    func detail(id: String) async throws -> Vod {
        let data = try await call(params: ["id": id])
        let detail = try JSONDecoder().decode(GoDetail.self, from: data)
        var vod = Vod(
            vodID: LossyString(id), vodName: LossyString(site.name), typeName: nil,
            vodPic: nil, vodRemarks: nil, vodYear: nil, vodArea: nil, vodDirector: nil, vodActor: nil,
            vodContent: LossyString(detail.info), vodPlayFrom: nil, vodPlayURL: nil
        )
        let froms = detail.playFrom
        let playFrom = froms.joined(separator: "$$$")
        let playURL = froms.map { detail.playURL[$0] ?? "" }.joined(separator: "$$$")
        vod = Vod(
            vodID: LossyString(id), vodName: LossyString(site.name), typeName: nil,
            vodPic: nil, vodRemarks: nil, vodYear: nil, vodArea: nil, vodDirector: nil, vodActor: nil,
            vodContent: LossyString(detail.info), vodPlayFrom: LossyString(playFrom), vodPlayURL: LossyString(playURL)
        )
        return vod
    }

    func player(flag: String, id: String) async throws -> SpiderPlayback {
        let data = try await call(params: ["flag": flag, "id": id])
        let url = try JSONDecoder().decode(String.self, from: data)
        return SpiderPlayback(url: url)
    }

    // MARK: - Private

    private func call(params: [String: String]) async throws -> Data {
        let request = requestJSON(params: params)
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let data: Data
                    if isWogg {
                        data = try GoSpiderBridge.home(siteJSON: request)
                    } else {
                        data = try invoke(params: params, siteJSON: request)
                    }
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func invoke(params: [String: String], siteJSON: String) throws -> Data {
        if params["cateId"] != nil { return try GoSpiderBridge.category(siteJSON: siteJSON) }
        if params["wd"] != nil { return try GoSpiderBridge.search(siteJSON: siteJSON) }
        if params["id"] != nil && params["flag"] != nil { return try GoSpiderBridge.play(siteJSON: siteJSON) }
        if params["id"] != nil { return try GoSpiderBridge.detail(siteJSON: siteJSON) }
        return try GoSpiderBridge.home(siteJSON: siteJSON)
    }

    private var isWogg: Bool {
        site.key.caseInsensitiveCompare("wogg") == .orderedSame || site.name.lowercased().contains("wogg")
    }

    private func requestJSON(params: [String: String]) -> String {
        var payload: [String: Any] = ["params": params]
        if isWogg {
            payload["site"] = "wogg"
        }
        if let host {
            payload["host"] = host
        }
        if site.type == 4, let rule = site.ext?.encodedString {
            payload["rule"] = rule
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    private func decodeItems(_ data: Data, page: Int) throws -> VodResult {
        let items = try JSONDecoder().decode([GoItem].self, from: data)
        let vods = items.map { item in
            Vod(
                vodID: LossyString(item.url), vodName: LossyString(item.name), typeName: nil,
                vodPic: LossyString(item.pic), vodRemarks: LossyString(item.remark),
                vodYear: nil, vodArea: nil, vodDirector: nil, vodActor: nil,
                vodContent: nil, vodPlayFrom: nil, vodPlayURL: nil
            )
        }
        return VodResult(
            code: LossyInt(1), msg: nil, page: LossyInt(page),
            pagecount: LossyInt(vods.isEmpty ? page : page + 1),
            limit: nil, total: nil, list: vods, class: nil, filters: nil
        )
    }
}

private struct GoItem: Decodable {
    let name: String
    let pic: String
    let url: String
    let remark: String
}

private struct GoDetail: Decodable {
    let info: String
    let playFrom: [String]
    let playURL: [String: String]

    enum CodingKeys: String, CodingKey {
        case info
        case playFrom = "play_from"
        case playURL = "play_url"
    }
}
