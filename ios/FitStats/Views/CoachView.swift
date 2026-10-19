import SwiftUI
import UIKit

private struct Suggestion: Identifiable {
    let icon: String
    let text: String
    var id: String { text }
}

struct CoachView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var coach: CoachStore
    @State var input = ""
    @State var showHistory = false
    @FocusState var inputFocused: Bool
    /// The text field and send button on screen: tapping anywhere else hides the keyboard.
    @State private var composerFrame: CGRect = .zero

    private let bottomID = "coach-bottom"

    private static let suggestions = [
        Suggestion(icon: "bolt.heart.fill", text: "How recovered am I today, and why?"),
        Suggestion(icon: "moon.stars.fill", text: "How has my sleep been this week?"),
        Suggestion(icon: "figure.run", text: "Plan my training for the next few days"),
        Suggestion(icon: "waveform.path", text: "What's been affecting my HRV lately?"),
        Suggestion(icon: "bed.double.fill", text: "When should I go to bed tonight?"),
        Suggestion(icon: "chart.line.uptrend.xyaxis", text: "Compare this month with last month"),
    ]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 14) {
                        if coach.messages.isEmpty && !coach.isSending {
                            home
                        } else {
                            conversation
                        }
                        Color.clear.frame(height: 1).id(bottomID)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 12)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: coach.streamingText) { _, _ in proxy.scrollTo(bottomID, anchor: .bottom) }
                .onChange(of: coach.messages.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(bottomID, anchor: .bottom) }
                }
            }
            .safeAreaInset(edge: .bottom) { composer }
            .onTapOutside(of: composerFrame, active: inputFocused) { inputFocused = false }
            .screenBackground()
            .navigationTitle("Coach")
            .swipeBackFromAnywhere()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showHistory = true } label: { Image(systemName: "clock.arrow.circlepath") }
                        .accessibilityLabel("Conversations")
                        .accessibilityIdentifier("coach-history")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { coach.newChat() } label: { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel("New conversation")
                        .disabled(coach.messages.isEmpty && !coach.isSending)
                }
            }
            .sheet(isPresented: $showHistory) { CoachHistoryView() }
            .task { await coach.refresh() }
        }
    }

    // MARK: home

    @ViewBuilder private var home: some View {
        VStack(spacing: 8) {
            CoachAvatar(size: 54)
            Text("Your coach").font(.title3.bold())
            Text("Ask about your recovery, sleep, training or trends. Every answer is based on your own data.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 12)
        .padding(.bottom, 4)

        if let status = coach.status, !status.configured {
            setupCard
        } else {
            BriefingCard()
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Ask")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(Self.suggestions) { s in
                        Button { coach.send(s.text) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Image(systemName: s.icon).font(.subheadline).foregroundStyle(Theme.sleep)
                                Text(s.text)
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Spacer(minLength: 0)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.cardBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(!coach.isConfigured)
                        .accessibilityIdentifier("coach-suggestion")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        if let error = coach.error {
            Banner(icon: "exclamationmark.triangle.fill", text: error, color: Theme.recoveryYellow, actionTitle: "OK") { coach.error = nil }
        }
        Text("The coach uses Claude by Anthropic: your question and a summary of your FitStats data are sent to Anthropic's API to answer it. It's an AI coach, not medical advice.")
            .font(.caption2)
            .foregroundStyle(Theme.tertiary)
            .multilineTextAlignment(.center)
            .padding(.top, 4)
    }

    private var setupCard: some View {
        Card {
            SectionHeader(title: "Set up the coach")
            Text("The coach needs a Claude API key on your server. Create one in the Anthropic Console, then add it in Supabase → Edge Functions → Secrets as ANTHROPIC_API_KEY. Step-by-step instructions are in SETUP.md.")
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
            Button("Check again") { Task { await coach.refresh() } }
                .font(.footnote.weight(.semibold))
        }
    }

    // MARK: conversation

    @ViewBuilder private var conversation: some View {
        ForEach(coach.messages) { message in
            MessageRow(message: message)
        }
        if coach.isSending {
            if coach.streamingText.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    CoachAvatar(size: 28)
                    HStack(spacing: 8) {
                        TypingDots()
                        Text(coach.toolStatus ?? "Thinking…")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondary)
                            .animation(.default, value: coach.toolStatus)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
                    Spacer(minLength: 24)
                }
            } else {
                MessageRow(message: CoachMessage(id: "streaming", role: "assistant", content: coach.streamingText, createdAt: nil), streaming: true)
            }
        }
        if let error = coach.error {
            VStack(alignment: .leading, spacing: 8) {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.recoveryYellow)
                if coach.failedQuestion != nil {
                    Button("Try again") { coach.retry() }
                        .font(.footnote.weight(.semibold))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.recoveryYellow.opacity(0.1)))
        }
    }

    private var composer: some View {
        let canSend = coach.isConfigured && !coach.isSending && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(alignment: .bottom, spacing: 10) {
            TextField(coach.isConfigured ? "Ask your coach…" : "Coach isn't set up yet", text: $input, axis: .vertical)
                .lineLimit(1...5)
                .focused($inputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.08)))
                .disabled(!coach.isConfigured)
                .accessibilityIdentifier("coach-input")
            Button {
                coach.send(input)
                input = ""
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(canSend ? Theme.recoveryGreen : Color.white.opacity(0.2))
            }
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(.bar)
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { composerFrame = geo.frame(in: .global) }
                    .onChange(of: geo.frame(in: .global)) { _, frame in composerFrame = frame }
            }
        }
    }
}

