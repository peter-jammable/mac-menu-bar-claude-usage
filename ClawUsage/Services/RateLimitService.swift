import Foundation

enum RateLimitService {
    private static let usageURL = "https://api.anthropic.com/api/oauth/usage"

    static func fetchUsage(accessToken: String) async throws -> UsageData {
        var request = URLRequest(url: URL(string: usageURL)!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RateLimitError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw RateLimitError.unauthorized
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RateLimitError.apiFailed(statusCode: httpResponse.statusCode, body: body)
        }

        return try JSONDecoder().decode(UsageData.self, from: data)
    }
}

enum RateLimitError: LocalizedError, Equatable {
    case invalidResponse
    case unauthorized
    case apiFailed(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from API"
        case .unauthorized:
            return "Access token is invalid or expired"
        case .apiFailed(let code, let body):
            return "API error (\(code)): \(body)"
        }
    }
}
