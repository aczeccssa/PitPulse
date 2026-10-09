import Foundation
@testable import F1Companion

enum TestData {
    static func date(_ value: String) -> Date {
        RFC3339.parse(value)!
    }

    static func session(
        id: String = "2026:1:fp1",
        meetingId: String = "2026:1",
        type: SessionType = .fp1,
        start: String = "2026-03-06T01:30:00Z",
        status: SessionStatus = .scheduled
    ) -> Session {
        Session(
            id: id,
            meetingId: meetingId,
            sessionType: type,
            startTime: date(start),
            endTime: nil,
            status: status,
            jolpicaSessionId: nil,
            openf1SessionKey: nil
        )
    }

    static func meeting(
        id: String = "2026:1",
        season: Int = 2026,
        round: Int? = 1,
        name: String = "Australian Grand Prix",
        country: String = "Australia",
        code: String? = "AU",
        status: MeetingStatus = .scheduled,
        sessions: [Session]? = nil
    ) -> Meeting {
        Meeting(
            id: id,
            season: season,
            round: round,
            name: name,
            country: country,
            countryCode: code,
            location: "Melbourne",
            startDate: date("2026-03-06T01:30:00Z"),
            endDate: date("2026-03-08T04:00:00Z"),
            status: status,
            sessions: sessions ?? [session(id: "\(id):fp1", meetingId: id)],
            source: "fixture",
            fetchedAt: date("2026-03-01T00:00:00Z"),
            sourceUpdatedAt: nil,
            revision: 1
        )
    }

    static func meta(schemaVersion: Int = 1, revision: Int = 1, stale: Bool = false) -> ResponseMeta {
        ResponseMeta(
            schemaVersion: schemaVersion,
            revision: revision,
            stale: stale,
            quality: stale ? .stale : .provisional,
            source: "fixture",
            fetchedAt: date("2026-03-01T00:00:00Z"),
            sourceUpdatedAt: nil
        )
    }

    static func envelope(
        meetings: [Meeting] = [meeting()],
        schemaVersion: Int = 1
    ) -> APIEnvelope<[Meeting]> {
        APIEnvelope(data: meetings, meta: meta(schemaVersion: schemaVersion))
    }
}

final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
