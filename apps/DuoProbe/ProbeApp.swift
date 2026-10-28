import SwiftUI

@main
struct DuoProbeApp: App {
    @StateObject private var log = ProbeLog()
    @StateObject private var monitor = SystemMonitor()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(log)
                .onAppear {
                    monitor.start(log: log)
                }
        }
    }
}

struct TestItem: Identifiable {
    let id: String
    let title: String
    let blurb: String
}

enum TestCatalogue {
    static let all: [TestItem] = [
        TestItem(id: "P1", title: "Device info", blurb: "Just tap Run"),
        TestItem(id: "P2", title: "Cameras", blurb: "Posture A: which camera shows the room?"),
        TestItem(id: "P3", title: "Inner camera", blurb: "Posture A: rate the picture"),
        TestItem(id: "P4", title: "Outer screen", blurb: "Posture A: what does the small screen show?"),
        TestItem(id: "P4b", title: "Outer screen preview", blurb: "Only in the Mac-built version"),
        TestItem(id: "P5", title: "Hinge", blurb: "1 slow close, 5 normal closes"),
        TestItem(id: "P6", title: "Darkness", blurb: "5 normal closes"),
        TestItem(id: "P7", title: "AR tracking", blurb: "Walk slowly to the wall and back"),
        TestItem(id: "P8", title: "Two cameras", blurb: "Just tap Start"),
        TestItem(id: "P9", title: "Clips", blurb: "Record 3 short clips"),
        TestItem(id: "P10", title: "Close signals", blurb: "3 normal closes, then 2 questions"),
        TestItem(id: "P11", title: "Motion sensors", blurb: "Swing one half, then the other"),
        TestItem(id: "P12", title: "Posture B", blurb: "Opened wide, inner screen facing you")
    ]
}

struct RootView: View {
    @EnvironmentObject var log: ProbeLog
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Do the tests in order, top to bottom. Each one explains what to do. Close the phone at normal speed only. Never slam it.")
                        .font(.callout)
                }
                Section("Tests") {
                    ForEach(TestCatalogue.all) { item in
                        NavigationLink {
                            destination(for: item.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("\(item.id)  \(item.title)").font(.headline)
                                    Text(item.blurb).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(log.results[item.id] ?? "")
                                    .font(.caption.bold())
                            }
                        }
                    }
                }
                Section("When you've finished") {
                    ShareLogButton(log: log)
                    NavigationLink("Show the whole log") {
                        LogView(log: log)
                    }
                }
            }
            .navigationTitle("DuoProbe")
        }
        .task(id: scenePhase) { @MainActor in
            log.system("scenePhase = \(String(describing: scenePhase))")
        }
    }

    @ViewBuilder
    private func destination(for id: String) -> some View {
        switch id {
        case "P1": P1View(log: log)
        case "P2": P2View(log: log)
        case "P3": P3View(log: log)
        case "P4": P4View(log: log)
        case "P4b": P4bView(log: log)
        case "P5": P5View(log: log)
        case "P6": P6View(log: log)
        case "P7": P7View(log: log)
        case "P8": P8View(log: log)
        case "P9": P9View(log: log)
        case "P10": P10View(log: log)
        case "P11": P11View(log: log)
        case "P12": P12View(log: log)
        default: Text("Unknown test")
        }
    }
}
