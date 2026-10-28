import SwiftUI

/// The frame every test screen uses: title, numbered instructions, the test's own
/// controls, the latest result and the test's most recent log lines.
struct TestPage<Content: View>: View {
    let id: String
    let title: String
    let steps: [String]
    @ObservedObject var log: ProbeLog
    let content: Content

    init(id: String, title: String, steps: [String], log: ProbeLog, @ViewBuilder content: () -> Content) {
        self.id = id
        self.title = title
        self.steps = steps
        self._log = ObservedObject(wrappedValue: log)
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(.title2.bold())
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { pair in
                        Text("\(pair.offset + 1). \(pair.element)")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.yellow.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                content
                if let r = log.results[id] {
                    Text("Latest result: \(r)")
                        .font(.footnote.bold())
                }
                RecentLines(log: log, tag: id)
                ShareLogButton(log: log)
            }
            .padding()
        }
        .navigationTitle(id)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Buttons for a tester's answer. The chosen one gets a tick, and every tap is logged.
struct AnswerButtons: View {
    let testID: String
    let question: String
    let options: [String]
    let log: ProbeLog
    var onAnswer: ((String) -> Void)? = nil
    @State var chosen: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(question)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(options, id: \.self) { option in
                Button {
                    chosen = option
                    log.answer(testID, question, option)
                    onAnswer?(option)
                } label: {
                    HStack {
                        Image(systemName: chosen == option ? "checkmark.circle.fill" : "circle")
                        Text(option)
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ReadoutBox: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.callout, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color.gray.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct BigButton: View {
    let title: String
    let enabled: Bool
    let action: () -> Void

    init(_ title: String, enabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.enabled = enabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!enabled)
    }
}

struct RecentLines: View {
    @ObservedObject var log: ProbeLog
    let tag: String

    var body: some View {
        let mine = log.lines.filter { $0.contains("] \(tag) ") }.suffix(8)
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(mine.enumerated()), id: \.offset) { pair in
                Text(pair.element)
                    .font(.system(.caption2, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct ShareLogButton: View {
    @ObservedObject var log: ProbeLog

    var body: some View {
        ShareLink(items: log.shareItems) {
            Label("Share log (\(log.shareItems.count) file\(log.shareItems.count == 1 ? "" : "s"))",
                  systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
    }
}

struct LogView: View {
    @ObservedObject var log: ProbeLog

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ShareLogButton(log: log)
                ForEach(Array(log.lines.suffix(600).enumerated()), id: \.offset) { pair in
                    Text(pair.element)
                        .font(.system(.caption2, design: .monospaced))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding()
        }
        .navigationTitle("Log")
        .navigationBarTitleDisplayMode(.inline)
    }
}
