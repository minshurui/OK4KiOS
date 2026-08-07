import XCTest
@testable import OK4KiOS

final class LiveServiceTests: XCTestCase {
    private let service = LiveService()

    func testParsesStandardM3U() {
        let text = """
        #EXTM3U
        #EXTINF:-1 tvg-id="CCTV1" group-title="央视" tvg-logo="https://example.test/cctv1.png",CCTV-1
        http://example.test/cctv1.m3u8
        #EXTINF:-1 tvg-id="CCTV2" group-title="央视",CCTV-2
        http://example.test/cctv2.m3u8
        """
        let groups = service.parse(text)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.name, "央视")
        XCTAssertEqual(groups.first?.channels.count, 2)
        XCTAssertEqual(groups.first?.channels[0].name, "CCTV-1")
        XCTAssertEqual(groups.first?.channels[0].url.absoluteString, "http://example.test/cctv1.m3u8")
        XCTAssertEqual(groups.first?.channels[0].logoURL?.absoluteString, "https://example.test/cctv1.png")
    }

    func testParsesTXTNameCommaURL() {
        let text = """
        #EXTM3U
        凤凰卫视,http://example.test/fh.m3u8
        香港台,http://example.test/hk.m3u8
        """
        let groups = service.parse(text)
        let channels = groups.flatMap(\.channels)
        XCTAssertEqual(channels.count, 2)
        XCTAssertEqual(channels[0].name, "凤凰卫视")
        XCTAssertEqual(channels[0].url.absoluteString, "http://example.test/fh.m3u8")
    }

    func testParsesM3UWithHeadersSuffix() {
        let text = """
        #EXTM3U
        #EXTINF:-1 group-title="测试",加密台
        http://example.test/live.m3u8|User-Agent=OK%204K&Referer=https%3A%2F%2Fexample.test%2F
        """
        let groups = service.parse(text)
        let channel = groups.first?.channels.first
        XCTAssertEqual(channel?.headers["User-Agent"], "OK 4K")
        XCTAssertEqual(channel?.headers["Referer"], "https://example.test/")
    }

    func testParsesTVBoxLivesJSON() {
        let json = """
        {"lives":[
          {"name":"精选直播","type":0,"url":"http://example.test/live.m3u","ua":"VLC/3.0.21","epg":"http://epg.test"},
          {"name":"单频道","type":1,"url":"http://example.test/channel.m3u8","ua":"VLC/3.0.21"}
        ]}
        """
        let groups = service.parse(json)
        XCTAssertFalse(groups.isEmpty)
    }

    func testParsesURLsJSON() {
        let json = """
        {"urls":[{"name":"综合源","url":"http://example.test/iptv.m3u"},{"name":"备用源","url":"http://example.test/backup.txt"}]}
        """
        let groups = service.parse(json)
        XCTAssertFalse(groups.isEmpty)
    }

    func testGroupTitleSemicolonSplit() {
        let text = """
        #EXTM3U
        #EXTINF:-1 group-title="教育;科学",CCTV-10
        http://example.test/cctv10.m3u8
        """
        let groups = service.parse(text)
        XCTAssertEqual(groups.first?.name, "教育,科学")
    }
}
