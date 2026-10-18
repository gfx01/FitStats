import Foundation

// Shapes returned by the coach routes of the `fitstats` Edge Function (lib/coach.ts).

struct CoachStatus: Codable {
    let configured: Bool
    let model: String
    let models: [CoachModelOption]
    let usage: CoachUsage?
    let dailyLimit: Int?

    enum CodingKeys: String, CodingKey {
        case configured, model, models, usage
        case dailyLimit = "daily_limit"
    }
}

struct CoachModelOption: Codable, Identifiable, Hashable {
    let id: String
    let label: String
    let note: String
}

struct CoachUsage: Codable {
    let requests: Int
    let input: Int
    let output: Int
    let cacheRead: Int
    let cacheWrite: Int
    let costUsd: Double
    let month: String?
    let dayRequests: Int?

    enum CodingKeys: String, CodingKey {
        case requests, input, output, month
        case cacheRead = "cache_read"
        case cacheWrite = "cache_write"
        case costUsd = "cost_usd"
        case dayRequests = "day_requests"
    }
}

struct CoachThread: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, title
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct CoachThreadsResponse: Codable {
    let threads: [CoachThread]
}

struct CoachMessage: Codable, Identifiable, Equatable {
    let id: String
    let role: String
    let content: String
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, role, content
        case createdAt = "created_at"
    }

    var isUser: Bool { role == "user" }
}

struct CoachThreadResponse: Codable {
    let thread: CoachThread
    let messages: [CoachMessage]
}

struct CoachBrief: Codable, Equatable {
    let date: String
    let text: String
    let createdAt: String
    let model: String?

    enum CodingKeys: String, CodingKey {
        case date, text, model
        case createdAt = "created_at"
    }
}

struct CoachBriefResponse: Codable {
    let brief: CoachBrief?
}

/// One server-sent event from the `coach` route: status, text, done or error.
struct CoachEvent: Decodable {
    let type: String
    let text: String?
    let message: String?
    let code: String?
    let threadId: String?
    let messageId: String?
    let brief: CoachBrief?
    let usage: CoachUsage?

    enum CodingKeys: String, CodingKey {
        case type, text, message, code, brief, usage
        case threadId = "thread_id"
        case messageId = "message_id"
    }
}

struct CoachFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
