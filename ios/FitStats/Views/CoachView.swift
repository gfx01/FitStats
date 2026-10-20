import PhotosUI
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
    @State private var choosingCoach = false
    /// Screenshots to send with the next message.
    @State private var attachments: [CoachImageUpload] = []
    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var loadingImages = false

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
                ToolbarItem(placement: .principal) {
                    Button { choosingCoach = true } label: {
                        HStack(spacing: 6) {
                            CoachCharacter(persona: coach.persona, size: 24, thinking: coach.isSending)
                            Text(coach.persona.name).font(.headline).foregroundStyle(.white)
                            Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(Theme.tertiary)
                        }
                    }
                    .accessibilityLabel("Coach: \(coach.persona.name). Switch coach")
                    .accessibilityIdentifier("coach-switch-bar")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { coach.newChat() } label: { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel("New conversation")
                        .disabled(coach.messages.isEmpty && !coach.isSending)
                }
            }
            .sheet(isPresented: $showHistory) { CoachHistoryView() }
            .sheet(isPresented: $choosingCoach) { CoachPickerView() }
            .onChange(of: pickedItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await loadPicked(items) }
            }
            .task { await coach.refresh() }
            .onAppear(perform: takeDraft)
            .onChange(of: model.coachDraft) { _, _ in takeDraft() }
        }
    }

    /// A question from an "Ask coach" button elsewhere in the app: put in the message field with
    /// the keyboard up, to finish or send as it is.
    private func takeDraft() {
        guard let draft = model.coachDraft else { return }
        model.coachDraft = nil
        input = draft
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            inputFocused = true
        }
    }

    // MARK: home

    @ViewBuilder private var home: some View {
        VStack(spacing: 6) {
            // Not a button: a tap here only hides the keyboard (see the Coach UI test).
            CoachCharacter(persona: coach.persona, size: 92)
                .padding(.bottom, 2)
            Text(coach.persona.name).font(.title2.bold())
            Text(coach.persona.tagline.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(coach.persona.color)
            Text(coach.persona.summary)
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button { choosingCoach = true } label: {
                Label("Switch coach", systemImage: "arrow.left.arrow.right")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(coach.persona.color.opacity(0.16)))
                    .foregroundStyle(coach.persona.color)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .accessibilityIdentifier("coach-switch")
        }
        .padding(.top, 8)
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
                                Image(systemName: s.icon).font(.subheadline).foregroundStyle(coach.persona.color)
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
        Text("The coach uses Claude by Anthropic: your question, any screenshots you attach and a summary of your FitStats data are sent to Anthropic's API to answer it. Only small previews of screenshots are kept. It's an AI coach, not medical advice.")
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
            MessageRow(message: message, current: coach.persona)
        }
        if coach.isSending {
            if coach.streamingText.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    CoachCharacter(persona: coach.persona, size: 32, thinking: true)
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
                MessageRow(message: CoachMessage(id: "streaming", role: "assistant", content: coach.streamingText, createdAt: nil, persona: coach.persona.rawValue),
                           current: coach.persona, streaming: true)
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

    private var canSend: Bool {
        coach.isConfigured && !coach.isSending && !loadingImages
            && (!input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty)
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if !attachments.isEmpty || loadingImages {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(attachments) { a in
                            Image(uiImage: a.preview)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 54, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(alignment: .topTrailing) {
                                    Button { attachments.removeAll { $0.id == a.id } } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 18))
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, Color.black.opacity(0.7))
                                    }
                                    .offset(x: 6, y: -6)
                                    .accessibilityLabel("Remove screenshot")
                                }
                        }
                        if loadingImages { ProgressView().frame(width: 54, height: 72) }
                    }
                    .padding(.top, 6)
                    .padding(.horizontal, 2)
                }
                .accessibilityIdentifier("coach-attachment-strip")
            }
            HStack(alignment: .bottom, spacing: 8) {
                PhotosPicker(selection: $pickedItems, maxSelectionCount: max(1, 3 - attachments.count), matching: .images) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(attachments.count < 3 && coach.isConfigured ? coach.persona.color : Color.white.opacity(0.2))
                        .frame(width: 34, height: 40)
                }
                .disabled(!coach.isConfigured || coach.isSending || attachments.count >= 3)
                .accessibilityLabel("Attach screenshots")
                .accessibilityIdentifier("coach-attach")
                TextField(coach.isConfigured ? "Ask \(coach.persona.name)…" : "Coach isn't set up yet", text: $input, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.08)))
                    .disabled(!coach.isConfigured)
                    .accessibilityIdentifier("coach-input")
                Button {
                    coach.send(input, images: attachments)
                    input = ""
                    attachments = []
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(canSend ? coach.persona.color : Color.white.opacity(0.2))
                }
                .disabled(!canSend)
                .accessibilityLabel("Send")
                .accessibilityIdentifier("coach-send")
            }
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

    /// Picked photos, scaled down for sending (at most three).
    private func loadPicked(_ items: [PhotosPickerItem]) async {
        loadingImages = true
        defer {
            loadingImages = false
            pickedItems = []
        }
        for item in items where attachments.count < 3 {
            if let data = try? await item.loadTransferable(type: Data.self), let upload = CoachImageUpload(imageData: data) {
                attachments.append(upload)
            }
        }
    }
}

// MARK: - Pieces

private struct MessageRow: View {
    let message: CoachMessage
    /// The coach chosen now, for replies that don't say who wrote them.
    let current: CoachPersona
    var streaming = false

    var body: some View {
        if message.isUser {
            VStack(alignment: .trailing, spacing: 6) {
                if let attachments = message.attachments, !attachments.isEmpty {
                    AttachmentThumbs(attachments: attachments)
                }
                if !message.content.isEmpty {
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
            }
            .padding(.leading, 48)
            .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            let persona = message.coach ?? current
            HStack(alignment: .top, spacing: 10) {
                // Only the reply being written moves; the rest stay still.
                CoachCharacter(persona: persona, size: 32, thinking: false, animated: streaming)
                CoachMarkdown(text: message.content)
                    .font(.subheadline)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(persona.color.opacity(0.22), lineWidth: 1))
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
