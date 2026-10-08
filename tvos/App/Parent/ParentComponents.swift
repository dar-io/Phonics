import SwiftUI
import StorySoundsCore

// Shared building blocks for the grown-ups' area. Remote-first: big type, few controls per screen,
// paging instead of scrolling, and meaning always carried by words/symbols as well as colour.

/// Compact full-width row used for list items (smaller than FocusCardStyle so five fit on one screen).
struct ParentRowStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.calmMotion) private var calm
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 88

    func makeBody(configuration: Configuration) -> some View {
        let still = reduceMotion || calm
        return configuration.label
            .padding(.horizontal, 30).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .foregroundStyle(prominent ? Theme.onAccent : Theme.text)
            .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(prominent ? Theme.accent : Theme.surfaceRaised))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(Theme.focusRing, lineWidth: isFocused ? 8 : 0))
            .scaleEffect(isFocused && !still ? 1.03 : 1.0)
            .shadow(color: .black.opacity(isFocused ? 0.5 : 0), radius: isFocused ? 20 : 0, y: isFocused ? 10 : 0)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(still ? nil : .easeOut(duration: 0.15), value: isFocused)
    }
}

/// One screen of a section: title, optional page title, content, and a pager bar (Previous / Next / Back).
/// Previous/Next wrap around so they are never dead buttons. Menu/Back (`onExitCommand`) calls `onBack`.
struct ParentPageScaffold<Content: View>: View {
    private let title: String
    private let pageTitle: String?
    private let idPrefix: String
    private let page: Binding<Int>
    private let pageCount: Int
    private let pagerIsDefault: Bool
    private let backLabel: String
    private let onBack: () -> Void
    private let content: () -> Content
    @Namespace private var focusNS

    init(title: String, pageTitle: String? = nil, idPrefix: String, page: Binding<Int>, pageCount: Int,
         pagerIsDefault: Bool = true, backLabel: String = "Back to menu",
         onBack: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self.pageTitle = pageTitle; self.idPrefix = idPrefix; self.page = page
        self.pageCount = max(1, pageCount); self.pagerIsDefault = pagerIsDefault; self.backLabel = backLabel
        self.onBack = onBack; self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(Theme.headingFont).accessibilityAddTraits(.isHeader)
                Spacer()
                if pageCount > 1 {
                    Text("Page \(page.wrappedValue + 1) of \(pageCount)")
                        .font(Theme.captionFont).foregroundStyle(Theme.textSecondary)
                        .accessibilityLabel("Page \(page.wrappedValue + 1) of \(pageCount)")
                }
            }
            if let pageTitle = pageTitle {
                Text(pageTitle).font(Theme.bodyFont).foregroundStyle(Theme.accent)
                    .accessibilityAddTraits(.isHeader)
            }
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .focusSection()
            pager.focusSection()
        }
        .focusScope(focusNS)
        .screenContainer()
        .onExitCommand(perform: onBack)
    }

    private var pager: some View {
        HStack(spacing: 32) {
            if pageCount > 1 {
                Button { page.wrappedValue = (page.wrappedValue + pageCount - 1) % pageCount } label: {
                    Label("Previous", systemImage: "chevron.left").font(Theme.bodyFont)
                }
                .buttonStyle(FocusCardStyle())
                .a11yID(idPrefix + ".prev")
                .accessibilityLabel("Previous page. Page \(((page.wrappedValue + pageCount - 1) % pageCount) + 1) of \(pageCount)")
                .accessibilityHint("You are on page \(page.wrappedValue + 1) of \(pageCount)")

                Button { page.wrappedValue = (page.wrappedValue + 1) % pageCount } label: {
                    Label("Next", systemImage: "chevron.right").font(Theme.bodyFont)
                }
                .buttonStyle(FocusCardStyle(prominent: true))
                .prefersDefaultFocus(pagerIsDefault, in: focusNS)
                .a11yID(idPrefix + ".next")
                .accessibilityLabel("Next page. Page \(((page.wrappedValue + 1) % pageCount) + 1) of \(pageCount)")
                .accessibilityHint("You are on page \(page.wrappedValue + 1) of \(pageCount)")
            }
            Spacer(minLength: 0)
            Button(action: onBack) {
                Label(backLabel, systemImage: "arrow.uturn.backward").font(Theme.bodyFont)
            }
            .buttonStyle(FocusCardStyle(prominent: pageCount == 1))
            .prefersDefaultFocus(pagerIsDefault && pageCount == 1, in: focusNS)
            .a11yID(idPrefix + ".back")
            .accessibilityLabel(backLabel)
            .accessibilityHint("You can also press the Menu button on the remote")
        }
    }
}