// MARK: - Pieces

struct CoachAvatar: View {
    var size: CGFloat

    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                Circle().fill(LinearGradient(colors: [Theme.sleep, Theme.strain], startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .shadow(color: Theme.sleep.opacity(0.35), radius: size * 0.18)
    }
}

private struct MessageRow: View {
    let message: CoachMessage
    var streaming = false

    var body: some View {
        if message.isUser {
            HStack {
                Spacer(minLength: 48)
                Text(message.content)
                    .font(.subheadline)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(LinearGradient(colors: [Theme.strain.opacity(0.55), Theme.strainEnd.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                    .textSelection(.enabled)
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                CoachAvatar(size: 28)
                CoachMarkdown(text: message.content)
                    .font(.subheadline)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
                    .overlay(alignment: .bottomTrailing) {
                        if streaming { TypingDots().padding(8) }
                    }
                    .contextMenu {
                        Button { UIPasteboard.general.string = message.content } label: { Label("Copy", systemImage: "doc.on.doc") }
                    }
            }
        }
    }
}

/// Today's briefing: generated on request, cached by the server for the day.
private struct BriefingCard: View {
    @EnvironmentObject var coach: CoachStore
    @EnvironmentObject var model: AppModel

    var body: some View {
        Card {
            HStack {
                SectionHeader(title: "Today's briefing")
                Spacer()
                if coach.brief != nil && !coach.isBriefing {
                    Button { coach.generateBrief() } label: { Image(systemName: "arrow.clockwise") }
                        .font(.footnote.weight(.semibold))
                        .accessibilityLabel("Write a new briefing")
                }
            }
            if coach.isBriefing {
                if coach.briefStreaming.isEmpty {
                    HStack(spacing: 8) {
                        TypingDots()
                        Text("Reading your night and your trends…").font(.footnote).foregroundStyle(Theme.secondary)
                    }
                } else {
                    CoachMarkdown(text: coach.briefStreaming, linesAsParagraphs: true).font(.subheadline)
                }
            } else if let brief = coach.brief {
                let byModel = coach.label(for: brief.model).map { " · \($0)" } ?? ""
                CoachMarkdown(text: brief.text, linesAsParagraphs: true).font(.subheadline)
                Text("Written \(Format.relative(brief.createdAt))\(byModel)")
                    .font(.caption2)
                    .foregroundStyle(Theme.tertiary)
            } else {
                Text("A short read on your recovery, what to do today and when to sleep tonight.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                Button { coach.generateBrief() } label: {
                    Label("Write today's briefing", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Theme.sleep.opacity(0.22)))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.sleep)
            }
            if let error = coach.briefError {
                Text(error).font(.caption).foregroundStyle(Theme.recoveryYellow)
            }
        }
    }
}

struct TypingDots: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.35)) { context in
            let phase = Int(context.date.timeIntervalSinceReferenceDate / 0.35) % 3
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.white.opacity(i == phase ? 0.85 : 0.28))
                        .frame(width: 6, height: 6)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Renders the small Markdown subset the coach writes: paragraphs, "- " bullets,
/// numbered items, headings, and inline bold/italic/links.
struct CoachMarkdown: View {
    let text: String
    var linesAsParagraphs = false

    private enum Block {
        case paragraph(String)
        case bullet(String)
        case numbered(String, String)
        case heading(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { item in
                switch item.element {
                case .paragraph(let s):
                    Text(Self.inline(s))
                case .heading(let s):
                    Text(Self.inline(s)).fontWeight(.semibold)
                case .bullet(let s):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(Theme.sleep)
                        Text(Self.inline(s))
                    }
                case .numbered(let n, let s):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(n).foregroundStyle(Theme.sleep).monospacedDigit()
                        Text(Self.inline(s))
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var blocks: [Block] {
        var out: [Block] = []
        var paragraph: [String] = []
        func flush() {
            if !paragraph.isEmpty {
                out.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph = []
            }
        }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flush()
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                flush()
                out.append(.bullet(String(line.dropFirst(2))))
            } else if let r = line.range(of: #"^\d{1,2}[.)] "#, options: .regularExpression) {
                flush()
                out.append(.numbered(line[r].trimmingCharacters(in: .whitespaces), String(line[r.upperBound...])))
            } else if line.hasPrefix("#") {
                flush()
                out.append(.heading(line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)))
            } else {
                paragraph.append(line)
                if linesAsParagraphs { flush() }
            }
        }
        flush()
        return out
    }

    static func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

struct CoachHistoryView: View {
    @EnvironmentObject var coach: CoachStore
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                if coach.threads.isEmpty {
                    Text("No conversations yet.").foregroundStyle(Theme.secondary)
                }
                ForEach(coach.threads) { thread in
                    Button {
                        Task {
                            await coach.open(thread)
                            dismiss()
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(thread.title).font(.subheadline.weight(.medium)).foregroundStyle(.white).lineLimit(2)
                            Text(Format.relative(thread.updatedAt)).font(.caption).foregroundStyle(Theme.tertiary)
                        }
                        .padding(.vertical, 2)
                    }
                    .accessibilityIdentifier("coach-thread")
                }
                .onDelete { offsets in
                    let doomed = offsets.map { coach.threads[$0] }
                    Task { for t in doomed { await coach.delete(t) } }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Conversations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}
