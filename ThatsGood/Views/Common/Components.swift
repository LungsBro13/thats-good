import SwiftUI

struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(1)
            .foregroundStyle(Color.tgMuted)
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle().fill(Color.tgLine).frame(height: 1)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(Color.tgBackground)
            .background(Color.primary.opacity(configuration.isPressed ? 0.75 : 1),
                        in: RoundedRectangle(cornerRadius: 10))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(Color.primary)
            .background(RoundedRectangle(cornerRadius: 10).stroke(Color.tgLine))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Minus / value / plus, with 44pt touch targets.
struct StepperCell: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title)
            HStack {
                stepButton("minus", label: "Decrease \(title)") { value = max(range.lowerBound, value - 1) }
                Spacer(minLength: 4)
                Text("\(value)")
                    .font(.system(size: 30, weight: .semibold))
                    .monospacedDigit()
                Spacer(minLength: 4)
                stepButton("plus", label: "Increase \(title)") { value = min(range.upperBound, value + 1) }
            }
        }
        .padding(12)
    }

    private func stepButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.tgLine))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// A row of buttons where one (or none) can be picked. Tapping the picked one again clears it.
struct ChoiceRow<Option: Hashable>: View {
    let title: String
    let options: [Option]
    @Binding var selection: Option?
    let label: (Option) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title)
            SegmentBar(options: options, isSelected: { $0 == selection }, label: label) { option in
                selection = (selection == option) ? nil : option
            }
        }
    }
}

/// Same look, but one option is always picked.
struct SegmentedPicker<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String

    var body: some View {
        SegmentBar(options: options, isSelected: { $0 == selection }, label: label) { selection = $0 }
    }
}

private struct SegmentBar<Option: Hashable>: View {
    let options: [Option]
    let isSelected: (Option) -> Bool
    let label: (Option) -> String
    let onTap: (Option) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let on = isSelected(option)
                Button { onTap(option) } label: {
                    Text(label(option))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(on ? Color.tgBackground : Color.tgMuted)
                        .background(on ? Color.primary : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.tgLine))
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(Color.tgMuted)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
            if let detail {
                Text(detail).font(.caption2).foregroundStyle(Color.tgMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }
}

struct ComingSoonView: View {
    let title: String
    let message: String

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Coming soon")
                Text(message).font(.body).foregroundStyle(Color.tgMuted)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(Color.tgBackground)
            .navigationTitle(title)
        }
    }
}
