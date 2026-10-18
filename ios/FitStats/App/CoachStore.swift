import Foundation

/// Coach conversations, the daily briefing and model/usage info. Replies stream in
/// from the server, which holds the Claude API key and looks up your data.
@MainActor
final class CoachStore: ObservableObject {
    @Published private(set) var status: CoachStatus?
    @Published private(set) var threads: [CoachThread] = []
    @Published private(set) var threadId: String?
    @Published private(set) var messages: [CoachMessage] = []
    @Published private(set) var streamingText = ""
    @Published private(set) var toolStatus: String?
    @Published private(set) var isSending = false
    @Published private(set) var failedQuestion: String?
    @Published var error: String?

    @Published private(set) var brief: CoachBrief?
    @Published private(set) var briefStreaming = ""
    @Published private(set) var isBriefing = false
    @Published var briefError: String?

    var apiProvider: @MainActor () -> APIClient? = { nil }
    var onUnauthorized: @MainActor () -> Void = {}

    private var fixtureDir: URL?
    private var fixtureMessages: [CoachMessage] = []
    private var sendTask: Task<Void, Never>?

    var isConfigured: Bool { status?.configured ?? false }

    var modelLabel: String? { label(for: status?.model) }

    func label(for modelId: String?) -> String? {
        guard let modelId else { return nil }
        return status?.models.first { $0.id == modelId }?.label ?? modelId
    }

    // MARK: loading

    /// Screenshot fixtures (see supabase/tests/make-fixtures.ts).
    func loadFixtures(from dir: URL) {
        fixtureDir = dir
        func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(name)) else { return nil }
            return try? JSONDecoder().decode(T.self, from: data)
        }
        status = load(CoachStatus.self, "coach-status.json")
        threads = load(CoachThreadsResponse.self, "coach-threads.json")?.threads ?? []
        brief = load(CoachBriefResponse.self, "coach-brief.json")?.brief
        fixtureMessages = load(CoachThreadResponse.self, "coach-thread.json")?.messages ?? []
    }

    func refresh() async {
        guard fixtureDir == nil, let api = apiProvider() else { return }
        do {
            status = try await api.fetch(CoachStatus.self, "coach_status").0
            threads = try await api.fetch(CoachThreadsResponse.self, "coach_threads").0.threads
            brief = try await api.fetch(CoachBriefResponse.self, "coach_brief").0.brief
        } catch {
            handle(error)
        }
    }

    private func refreshStatusAndThreads() async {
        guard fixtureDir == nil, let api = apiProvider() else { return }
        if let s = try? await api.fetch(CoachStatus.self, "coach_status").0 { status = s }
        if let t = try? await api.fetch(CoachThreadsResponse.self, "coach_threads").0 { threads = t.threads }
    }

    func reset() {
        newChat()
        status = nil
        threads = []
        brief = nil
        briefStreaming = ""
        briefError = nil
    }

    // MARK: conversations

    func newChat() {
        sendTask?.cancel()
        sendTask = nil
        threadId = nil
        messages = []
        streamingText = ""
        toolStatus = nil
        isSending = false
        failedQuestion = nil
        error = nil
    }

    func open(_ thread: CoachThread) async {
        newChat()
        threadId = thread.id
        if fixtureDir != nil {
            messages = fixtureMessages
            return
        }
        guard let api = apiProvider() else { return }
        do {
            messages = try await api.fetch(CoachThreadResponse.self, "coach_thread", query: ["id": thread.id]).0.messages
        } catch {
            handle(error)
        }
    }

    func delete(_ thread: CoachThread) async {
        threads.removeAll { $0.id == thread.id }
        if threadId == thread.id { newChat() }
        guard fixtureDir == nil, let api = apiProvider() else { return }
        do {
            _ = try await api.post("coach_delete", query: ["id": thread.id])
        } catch {
            handle(error)
        }
    }

    func send(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isSending else { return }
        error = nil
        failedQuestion = nil
        messages.append(CoachMessage(id: "local-\(UUID().uuidString)", role: "user", content: question, createdAt: nil))
        streamingText = ""
        toolStatus = nil
        isSending = true
        let thread = threadId
        sendTask = Task { await stream(question, thread: thread) }
    }

    func retry() {
        guard let question = failedQuestion else { return }
        if let i = messages.lastIndex(where: { $0.isUser && $0.content == question }) {
            messages.removeSubrange(i...)
        }
        failedQuestion = nil
        send(question)
    }

    private func stream(_ question: String, thread: String?) async {
        defer {
            isSending = false
            toolStatus = nil
        }
        guard fixtureDir == nil, let api = apiProvider() else { return }
        var body = ["message": question]
        if let thread { body["thread_id"] = thread }
        do {
            let data = try JSONEncoder().encode(body)
            for try await event in api.events("coach", body: data) {
                switch event.type {
                case "status":
                    toolStatus = event.text
                case "text":
                    streamingText += event.text ?? ""
                    toolStatus = nil
                case "done":
                    let reply = streamingText.trimmingCharacters(in: .whitespacesAndNewlines)
                    messages.append(CoachMessage(id: event.messageId ?? UUID().uuidString, role: "assistant", content: reply, createdAt: nil))
                    streamingText = ""
                    if let id = event.threadId { threadId = id }
                    await refreshStatusAndThreads()
                case "error":
                    throw CoachFailure(message: event.message ?? "The coach couldn't answer.")
                default:
                    break
                }
            }
        } catch is CancellationError {
            streamingText = ""
        } catch {
            // Keep whatever arrived; the question can be sent again (nothing was saved).
            if !streamingText.isEmpty {
                messages.append(CoachMessage(id: UUID().uuidString, role: "assistant", content: streamingText + "\n\n_(interrupted)_", createdAt: nil))
                streamingText = ""
            }
            failedQuestion = question
            handle(error)
        }
    }

    // MARK: briefing

    var hasTodaysBrief: Bool { brief != nil }

    func generateBrief() {
        guard !isBriefing, fixtureDir == nil, let api = apiProvider() else { return }
        isBriefing = true
        briefStreaming = ""
        briefError = nil
        Task {
            defer { isBriefing = false }
            do {
                for try await event in api.events("coach", body: Data(#"{"kind":"brief"}"#.utf8)) {
                    switch event.type {
                    case "text":
                        briefStreaming += event.text ?? ""
                    case "done":
                        if let b = event.brief { brief = b }
                        briefStreaming = ""
                        await refreshStatusAndThreads()
                    case "error":
                        throw CoachFailure(message: event.message ?? "The briefing couldn't be written.")
                    default:
                        break
                    }
                }
            } catch is CancellationError {
                briefStreaming = ""
            } catch {
                briefStreaming = ""
                if case APIError.unauthorized = error { onUnauthorized() }
                briefError = error.localizedDescription
            }
        }
    }

    // MARK: settings

    func setModel(_ id: String) async {
        guard fixtureDir == nil, let api = apiProvider(), id != status?.model else { return }
        do {
            let data = try JSONEncoder().encode(["coach_model": id])
            _ = try await api.post("settings", body: data)
            await refreshStatusAndThreads()
        } catch {
            handle(error)
        }
    }

    private func handle(_ error: Error) {
        if case APIError.unauthorized = error {
            onUnauthorized()
        } else {
            self.error = error.localizedDescription
        }
    }
}
