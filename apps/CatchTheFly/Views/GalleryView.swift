import SwiftUI

/// The splat gallery: the last 30 flies caught, each drawn from its own seed, with its time.
struct GalleryView: View {
    @ObservedObject var gallery: SplatGallery
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClear = false

    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if gallery.records.isEmpty {
                    VStack(spacing: 12) {
                        SplatTile(seed: 1)
                            .frame(width: 120, height: 120)
                            .opacity(0.35)
                            .accessibilityHidden(true)
                        Text("No splats yet")
                            .font(.title2.bold())
                        Text("Every fly you catch lands here. Off you go!")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.secondary)
                    }
                    .padding(.top, 60)
                    .padding(.horizontal, 24)
                } else {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(gallery.records) { record in
                            GalleryCell(record: record)
                        }
                    }
                    .padding(16)
                    Button(role: .destructive) {
                        confirmClear = true
                    } label: {
                        Label("Clear the gallery", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Splat gallery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Clear the gallery?", isPresented: $confirmClear) {
                Button("Clear", role: .destructive) {
                    gallery.clear()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your best time stays as it is.")
            }
        }
    }
}

struct GalleryCell: View {
    let record: SplatRecord

    var body: some View {
        VStack(spacing: 4) {
            SplatTile(seed: record.seed)
                .aspectRatio(1, contentMode: .fit)
            Text(GameText.clock(record.catchTime))
                .font(.headline.monospacedDigit())
            Text("Fly \(record.flyNumber), round \(record.roundNumber)")
                .font(.caption)
                .foregroundStyle(Color.secondary)
            Text(record.date.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fly \(record.flyNumber) of round \(record.roundNumber), caught in \(GameText.clock(record.catchTime)), \(record.date.formatted(date: .abbreviated, time: .shortened))")
    }
}

/// One splat on a pale round "wall" tile.
struct SplatTile: View {
    let seed: Int

    var body: some View {
        Canvas { ctx, size in
            let w = Double(size.width)
            let h = Double(size.height)
            let wall = CGRect(x: 2, y: 2, width: w - 4, height: h - 4)
            ctx.fill(Path(roundedRect: wall, cornerRadius: 18), with: .color(Color(red: 0.95, green: 0.93, blue: 0.86)))
            ctx.stroke(Path(roundedRect: wall, cornerRadius: 18), with: .color(Color.black.opacity(0.15)), lineWidth: 1)
            FlyArtist.drawSplat(&ctx, at: CGPoint(x: w / 2, y: h / 2), radius: min(w, h) * 0.24,
                                seed: max(1, seed), alpha: 1, showWord: false)
        }
    }
}
