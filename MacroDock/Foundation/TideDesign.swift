import SwiftUI
import UIKit

/// Role in MVVM-C: typed design tokens. The only place that names colours, type steps, spacing and motion.
enum TidePalette {
    static let background = Color("mdk_background")
    static let surface = Color("mdk_surface")
    static let ink = Color("mdk_ink")
    static let accent = Color("mdk_accent")
    static let muted = Color("mdk_muted")

    static func uiColor(_ name: String) -> UIColor {
        UIColor(named: name) ?? .black
    }
}

enum SignalType {
    static let beacon = Font.custom("Optima-Bold", size: 40, relativeTo: .largeTitle)
    static let mast = Font.custom("Optima-Bold", size: 28, relativeTo: .title)
    static let berth = Font.custom("Optima-Bold", size: 20, relativeTo: .title3)
    static let cargo = Font.custom("Optima-Regular", size: 17, relativeTo: .body)
    static let log = Font.custom("Optima-Regular", size: 15, relativeTo: .subheadline)
    static let signal = Font.custom("Optima-Regular", size: 12, relativeTo: .caption)

    static let headerKerning: CGFloat = 3.2
}

enum BerthMetrics {
    static let unit: CGFloat = 8
    static let radius: CGFloat = 0
    static let tap: CGFloat = 44

    static func space(_ multiples: Int) -> CGFloat {
        unit * CGFloat(multiples)
    }
}

enum TideMotion {
    static let duration: Double = 0.28
    static let curve = Animation.timingCurve(0.25, 0.1, 0.25, 1, duration: duration)

    static func fadeIfReduced(_ reduce: Bool) -> Animation {
        reduce ? .easeOut(duration: 0.2) : curve
    }
}

enum TideFormat {
    static let kcal: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    static let macro: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    static let grams: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    static func kcalText(_ value: Double) -> String {
        kcal.string(from: NSNumber(value: value.rounded())) ?? "0"
    }

    static func macroText(_ value: Double?) -> String {
        guard let value else { return "unknown" }
        return macro.string(from: NSNumber(value: value)) ?? "unknown"
    }

    static func compactMacro(_ value: Double?) -> String {
        guard let value else { return "—" }
        return macro.string(from: NSNumber(value: value)) ?? "—"
    }

    static func gramsText(_ value: Double) -> String {
        grams.string(from: NSNumber(value: value)) ?? "0"
    }

    static func parseGrams(_ raw: String) -> Double? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .current
        return formatter.number(from: raw)?.doubleValue
    }
}

enum HapticBeacon {
    @MainActor
    static func commit() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

struct TideEmptyState: View {
    let image: String
    let headline: String
    let line: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: BerthMetrics.space(2)) {
            Image(image)
                .resizable()
                .scaledToFit()
                .frame(width: 168, height: 168)
                .accessibilityHidden(true)
            Text(headline)
                .font(SignalType.berth)
                .kerning(SignalType.headerKerning)
                .foregroundStyle(TidePalette.ink)
                .multilineTextAlignment(.center)
            Text(line)
                .font(SignalType.log)
                .foregroundStyle(TidePalette.muted)
                .multilineTextAlignment(.center)
            Button(actionTitle, action: action)
                .buttonStyle(HarborActionStyle())
                .frame(minHeight: BerthMetrics.tap)
        }
        .padding(BerthMetrics.space(3))
        .frame(maxWidth: .infinity)
    }
}

struct HarborActionStyle: ButtonStyle {
    var destructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SignalType.berth)
            .kerning(1.2)
            .foregroundStyle(TidePalette.ink)
            .frame(maxWidth: .infinity, minHeight: BerthMetrics.tap)
            .background(destructive ? TidePalette.accent : TidePalette.surface)
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

struct CargoThumb: View {
    let product: CargoProduct

    var body: some View {
        Group {
            if let url = product.imageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        bundled
                    case .empty:
                        TidePalette.surface
                    @unknown default:
                        bundled
                    }
                }
            } else {
                bundled
            }
        }
        .frame(width: 56, height: 56)
        .clipped()
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var bundled: some View {
        if let asset = product.shelfAsset {
            Image(asset)
                .resizable()
                .scaledToFill()
        } else {
            Image("mdk_ProductPlaceholder")
                .resizable()
                .scaledToFill()
        }
    }
}

struct TideFaultBanner: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: BerthMetrics.space(2)) {
            Text(message)
                .font(SignalType.log)
                .foregroundStyle(TidePalette.ink)
                .multilineTextAlignment(.center)
            Button("Try the quay again", action: retry)
                .buttonStyle(HarborActionStyle())
        }
        .padding(BerthMetrics.space(2))
        .frame(maxWidth: .infinity)
        .background(TidePalette.surface)
    }
}
