import Foundation

enum APIClientError: Error, Equatable, LocalizedError {
    case invalidServerAddress(String)
    case insecureRemoteServer
    case invalidResponse
    case transport(String)
    case timeout
    case unauthorized
    case rateLimited(retryAfter: Date?)
    case server(status: Int)
    case decoding(String)
    case incompatibleSchema(found: Int, expected: Int)

    var errorDescription: String? {
        switch self {
        case .invalidServerAddress:
            "服务器地址无效。"
        case .insecureRemoteServer:
            "仅允许本机使用 HTTP；远程服务器必须使用 HTTPS。"
        case .invalidResponse:
            "服务器响应格式无效。"
        case .transport:
            "无法连接服务器。"
        case .timeout:
            "连接服务器超时。"
        case .unauthorized:
            "Token 无效或缺失。"
        case let .rateLimited(retryAfter):
            if let retryAfter {
                "请求过于频繁，请在 \(retryAfter.formatted(date: .omitted, time: .shortened)) 后重试。"
            } else {
                "请求过于频繁，请稍后重试。"
            }
        case let .server(status):
            "服务器返回错误（HTTP \(status)）。"
        case .decoding:
            "服务器数据无法解析，可能是不兼容的版本。"
        case let .incompatibleSchema(found, expected):
            "数据契约版本不兼容：收到 \(found)，需要 \(expected)。"
        }
    }
}
