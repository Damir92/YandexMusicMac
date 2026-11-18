import SwiftUI
import AppKit
import QuartzCore

/// Hardware-accelerated equalizer indicator using pure CoreAnimation (`CALayer` + `CABasicAnimation`).
/// Produces ZERO SwiftUI AttributeGraph / DisplayList invalidations and automatically pauses
/// when playback stops or the host window is occluded/hidden.
public struct YMPlayingEqualizerView: View {
    public let color: Color
    public let barWidth: CGFloat
    public let maxHeight: CGFloat
    public let minHeight: CGFloat
    public let isPlaying: Bool

    private let barSpacing: CGFloat = 2

    public init(
        color: Color = YMTheme.accent,
        barWidth: CGFloat = 2.5,
        maxHeight: CGFloat = 14,
        minHeight: CGFloat = 3,
        isPlaying: Bool = true
    ) {
        self.color = color
        self.barWidth = barWidth
        self.maxHeight = maxHeight
        self.minHeight = minHeight
        self.isPlaying = isPlaying
    }

    private var totalWidth: CGFloat {
        barWidth * 4 + barSpacing * 3
    }

    public var body: some View {
        CoreAnimationEqualizerRepresentable(
            color: color,
            barWidth: barWidth,
            barSpacing: barSpacing,
            maxHeight: maxHeight,
            minHeight: minHeight,
            isPlaying: isPlaying
        )
        .frame(width: totalWidth, height: maxHeight)
        .allowsHitTesting(false)
    }
}

private struct CoreAnimationEqualizerRepresentable: NSViewRepresentable {
    let color: Color
    let barWidth: CGFloat
    let barSpacing: CGFloat
    let maxHeight: CGFloat
    let minHeight: CGFloat
    let isPlaying: Bool

    func makeNSView(context: Context) -> CoreAnimationEqualizerNSView {
        let view = CoreAnimationEqualizerNSView()
        view.configure(
            color: color,
            barWidth: barWidth,
            barSpacing: barSpacing,
            maxHeight: maxHeight,
            minHeight: minHeight,
            isPlaying: isPlaying
        )
        return view
    }

    func updateNSView(_ nsView: CoreAnimationEqualizerNSView, context: Context) {
        nsView.configure(
            color: color,
            barWidth: barWidth,
            barSpacing: barSpacing,
            maxHeight: maxHeight,
            minHeight: minHeight,
            isPlaying: isPlaying
        )
    }

    static func dismantleNSView(_ nsView: CoreAnimationEqualizerNSView, coordinator: ()) {
        nsView.tearDown()
    }
}

@MainActor
private final class CoreAnimationEqualizerNSView: NSView {
    private struct BarSpec {
        let minScale: CGFloat
        let maxScale: CGFloat
        let duration: CFTimeInterval
    }

    private static let specs: [BarSpec] = [
        BarSpec(minScale: 0.25, maxScale: 0.95, duration: 0.42),
        BarSpec(minScale: 0.40, maxScale: 0.70, duration: 0.65),
        BarSpec(minScale: 0.20, maxScale: 1.00, duration: 0.35),
        BarSpec(minScale: 0.35, maxScale: 0.85, duration: 0.52)
    ]

    private let barLayers: [CALayer] = (0..<4).map { _ in CALayer() }
    private var currentColor: Color = .yellow
    private var barWidth: CGFloat = 2.5
    private var barSpacing: CGFloat = 2
    private var maxHeight: CGFloat = 14
    private var minHeight: CGFloat = 3
    private var isPlaying: Bool = false
    private var isAnimating: Bool = false
    private var observers: [any NSObjectProtocol] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        for barLayer in barLayers {
            // AppKit default coordinate system: y = 0 is bottom
            barLayer.anchorPoint = CGPoint(x: 0.5, y: 0.0)
            barLayer.actions = [
                "position": NSNull(),
                "bounds": NSNull(),
                "transform": NSNull(),
                "backgroundColor": NSNull(),
                "cornerRadius": NSNull()
            ]
            layer?.addSublayer(barLayer)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        color: Color,
        barWidth: CGFloat,
        barSpacing: CGFloat,
        maxHeight: CGFloat,
        minHeight: CGFloat,
        isPlaying: Bool
    ) {
        let geometryChanged = self.barWidth != barWidth
            || self.barSpacing != barSpacing
            || self.maxHeight != maxHeight
            || self.minHeight != minHeight

        self.currentColor = color
        self.barWidth = barWidth
        self.barSpacing = barSpacing
        self.maxHeight = maxHeight
        self.minHeight = minHeight
        self.isPlaying = isPlaying

        if geometryChanged {
            layoutBars()
        }
        applyBarColors()
        updateAnimationState()
    }