/// Heading + paragraph, not focusable.
struct ParentInfoBlock: View {
    let heading: String
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(heading).font(Theme.subheadingFont).foregroundStyle(Theme.accent)
                .accessibilityAddTraits(.isHeader)
            Text(text).font(Theme.bodyFont).foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A big number with a word label (never colour only).
struct ParentStatTile: View {
    let value: Int
    let label: String
    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)").font(Theme.titleFont).monospacedDigit()
            Text(label).font(Theme.bodyFont).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 18)
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(Theme.surface))
        .accessibilityElement(children: .combine)
    }
}

/// "- value +" control. Buttons never get disabled (a disabled button loses focus and the focus would jump);
/// at a limit the press does nothing and the value text says so. For VoiceOver the value is also an adjustable
/// element (swipe up/down = increase/decrease) in addition to the two buttons.
struct ParentStepperRow: View {
    let title: String
    let hint: String
    let valueText: String
    let idPrefix: String
    let onDec: () -> Void
    let onInc: () -> Void

    var body: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.bodyFont).bold()
                Text(hint).font(Theme.captionFont).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // VoiceOver: this label block is the adjustable element (swipe up/down). The visible value text below is kept
            // as plain static text ("<title> is <value>") because UI tests read it.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(valueText)
            .accessibilityHint("\(hint) Swipe up or down to change.")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: onInc()
                case .decrement: onDec()
                @unknown default: break
                }
            }
            Spacer(minLength: 16)
            Button(action: onDec) { Image(systemName: "minus").font(Theme.controlGlyphFont) }
                .buttonStyle(FocusCardStyle())
                .a11yID(idPrefix + ".minus")
                .accessibilityLabel("Decrease \(title)")
                .accessibilityHint("Currently \(valueText)")
            Text(valueText).font(Theme.headingFont).monospacedDigit()
                .frame(minWidth: 230).multilineTextAlignment(.center)
                .accessibilityLabel("\(title) is \(valueText)")
            Button(action: onInc) { Image(systemName: "plus").font(Theme.controlGlyphFont) }
                .buttonStyle(FocusCardStyle())
                .a11yID(idPrefix + ".plus")
                .accessibilityLabel("Increase \(title)")
                .accessibilityHint("Currently \(valueText)")
        }
    }
}

/// On/off button whose state is shown with words and a symbol (not colour only).
struct ParentToggleRow: View {
    let title: String
    let hint: String
    let isOn: Bool
    let id: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.bodyFont).bold()
                    Text(hint).font(Theme.captionFont).multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 16)
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle").font(Theme.controlGlyphFont)
                Text(isOn ? "On" : "Off").font(Theme.headingFont).frame(minWidth: 110, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(FocusCardStyle())
        .a11yID(id)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
        .accessibilityHint("Press Select to switch \(isOn ? "off" : "on"). \(hint)")
    }
}

// MARK: Wording helpers

extension UnitStatus {
    var parentWord: String {
        switch self {
        case .locked: return "Locked"
        case .available: return "Ready"
        case .inProgress: return "Learning"
        case .reviewDue: return "Review"
        case .mastered: return "Secure"
        }
    }
    var parentSymbol: String {
        switch self {
        case .locked: return "lock.fill"
        case .available: return "play.circle"
        case .inProgress: return "book.fill"
        case .reviewDue: return "arrow.triangle.2.circlepath"
        case .mastered: return "checkmark.seal.fill"
        }
    }
}

enum ParentFormat {
    static func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB"); f.dateFormat = "d MMM"
        return f.string(from: d)
    }
    /// "b (/b/)" style label, matching ParentReport.
    static func label(_ u: GraphemeUnit) -> String {
        let g = u.graphemes.joined(separator: ", ")
        return g.isEmpty ? u.phoneme : "\(g) (\(u.phoneme))"
    }
    static func pageCount(items: Int, perPage: Int) -> Int { max(1, (items + perPage - 1) / perPage) }
    static func slice<T>(_ items: [T], page: Int, perPage: Int) -> [T] {
        let start = max(0, page) * perPage
        guard start < items.count else { return [] }
        return Array(items[start..<min(items.count, start + perPage)])
    }
}
