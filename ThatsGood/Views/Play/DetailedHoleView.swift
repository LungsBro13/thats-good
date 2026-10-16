import SwiftUI
import SwiftData
import MapKit

/// Detailed mode for one hole: satellite map, yardages, tap to measure, and shot marking.
struct DetailedHoleView: View {
    @Bindable var round: Round
    let holeNumber: Int
    @Bindable var score: HoleScore
    let par: Int

    @Environment(\.modelContext) private var context
    @ObservedObject private var location = LocationManager.shared
    @Query(filter: #Predicate<Club> { $0.inBag }, sort: \Club.sortOrder) private var clubs: [Club]

    @State private var camera: MapCameraPosition = .automatic
    @State private var target: CLLocationCoordinate2D?
    @State private var settingGreen = false
    @State private var club: String?
    @State private var lie: ShotLie = .tee
    @State private var lieTouched = false

    private var geo: CourseGeo? { round.course?.geo }
    private var holeGeo: HoleGeo? { geo?.hole(holeNumber) }
    private var holeShots: [Shot] { round.shots(onHole: holeNumber) }
    private var strokeShots: [Shot] { holeShots.filter { $0.lieValue != .green } }
    private var onGreen: Bool { holeShots.contains { $0.lieValue == .green } }

    /// Where the player is: GPS if we have it, otherwise the tee.
    private var player: GeoPoint? { location.point ?? holeGeo?.tee }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            map
            if location.isDenied {
                Text("Location is off for That's Good. Turn it on in Settings → Privacy & Security → Location Services to see yardages.")
                    .font(.footnote)
                    .foregroundStyle(Color.tgLoss)
            }
            if !onGreen, let player, let green = holeGeo {
                CaddieCard(distance: Geo.yards(player, green.greenCenter), lie: lie)
            }
            shotControls
        }
        .onAppear {
            location.start()
            Club.ensureDefaults(in: context)
            lie = holeShots.isEmpty ? .tee : guessLie()
            camera = initialCamera()
        }
        .onChange(of: holeGeo) {
            // Map data can arrive after the hole opens (download, or the player sets the green).
            camera = initialCamera()
        }
        .onChange(of: location.point) {
            // Keep the lie guess fresh as the player walks, unless they picked one themselves.
            if !lieTouched && !holeShots.isEmpty { lie = guessLie() }
        }
        .onChange(of: strokeCountFingerprint) {
            if !strokeShots.isEmpty {
                score.strokes = max(1, strokeShots.count + score.putts + score.penalties)
            }
        }
    }

    private var strokeCountFingerprint: String {
        "\(strokeShots.count)|\(score.putts)|\(score.penalties)"
    }

    // MARK: Map

    private var map: some View {
        MapReader { proxy in
            Map(position: $camera) {
                UserAnnotation()
                if let outline = holeGeo?.greenOutline, outline.count >= 3 {
                    MapPolygon(coordinates: outline.map(\.coordinate))
                        .foregroundStyle(Color.tgAccent.opacity(0.18))
                        .stroke(Color.tgAccent, lineWidth: 2)
                }
                if let green = holeGeo?.greenCenter {
                    Annotation("Green", coordinate: green.coordinate, anchor: .bottom) {
                        Image(systemName: "flag.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                    }
                    .annotationTitles(.hidden)
                }
                ForEach(holeShots) { shot in
                    Annotation("Shot \(shot.index)", coordinate: shot.point.coordinate) {
                        Circle()
                            .fill(shot.lieValue == .green ? Color.tgAccent : Color.white)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 1))
                    }
                    .annotationTitles(.hidden)
                }
                if let target, let player, let green = holeGeo?.greenCenter {
                    MapPolyline(coordinates: [player.coordinate, target, green.coordinate])
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
                    Annotation("Target", coordinate: target) {
                        targetLabel(toTarget: Geo.yards(player, GeoPoint(target)),
                                    toGreen: Geo.yards(GeoPoint(target), green))
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.imagery)
            .mapControls { MapCompass() }
            .onTapGesture { screenPoint in
                guard let coordinate = proxy.convert(screenPoint, from: .local) else { return }
                if settingGreen {
                    setGreen(at: GeoPoint(coordinate))
                } else {
                    target = coordinate
                }
            }
        }
        .frame(height: 380)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .topTrailing) { yardageBox.padding(10) }
        .overlay(alignment: .bottomLeading) { mapButtons.padding(10) }
        .overlay(alignment: .topLeading) {
            if !onGreen, let player, let green = holeGeo {
                CaddieCard(distance: Geo.yards(player, green.greenCenter), lie: lie, compact: true).padding(10)
            }
        }
    }

    @ViewBuilder
    private var yardageBox: some View {
        if let player, let green = holeGeo {
            let fmb = Geo.frontMiddleBack(from: player, greenCenter: green.greenCenter, outline: green.greenOutline)
            VStack(alignment: .trailing, spacing: 2) {
                if let back = fmb.back { yardageRow("BACK", back) }
                Text("\(Int(fmb.middle.rounded()))")
                    .font(.system(size: 40, weight: .semibold))
                    .monospacedDigit()
                if let front = fmb.front { yardageRow("FRONT", front) }
            }
            .foregroundStyle(.white)
            .padding(10)
            .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(Int(fmb.middle.rounded())) yards to the middle of the green")
        } else {
            Text("No green for this hole yet.\nTap Set green, then tap the middle of the green.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
                .padding(10)
                .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func yardageRow(_ label: String, _ yards: Double) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
            Text("\(Int(yards.rounded()))").font(.subheadline.weight(.semibold)).monospacedDigit()
        }
    }

    private func targetLabel(toTarget: Double, toGreen: Double) -> some View {
        VStack(spacing: 0) {
            Text("\(Int(toTarget.rounded()))").font(.caption.weight(.bold))
            Text("\(Int(toGreen.rounded())) to go").font(.caption2)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 4))
    }

    private var mapButtons: some View {
        HStack(spacing: 8) {
            mapButton(settingGreen ? "Tap the green" : "Set green", icon: "flag", active: settingGreen) {
                settingGreen.toggle()
            }
            if target != nil {
                mapButton("Clear", icon: "xmark", active: false) { target = nil }
            }
            mapButton("Hole view", icon: "scope", active: false) { camera = initialCamera() }
        }
    }

    private func mapButton(_ title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .frame(minHeight: 36)
                .foregroundStyle(active ? Color.black : Color.white)
                .background(active ? Color.tgAccent : Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: Shots

    private var shotControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(onGreen ? "On the green" : "Shot \(strokeShots.count + 1)")
                Spacer()
                if let last = lastShotSummary {
                    Text(last).font(.footnote).foregroundStyle(Color.tgMuted)
                }
            }

            if !onGreen {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(clubs) { item in
                            let on = club == item.name
                            Button { club = on ? nil : item.name } label: {
                                Text(item.name)
                                    .font(.subheadline.weight(.semibold))
                                    .frame(minWidth: 48, minHeight: 44)
                                    .padding(.horizontal, 6)
                                    .foregroundStyle(on ? Color.tgBackground : Color.primary)
                                    .background(on ? Color.primary : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? Color.primary : Color.tgLine))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                }

                SegmentedPicker(options: [ShotLie.tee, .fairway, .rough, .sand, .recovery],
                                selection: Binding(get: { lie }, set: { lie = $0; lieTouched = true })) { $0.label }
            }

            HStack(spacing: 8) {
                if !onGreen {
                    Button("Mark shot") { markShot() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(player == nil)
                    Button("On green") { markOnGreen() }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(player == nil)
                }
                if !holeShots.isEmpty {
                    Button { undo() } label: { Image(systemName: "arrow.uturn.backward") }
                        .buttonStyle(SecondaryButtonStyle())
                        .frame(width: 60)
                        .accessibilityLabel("Undo last shot")
                }
            }

            Text(onGreen
                 ? "Enter putts and first putt length below."
                 : "Stand by your ball, pick the club you're about to hit, then tap Mark shot.")
                .font(.footnote)
                .foregroundStyle(Color.tgMuted)
        }
    }

    private var lastShotSummary: String? {
        let shots = holeShots
        guard shots.count >= 2 else { return nil }
        let previous = shots[shots.count - 2], latest = shots[shots.count - 1]
        let yards = Int(Geo.yards(previous.point, latest.point).rounded())
        return "Last shot \(previous.club ?? "") \(yards) yd"
    }

    private func yardsToGreen(from point: GeoPoint) -> Double? {
        holeGeo.map { Geo.yards(point, $0.greenCenter) }
    }

    private func guessLie() -> ShotLie {
        guard let player, let guess = geo?.lie(at: player) else { return .fairway }
        return guess == .green ? .fairway : guess
    }

    private func markShot() {
        guard let player else { return }
        let shot = Shot(holeNumber: holeNumber, index: holeShots.count + 1, club: club, lie: lie,
                        point: player, yardsToGreen: yardsToGreen(from: player))
        round.shots.append(shot)
        score.isEntered = true
        club = nil
        lieTouched = false
        lie = guessLie()
        target = nil
    }

    private func markOnGreen() {
        guard let player else { return }
        let marker = Shot(holeNumber: holeNumber, index: holeShots.count + 1, club: nil, lie: .green,
                          point: player, yardsToGreen: yardsToGreen(from: player))
        round.shots.append(marker)
        score.isEntered = true
        if score.greenResult == nil, strokeShots.count <= par - 2 {
            score.greenResult = .hit
        }
    }

    private func undo() {
        guard let last = holeShots.last else { return }
        round.shots.removeAll { $0.persistentModelID == last.persistentModelID }
        context.delete(last)
        lie = holeShots.isEmpty ? .tee : guessLie()
    }

    private func setGreen(at point: GeoPoint) {
        guard let course = round.course else { return }
        var updated = course.geo ?? CourseGeo()
        updated.setGreen(hole: holeNumber, at: point)
        course.geo = updated
        settingGreen = false
        camera = initialCamera()
    }

    /// Looks down the hole from the tee (or the player) to the green.
    private func initialCamera() -> MapCameraPosition {
        let start = holeGeo?.tee ?? location.point
        guard let green = holeGeo?.greenCenter else {
            if let start { return .camera(MapCamera(centerCoordinate: start.coordinate, distance: 600)) }
            return .userLocation(fallback: .automatic)
        }
        guard let start else {
            return .camera(MapCamera(centerCoordinate: green.coordinate, distance: 500))
        }
        let length = Geo.meters(start, green)
        let mid = Geo.offset(start, bearing: Geo.bearing(start, green), meters: length / 2)
        return .camera(MapCamera(centerCoordinate: mid.coordinate,
                                 distance: max(350, length * 2.1),
                                 heading: Geo.bearing(start, green),
                                 pitch: 0))
    }
}