    override func layout() {
        super.layout()
        layoutBars()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeObservers()
        if let window {
            installObservers(for: window)
        }
        applyBarColors()
        updateAnimationState()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyBarColors()
    }

    func tearDown() {
        removeObservers()
        stopAnimations()
    }

    private func layoutBars() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let cornerRadius = barWidth / 2
        for (index, barLayer) in barLayers.enumerated() {
            let xCenter = CGFloat(index) * (barWidth + barSpacing) + barWidth * 0.5
            barLayer.bounds = CGRect(x: 0, y: 0, width: barWidth, height: maxHeight)
            barLayer.position = CGPoint(x: xCenter, y: 0)
            barLayer.cornerRadius = cornerRadius
        }
        CATransaction.commit()
    }

    private func applyBarColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let nsColor = NSColor(self.currentColor)
            let cgColor = nsColor.usingColorSpace(.sRGB)?.cgColor ?? nsColor.cgColor
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for barLayer in self.barLayers {
                barLayer.backgroundColor = cgColor
            }
            CATransaction.commit()
        }
    }

    private var isVisibleInWindow: Bool {
        guard let window else { return false }
        guard !NSApp.isHidden, !window.isMiniaturized else { return false }
        return window.occlusionState.contains(.visible)
    }

    private func updateAnimationState() {
        let shouldAnimate = isPlaying && isVisibleInWindow
        if shouldAnimate {
            startAnimationsIfNeeded()
        } else {
            stopAnimations()
        }
    }

    private func startAnimationsIfNeeded() {
        guard !isAnimating else { return }
        isAnimating = true

        let minRatio = maxHeight > 0 ? minHeight / maxHeight : 0.2
        for (index, barLayer) in barLayers.enumerated() {
            let spec = Self.specs[index]
            let fromScale = max(spec.minScale, minRatio)

            let anim = CABasicAnimation(keyPath: "transform.scale.y")
            anim.fromValue = fromScale
            anim.toValue = spec.maxScale
            anim.duration = spec.duration
            anim.autoreverses = true
            anim.repeatCount = .infinity
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            anim.isRemovedOnCompletion = false
            anim.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 24)
            barLayer.add(anim, forKey: "eqBounce")
        }
    }

    private func stopAnimations() {
        isAnimating = false
        let minRatio = maxHeight > 0 ? minHeight / maxHeight : 0.2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, barLayer) in barLayers.enumerated() {
            barLayer.removeAnimation(forKey: "eqBounce")
            let restScale = max(Self.specs[index].minScale, minRatio)
            barLayer.transform = CATransform3DMakeScale(1.0, restScale, 1.0)
        }
        CATransaction.commit()
    }

    private func installObservers(for window: NSWindow) {
        let center = NotificationCenter.default
        let occlusionObs = center.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateAnimationState()
            }
        }
        let miniaturizeObs = center.addObserver(
            forName: NSWindow.didMiniaturizeNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateAnimationState()
            }
        }
        let deminiaturizeObs = center.addObserver(
            forName: NSWindow.didDeminiaturizeNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateAnimationState()
            }
        }
        let hideObs = center.addObserver(
            forName: NSApplication.didHideNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateAnimationState()
            }
        }
        let unhideObs = center.addObserver(
            forName: NSApplication.didUnhideNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateAnimationState()
            }
        }
        observers = [occlusionObs, miniaturizeObs, deminiaturizeObs, hideObs, unhideObs]
    }

    private func removeObservers() {
        let center = NotificationCenter.default
        for obs in observers {
            center.removeObserver(obs)
        }
        observers.removeAll()
    }
}
