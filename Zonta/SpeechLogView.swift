import SwiftUI

/// The contents of the floating speech panel. Every answer is one selectable
/// card, newest first; a typed follow-up can be sent from the composer.
struct SpeechLogView: View {
    @ObservedObject var model: AppModel
    @State private var draft = ""

    var body: some View {
        content
            .glassSurface()
            .tint(Theme.accent)
    }

    private var content: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            messages
            Divider().opacity(0.4)
            composer
        }
        .padding(4)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.wave.2.fill")
                .foregroundStyle(Theme.accent)
            Text("\(model.speechLog.count)")
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.muted)
            if !model.speechEnabled {
                Text("off")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Theme.accentSoft))
            }
            Spacer()
            Button {
                model.clearSpeechLog()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.borderless)
            .help("Clear all answers")
            .disabled(model.speechLog.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    // MARK: - Messages

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if model.speechLog.isEmpty {
                    Text("No answers yet")
                        .font(.callout)
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(model.speechLog) { entry in
                            answerCard(entry)
                                .id(entry.id)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // One selection span across every card, so ⌘C can copy a
                    // single answer or a range of them.
                    .textSelection(.enabled)
                }
            }
            .onAppear { scrollToLatest(proxy, animated: false) }
            .onChange(of: model.speechLog.count) { _, _ in
                scrollToLatest(proxy, animated: true)
            }
        }
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let latest = model.speechLog.first else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(latest.id, anchor: .top)
            }
        } else {
            proxy.scrollTo(latest.id, anchor: .top)
        }
    }

    @ViewBuilder
    private func answerCard(_ entry: SpeechEntry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let question = entry.question, !question.isEmpty {
                    Image(systemName: "arrow.up.message")
                        .font(.caption2)
                        .foregroundStyle(Theme.accent)
                    Text(question)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer(minLength: 0)
                }
                Text(entry.date, format: .dateTime.hour().minute())
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
            }
            Text(entry.text)
                .font(.body)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.surfaceStrong)
        )
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Follow-up message…", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit(send)
            Button(action: send) {
                Label("Send", systemImage: "arrow.up.circle.fill")
            }
            .buttonStyle(AccentButtonStyle())
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        model.sendTextFollowUp(text)
        draft = ""
    }
}
