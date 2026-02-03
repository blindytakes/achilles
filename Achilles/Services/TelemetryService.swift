import Foundation

/// Sends OpenTelemetry trace spans to Grafana Cloud via HTTP POST (OTLP/JSON).
/// Zero external dependencies — uses only URLSession.
class TelemetryService {
    static let shared = TelemetryService()

    // MARK: - Grafana Cloud OTLP credentials
    private let endpoint   = "https://otlp-gateway-prod-us-east-3.grafana.net/otlp/v1/traces"
    private let instanceID = "1471077"
    private let apiKey     = "glc_eyJvIjoiMTYxOTE5MyIsIm4iOiJzdGFjay0xNDcxMDc3LW90bHAtd3JpdGUtdGhyb3diYWtzIiwiayI6IjBFY0wwRFdVM1QwVjRJWnpNSzE0Mjd6MyIsIm0iOnsiciI6InByb2QtdXMtZWFzdC0zIn19"

    // MARK: - Service identity (shows up in Tempo)
    private let serviceName    = "throwbaks-ios"
    private let serviceVersion = "3.3"   // matches MARKETING_VERSION in pbxproj

    private init() {}

    /// Call once on app launch.
    func initialize() {
        print("📊 TelemetryService initialized (service: \(serviceName) v\(serviceVersion))")
    }

    // MARK: - Span status
    enum SpanStatus {
        case ok
        case error
    }

    // MARK: - Public API

    /// Record a single span and fire-and-forget it to Grafana.
    func recordSpan(
        name: String,
        startTime: Date = Date(),
        durationMs: Int,
        attributes: [String: Any] = [:],
        status: SpanStatus = .ok
    ) {
        let payload = buildTracesPayload(
            spanName:   name,
            startTime:  startTime,
            durationMs: durationMs,
            attributes: attributes,
            status:     status
        )
        sendPayload(payload)
    }

    // MARK: - Payload construction

    private func buildTracesPayload(
        spanName: String,
        startTime: Date,
        durationMs: Int,
        attributes: [String: Any],
        status: SpanStatus
    ) -> [String: Any] {

        let traceID = randomHexString(length: 32)   // 16 bytes
        let spanID  = randomHexString(length: 16)   // 8  bytes

        // OTLP timestamps are nanoseconds since Unix epoch
        let startNanos = UInt64(startTime.timeIntervalSince1970 * 1_000_000_000)
        let endNanos   = startNanos + UInt64(durationMs) * 1_000_000

        let otlpAttributes = attributes.map { key, value -> [String: Any] in
            ["key": key, "value": anyValueObject(value)]
        }

        // OTLP status codes: 0 = UNSET, 1 = OK, 2 = ERROR
        let statusCode: Int = {
            switch status {
            case .ok:    return 1
            case .error: return 2
            }
        }()

        let span: [String: Any] = [
            "traceId":              traceID,
            "spanId":               spanID,
            "name":                 spanName,
            "kind":                 1,   // INTERNAL
            "startTimeUnixNano":    String(startNanos),
            "endTimeUnixNano":      String(endNanos),
            "attributes":           otlpAttributes,
            "status":               ["code": statusCode]
        ]

        let resourceAttributes: [[String: Any]] = [
            ["key": "service.name",             "value": ["stringValue": serviceName]],
            ["key": "service.version",          "value": ["stringValue": serviceVersion]],
            ["key": "telemetry.sdk.language",   "value": ["stringValue": "swift"]],
            ["key": "os.type",                  "value": ["stringValue": "ios"]]
        ]

        return [
            "resourceSpans": [
                [
                    "resource": ["attributes": resourceAttributes],
                    "scopeSpans": [
                        [
                            "scope": ["name": serviceName, "version": serviceVersion],
                            "spans": [span]
                        ]
                    ]
                ]
            ]
        ]
    }

    // MARK: - HTTP transport

    private func sendPayload(_ payload: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            print("❌ TelemetryService: JSON serialisation failed")
            return
        }
        guard let url = URL(string: endpoint) else {
            print("❌ TelemetryService: invalid endpoint URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod  = "POST"
        request.httpBody    = jsonData
        let basicToken = Data("\(instanceID):\(apiKey)".utf8).base64EncodedString()
        request.setValue("application/json",            forHTTPHeaderField: "Content-Type")
        request.setValue("Basic \(basicToken)",         forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                print("❌ TelemetryService: network error — \(error.localizedDescription)")
                return
            }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 200 || code == 202 {
                print("📤 Trace sent to Grafana Cloud successfully (HTTP \(code))")
            } else {
                print("❌ TelemetryService: Grafana returned HTTP \(code)")
            }
        }.resume()
    }

    // MARK: - Helpers

    private func anyValueObject(_ value: Any) -> [String: Any] {
        switch value {
        case let s as String:  return ["stringValue":  s]
        case let i as Int:     return ["intValue":     String(i)]
        case let d as Double:  return ["doubleValue":  d]
        case let b as Bool:    return ["boolValue":    b]
        default:               return ["stringValue":  "\(value)"]
        }
    }

    private func randomHexString(length: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: length / 2)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
