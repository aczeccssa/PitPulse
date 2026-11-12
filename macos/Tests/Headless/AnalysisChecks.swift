import Foundation
@testable import SharedData

@main
struct AnalysisChecks {
    static func main() throws {
        assert(AnalysisMath.duration(2388.162) == "39:48.162")
        assert(AnalysisMath.duration(3661.001) == "1:01:01.001")
        assert(AnalysisMath.duration(nil) == "—")
        assert(AnalysisMath.duration(.nan) == "—")
        assert(AnalysisMath.duration(1e300) == "—")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            guard let date = RFC3339.parse(value) else { throw CocoaError(.coderReadCorrupt) }
            return date
        }
        let progress = try decoder.decode(ResponseMeta.self, from: Data(#"{"schemaVersion":1,"revision":0,"stale":false,"quality":"partial","analysisStatus":"loading"}"#.utf8))
        assert(progress.analysisIsLoading && !progress.analysisCanBeCached)
        let failed = try decoder.decode(ResponseMeta.self, from: Data(#"{"schemaVersion":1,"revision":0,"stale":true,"quality":"partial","analysisStatus":"failed","analysisError":"unavailable"}"#.utf8))
        assert(!failed.analysisIsLoading && !failed.analysisCanBeCached && failed.analysisError == "unavailable")
        let legacy = try decoder.decode(ResponseMeta.self, from: Data(#"{"schemaVersion":1,"revision":1,"stale":false,"quality":"partial"}"#.utf8))
        assert(!legacy.analysisIsLoading && legacy.analysisCanBeCached)
        let row = try decoder.decode(AnalysisTelemetry.self, from: Data(#"{"date":"2026-10-10T10:12:00.125000+00:00","speed":240,"throttle":null,"nGear":7,"unknown":true}"#.utf8))
        assert(row.speed == 240 && row.throttle == nil && row.nGear == 7 && row.rpm == nil)
        assert(AnalysisMath.telemetry(at: row.date!.addingTimeInterval(0.8), in: [row]) != nil)
        assert(AnalysisMath.telemetry(at: row.date!.addingTimeInterval(1.01), in: [row]) == nil)
        assert(AnalysisMath.telemetry(at: nil, in: [row]) == nil)
        let missing = try decoder.decode(AnalysisRound.self, from: Data(#"{"round":1,"entries":[{"points":8},{"points":null}]}"#.utf8))
        assert(missing.points == nil)
        let complete = try decoder.decode(AnalysisRound.self, from: Data(#"{"round":1,"entries":[{"points":8},{"points":3}]}"#.utf8))
        assert(complete.points == 11)
        let lap = try decoder.decode(AnalysisLap.self, from: Data(#"{"lapNumber":1,"durationSector1":null,"durationSector2":30.5}"#.utf8))
        assert(lap.sectors[0] == nil && lap.sectors[1] == 30.5 && lap.sectors[2] == nil)
        for file in CommandLine.arguments.dropFirst() {
            let bytes = try Data(contentsOf: URL(fileURLWithPath: file))
            if file.contains("season") {
                let data = try decoder.decode(APIEnvelope<SeasonAnalysis>.self, from: bytes)
                print("Season analysis decoded: \(data.data.rounds.count) rounds")
            } else {
                let data = try decoder.decode(APIEnvelope<SessionAnalysis>.self, from: bytes)
                print("Session analysis decoded: \(data.data.laps.count) laps, \(data.data.location.count) coordinates, \(data.data.carData.count) telemetry samples")
            }
        }
        print("Analysis headless checks passed: duration, missing fields, unique time alignment, nullable points, sectors")
    }
}
