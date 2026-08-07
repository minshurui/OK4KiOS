import Foundation

let service = LiveService()

// 1. Standard M3U
let m3u = """
#EXTM3U
#EXTINF:-1 tvg-id="CCTV1" group-title="央视" tvg-logo="https://example.test/cctv1.png",CCTV-1
http://example.test/cctv1.m3u8
#EXTINF:-1 group-title="央视",CCTV-2
http://example.test/cctv2.m3u8
"""
let g1 = service.parse(m3u)
assert(g1.count == 1, "group count \(g1.count)")
assert(g1[0].name == "央视", "group name \(g1[0].name)")
assert(g1[0].channels.count == 2, "channels \(g1[0].channels.count)")
assert(g1[0].channels[0].name == "CCTV-1")
assert(g1[0].channels[0].logoURL?.absoluteString == "https://example.test/cctv1.png")
print("M3U OK, channels:", g1[0].channels.count)

// 2. TXT
let txt = """
#EXTM3U
凤凰卫视,http://example.test/fh.m3u8
香港台,http://example.test/hk.m3u8
"""
let g2 = service.parse(txt)
let ch2 = g2.flatMap(\.channels)
assert(ch2.count == 2, "txt channels \(ch2.count)")
assert(ch2[0].name == "凤凰卫视")
print("TXT OK, channels:", ch2.count)

// 3. Headers suffix
let hdr = """
#EXTM3U
#EXTINF:-1 group-title="测试",加密台
http://example.test/live.m3u8|User-Agent=OK%204K&Referer=https%3A%2F%2Fexample.test%2F
"""
let g3 = service.parse(hdr)
let c3 = g3.first?.channels.first
assert(c3?.headers["User-Agent"] == "OK 4K", "UA \(String(describing: c3?.headers["User-Agent"]))")
assert(c3?.headers["Referer"] == "https://example.test/")
print("Headers OK:", c3?.headers ?? [:])

// 4. TVBox lives JSON
let json = """
{"lives":[{"name":"精选直播","type":0,"url":"http://example.test/live.m3u","ua":"VLC/3.0.21"},{"name":"单频道","type":1,"url":"http://example.test/channel.m3u8","ua":"VLC/3.0.21"}]}
"""
let g4 = service.parse(json)
let ch4 = g4.flatMap(\.channels)
assert(!ch4.isEmpty, "lives json channels \(ch4.count)")
assert(ch4.allSatisfy { $0.url.absoluteString.contains("channel.m3u8") }, "playlist should be skipped in sync: \(ch4.map(\.url.absoluteString))")
print("TVBox lives OK:", ch4.map { "\($0.name)=\($0.url.absoluteString)" })

// 5. URLS JSON
let json2 = """
{"urls":[{"name":"综合源","url":"http://example.test/iptv.m3u"},{"name":"备用源","url":"http://example.test/backup.txt"}]}
"""
let g5 = service.parse(json2)
assert(!g5.flatMap(\.channels).isEmpty)
print("URLs OK")

// 6. Semicolon group
let semi = """
#EXTM3U
#EXTINF:-1 group-title="教育;科学",CCTV-10
http://example.test/cctv10.m3u8
"""
let g6 = service.parse(semi)
assert(g6.first?.name == "教育,科学", "semi \(String(describing: g6.first?.name))")
print("Semicolon OK:", g6.first?.name ?? "")

print("ALL PARSE TESTS PASSED")
