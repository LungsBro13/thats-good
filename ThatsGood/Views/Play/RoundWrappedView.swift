import SwiftUI
import SwiftData

extension WrappedContext {
    /// Everything Round Wrapped compares against: earlier rounds and the handicap before and after.
    static func make(_ round: Round, allRounds: [Round], imported: [ImportedScore]) -> WrappedContext {
        let previous = allRounds
            .filter { $0.isComplete && $0.persistentModelID != round.persistentModelID && $0.playedOn <= round.playedOn }
            .sorted { $0.playedOn > $1.playedOn }
            .map(\.data)
        let importedData = imported.map(\.data).filter { $0.date <= round.playedOn }
        let before = Handicap.currentIndex(previous, imported: importedData)
        let after = Handicap.currentIndex(previous + [round.data], imported: importedData)
        return WrappedContext(round: round.data, courseName: round.courseName, previous: previous,
                              handicapBefore: before, handicapAfter: after)
    }
}

/// Bold colours for the slides. Each has a background, a shape colour and a text colour with strong contrast.
/// Slide colours from a golf course: fairway, green, fringe, rough and bunker sand.
struct WrappedPalette {
    let background: Color
    let stripe: Color      // mowing stripes
    let bunker: Color      // the sand shape behind the golfer
    let ink: Color
    let golfer: Golfer.Style

    static let fairway = WrappedPalette(background: .tgFairway, stripe: .tgFairwayStripe, bunker: .tgSand,
                                        ink: .tgRough, golfer: .onGreen)
    static let green = WrappedPalette(background: .tgGreen, stripe: .tgGreenStripe, bunker: .tgSand,
                                      ink: .tgRough, golfer: .dark)
    static let sand = WrappedPalette(background: .tgSand, stripe: Color(hex: 0xE2CD97), bunker: .tgFringe,
                                     ink: Color(hex: 0x3D2D12), golfer: .dark)
    static let rough = WrappedPalette(background: .tgRoughText, stripe: Color(hex: 0x24553B), bunker: .tgSand.opacity(0.9),
                                      ink: Color(hex: 0xF3F6F2), golfer: .light)
    static let fringe = WrappedPalette(background: .tgFringe, stripe: Color(hex: 0xBEDFA3), bunker: .tgSandLight,
                                       ink: .tgRough, golfer: .dark)
    static let all: [WrappedPalette] = [fairway, sand, green, rough, fringe]
    static let outro = WrappedPalette(background: .tgRough, stripe: .tgRoughStripe, bunker: .tgSand.opacity(0.25),
                                      ink: Color(hex: 0xF3F6F2), golfer: .light)

    static func forSlide(_ index: Int, kind: WrappedSlide.Kind) -> WrappedPalette {
        kind == .outro ? outro : all[index % all.count]
    }
}

/// Round Wrapped: a quick, tap-through story of the round.
struct RoundWrappedView: View {
    let round: Round
    var startAt = 0
    let onFinish: () -> Void

    @Query(filter: #Predicate<Round> { $0.isComplete }) private var allRounds: [Round]
    @Query private var imported: [ImportedScore]

    @State private var slides: [WrappedSlide] = []
    @State private var context: WrappedContext?
    @State private var index = 0
    @State private var progress = 0.0
    @State private var paused = false
    @State private var pressStart: Date?
    @State private var shareImage: UIImage?

    private let slideSeconds = 5.0

    var body: some View {
        GeometryReader { geo in
            let slide = slides.indices.contains(index) ? slides[index] : nil
            let palette = slide.map { WrappedPalette.forSlide(index, kind: $0.kind) } ?? WrappedPalette.outro

            ZStack {
                if let slide {
                    WrappedSlideView(slide: slide, ink: palette.ink)
                        .id(slide.id)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                removal: .opacity))
                        .padding(.horizontal, 28)
                }

                VStack(spacing: 14) {
                    progressBars(ink: palette.ink)
                    HStack {
                        Text("ROUND WRAPPED").font(.brandTitle(20, bold: true)).fontDesign(nil).tracking(2.5)
                        Spacer()
                        Button(action: onFinish) {
                            Image(systemName: "xmark").font(.headline).frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Close")
                    }
                    .foregroundStyle(palette.ink)
                    Spacer()
                    if slide?.kind == .outro {
                        outroButtons(palette: palette)
                    } else {
                        Text("Tap for next · hold to pause")
                            .font(.caption)
                            .foregroundStyle(palette.ink.opacity(0.6))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .background {
                WrappedBackground(palette: palette)
                    .animation(.easeInOut(duration: 0.5), value: index)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if pressStart == nil { pressStart = .now; paused = true }
                    }
                    .onEnded { value in
                        let held = Date.now.timeIntervalSince(pressStart ?? .now)
                        pressStart = nil
                        paused = false
                        guard held < 0.3 else { return }
                        if value.location.x < geo.size.width / 3 { go(-1) } else { go(1) }
                    }
            )
        }
        .statusBarHidden()
        .onAppear(perform: build)
        .task(id: "\(index)-\(slides.count)") { await tick() }
    }

    // MARK: Pieces

    private func progressBars(ink: Color) -> some View {
        HStack(spacing: 4) {
            ForEach(slides.indices, id: \.self) { i in
                GeometryReader { bar in
                    Capsule().fill(ink.opacity(0.25))
                        .overlay(alignment: .leading) {
                            Capsule().fill(ink)
                                .frame(width: bar.size.width * (i < index ? 1 : (i == index ? progress : 0)))
                        }
                }
                .frame(height: 3)
            }
        }
        .padding(.top, 8)
        .accessibilityHidden(true)
    }

    private func outroButtons(palette: WrappedPalette) -> some View {
        VStack(spacing: 10) {
            if let shareImage {
                ShareLink(item: Image(uiImage: shareImage),
                          preview: SharePreview("My round on That's Good", image: Image(uiImage: shareImage))) {
                    Label("Share to your story", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(.white)
                        .background(Color.tgFairway, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            Button(action: onFinish) {
                Text("See the full breakdown")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(palette.ink)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.ink.opacity(0.5), lineWidth: 1.5))
            }
        }
        .padding(.bottom, 12)
    }

    // MARK: Behaviour

    private func build() {
        guard slides.isEmpty else { return }
        let ctx = WrappedContext.make(round, allRounds: allRounds, imported: imported)
        context = ctx
        slides = RoundWrapped.slides(ctx)
        var start = startAt
        #if DEBUG
        // CI screenshots: -wrappedSlide N opens slide N and holds still.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-wrappedSlide"), i + 1 < args.count, let n = Int(args[i + 1]) {
            start = n
            paused = true
        }
        #endif
        index = min(max(0, start), max(0, slides.count - 1))
        renderShareCard(ctx)
    }

    private func go(_ step: Int) {
        let next = index + step
        guard slides.indices.contains(next) else { return }
        withAnimation(.easeInOut(duration: 0.35)) { index = next }
    }

    /// Fills the progress bar, then moves on. The last slide waits for the player.
    private func tick() async {
        progress = 0
        guard slides.indices.contains(index), slides[index].kind != .outro else {
            progress = 1
            return
        }
        let step = 0.05
        while progress < 1 && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(step * 1_000_000_000))
            if !paused { progress = min(1, progress + step / slideSeconds) }
        }
        if !Task.isCancelled { go(1) }
    }

    @MainActor
    private func renderShareCard(_ ctx: WrappedContext) {
        let renderer = ImageRenderer(content: WrappedShareCard(context: ctx, slides: slides))
        renderer.scale = 3  // 360×640 points → 1080×1920 pixels, the size of a story
        shareImage = renderer.uiImage
    }
}

/// The big number, caption and detail for one slide, animated in.
struct WrappedSlideView: View {
    let slide: WrappedSlide
    let ink: Color

    @State private var shown = 0
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(slide.eyebrow)
                .font(.system(size: 15, weight: .heavy))
                .tracking(3)
                .opacity(appeared ? 0.8 : 0)
                .offset(y: appeared ? 0 : 12)
            Group {
                if let target = slide.countTo {
                    Text("\(shown)")
                        .contentTransition(.numericText(value: Double(shown)))
                        .onAppear {
                            shown = max(0, target - min(target, 40))
                            withAnimation(.easeOut(duration: 1.1).delay(0.15)) { shown = target }
                        }
                } else {
                    Text(slide.big)
                }
            }
            .font(.system(size: slide.big.count > 6 ? 72 : 120, weight: .black))
            .minimumScaleFactor(0.4)
            .lineLimit(1)
            .monospacedDigit()
            .scaleEffect(appeared ? 1 : 0.6, anchor: .leading)
            .opacity(appeared ? 1 : 0)
            Text(slide.caption)
                .font(.system(size: 30, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 20)
            if let detail = slide.detail {
                Text(detail)
                    .font(.system(size: 19, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(appeared ? 0.85 : 0)
                    .offset(y: appeared ? 0 : 20)
            }
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.7).delay(0.05)) { appeared = true }
        }
    }
}

/// A bold background with soft shapes drifting about.
struct WrappedBackground: View {
    let palette: WrappedPalette
    @State private var drift = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            MowingStripes(base: palette.background, stripe: palette.stripe, width: 48)
            // A bunker, drifting gently, with the golfer standing beside it.
            Ellipse()
                .fill(palette.bunker)
                .frame(width: 240, height: 120)
                .rotationEffect(.degrees(drift ? -8 : -3))
                .offset(x: 50, y: drift ? -118 : -110)
            Golfer(style: palette.golfer, height: 150)
                .padding(.trailing, 40)
                .padding(.bottom, 150)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}

/// A story-sized picture of the round to share (rendered at 1080×1920).
struct WrappedShareCard: View {
    let context: WrappedContext
    let slides: [WrappedSlide]

    var body: some View {
        let round = context.round
        let keep: [WrappedSlide.Kind] = [.streak, .shotOfTheDay, .birdies, .greens, .putting, .nines, .handicap]
        let highlights = slides.filter { keep.contains($0.kind) }.prefix(4)

        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Golfer(style: .dark, height: 26)
                Wordmark(size: 15)
            }
            Spacer()
            Text(context.courseName.uppercased()).font(.system(size: 14, weight: .heavy)).tracking(2).opacity(0.75)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(round.strokes)").font(.system(size: 120, weight: .black))
                Text(MatchEngine.toParText(round.toPar)).font(.system(size: 34, weight: .heavy))
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(highlights)) { s in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(s.big).font(.system(size: 26, weight: .black)).frame(minWidth: 70, alignment: .leading)
                        Text(s.caption).font(.system(size: 17, weight: .semibold)).lineLimit(2)
                    }
                }
            }
            Spacer()
            Text(round.date.formatted(date: .long, time: .omitted)).font(.system(size: 13, weight: .semibold)).opacity(0.7)
        }
        .foregroundStyle(Color.tgRough)
        .padding(32)
        .frame(width: 360, height: 640, alignment: .leading)
        .background {
            ZStack(alignment: .topTrailing) {
                MowingStripes(base: .tgFairway, stripe: .tgFairwayStripe, width: 40)
                Ellipse().fill(Color.tgSand).frame(width: 200, height: 100).rotationEffect(.degrees(-6)).offset(x: 60, y: 70)
            }
        }
        .clipped()
    }
}
