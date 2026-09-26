import AIBarCore
import AppKit
import SwiftUI

/// Owns the menu bar item: draws the badge and tooltip, toggles the usage popover on left click,
/// and reports right click (or control-click) as a refresh request.
@MainActor
final class StatusItemController: NSObject {
    var onRefreshRequested: () -> Void = {}

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let settingsStore: SettingsStore
    private var shownState: ProviderState?
    private var tooltipClock: Timer?
    private lazy var refreshTracer = PillTracer(button: statusItem.button)

    init(popoverContent: some View, settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        super.init()
        popover.behavior = .transient
        let hostingController = NSHostingController(rootView: popoverContent)
        // Lets the popover resize when its content changes, e.g. from an error message to the window rows.
        hostingController.sizingOptions = .preferredContentSize
        popover.contentViewController = hostingController
        configureButton()
        startTooltipClock()
        refitBadgeWhenDisplaysChange()
        render()
    }

    /// Shows `state` in the badge; nil before any provider has reported.
    func show(_ state: ProviderState?) {
        shownState = state
        render()
        refreshTracer.follow(isRefreshing: state?.isRefreshing ?? false)
    }

    func settingsDidChange() {
        render()
    }

    /// Makes way for the Settings window, which the popover would otherwise cover.
    func closePopover() {
        popover.performClose(nil)
    }

    /// Text, tint and tooltip all describe the window chosen in settings, so a weekly badge is coloured by the weekly
    /// forecast.
    private func render() {
        let window = shownState?.badgeWindow(for: settingsStore.settings.badgeWindowID)
        let forecast = window.flatMap { shownState?.forecasts[$0.id] }
        let text = UsageText.badge(window: window, hasError: shownState?.lastError != nil)
        let height = BadgeSize.height(menuBarHeights: NSScreen.screens.map(\.menuBarHeight))
        let tint = BadgeTint(forecast: forecast)
        statusItem.button?.image = BadgeRenderer.image(text: text, tint: tint, height: height)
        refreshTracer.fit(tint: tint)
        statusItem.button?.toolTip = shownState.map { state in
            UsageText.tooltip(providerName: state.displayName, window: window, forecast: forecast,
                              errorDescription: state.lastError?.localizedDescription, now: Date())
        }
    }

    /// The tooltip counts down to the reset in minutes, but data only changes every poll, so it is redrawn on
    /// its own to stay accurate in between.
    private func startTooltipClock() {
        tooltipClock = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.render() }
        }
    }

    /// The badge's height depends on the menu bars it appears in, which change as displays come and go.
    private func refitBadgeWhenDisplaysChange() {
        // The notification center keeps the observer for the app's lifetime, which is this controller's lifetime.
        _ = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.render() }
        }
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        if isSecondaryClick(NSApp.currentEvent) {
            onRefreshRequested()
        } else {
            togglePopover(from: sender)
        }
    }

    // Control-click counts as right click, matching the macOS convention for one-button input.
    private func isSecondaryClick(_ event: NSEvent?) -> Bool {
        guard let event else { return false }
        return event.type == .rightMouseUp || event.modifierFlags.contains(.control)
    }

    private func togglePopover(from button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(button)
        } else {
            // An accessory app is not active by default; without activating, the transient popover
            // would not receive the outside click that should dismiss it.
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}

/// Runs a light around the badge's capsule while a refresh runs, so a right-click refresh is acknowledged where the
/// user clicked (see `RefreshTracer` for how it moves and settles). Under Reduce Motion the outline brightens and
/// fades in place instead, so the refresh still shows without movement.
@MainActor
private final class PillTracer: NSObject {
    private weak var button: NSStatusBarButton?
    private let light = CAShapeLayer()
    private var tracer = RefreshTracer()
    private var isRefreshing = false
    private var displayLink: CADisplayLink?
    /// The capsule the path was last built for, so it is only rebuilt when the badge changes shape.
    private var outlinedRect: CGRect?

    /// Thin enough to leave the reading legible at 24 pt.
    private static let lineWidthPerPointOfHeight: CGFloat = 0.08
    private static let minimumLineWidth: CGFloat = 1.5
    /// A soft halo, so the light reads as a glow rather than a drawn line.
    private static let haloOpacity: Float = 0.5

    init(button: NSStatusBarButton?) {
        self.button = button
        super.init()
        button?.wantsLayer = true
        light.fillColor = nil
        light.lineCap = .round
        light.shadowOffset = .zero
        light.shadowOpacity = Self.haloOpacity
        light.isHidden = true
        button?.layer?.addSublayer(light)
    }

    /// Reacts only to a change, since every state update passes through here.
    func follow(isRefreshing refreshing: Bool) {
        guard refreshing != isRefreshing else { return }
        isRefreshing = refreshing
        let now = Date()
        if refreshing {
            tracer.start(at: now)
            startDisplayLink()
        } else {
            tracer.stop(at: now)
        }
        draw(at: now)
    }

    /// Called after every badge redraw: the capsule widens and narrows with its text, and the light takes the
    /// colour of the text, so it shows on a coloured capsule and on the plain neutral badge alike.
    func fit(tint: BadgeTint) {
        guard let button, let cell = button.cell else { return }
        let rect = cell.imageRect(forBounds: button.bounds)
        let color = button.effectiveAppearance.resolved(tint.textColor)
        withoutImplicitAnimation {
            light.strokeColor = color
            light.shadowColor = color
            guard rect != outlinedRect else { return }
            outlinedRect = rect
            let lineWidth = max(rect.height * Self.lineWidthPerPointOfHeight, Self.minimumLineWidth)
            light.frame = rect
            light.lineWidth = lineWidth
            light.shadowRadius = lineWidth * 0.6
            light.path = doubledOutline(of: CGRect(origin: .zero, size: rect.size).insetBy(dx: lineWidth / 2,
                                                                                           dy: lineWidth / 2),
                                        topAtMinY: button.isFlipped)
        }
    }

    /// Linked to the button's display, so the light moves in step with the screen it is on, including while a
    /// menu is being tracked. It only runs while there is light to draw.
    private func startDisplayLink() {
        guard displayLink == nil, let button else { return }
        let link = button.displayLink(target: self, selector: #selector(step))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = Date()
        draw(at: now)
        if !tracer.isMoving(at: now) {
            link.invalidate()
            displayLink = nil
        }
    }

    private func draw(at now: Date) {
        withoutImplicitAnimation {
            guard let segment = tracer.segment(at: now) else {
                light.isHidden = true
                return
            }
            light.isHidden = false
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                glowInPlace(segment)
            } else {
                let stroke = segment.strokeOnDoubledOutline
                light.opacity = 1
                light.strokeStart = stroke.lowerBound
                light.strokeEnd = stroke.upperBound
            }
        }
    }

    /// The whole outline, pulsing once per lap. The pulse is dark at the starting point, where the head stops, so
    /// it ends there as smoothly as the moving light drains away.
    private func glowInPlace(_ segment: RefreshTracer.Segment) {
        let pulse = 0.5 - 0.5 * cos(2 * .pi * segment.head)
        light.opacity = Float(0.7 * pulse)
        light.strokeStart = 0
        light.strokeEnd = 0.5
    }

    /// The light is a sublayer, which Core Animation would otherwise ease into every new position a quarter second
    /// late.
    private func withoutImplicitAnimation(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
    }
}

/// The capsule's outline twice over, clockwise from the middle of its top edge, so the light sets off and settles
/// at the top, where the eye expects a loop to begin. Built from corner tangents, which trace the same way on
/// screen whether or not the button's coordinates are flipped.
private func doubledOutline(of rect: CGRect, topAtMinY: Bool) -> CGPath {
    let top = topAtMinY ? rect.minY : rect.maxY
    let bottom = topAtMinY ? rect.maxY : rect.minY
    let radius = rect.height / 2
    let path = CGMutablePath()
    path.move(to: CGPoint(x: rect.midX, y: top))
    for _ in 0..<2 {
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: top), tangent2End: CGPoint(x: rect.maxX, y: bottom),
                    radius: radius)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: bottom), tangent2End: CGPoint(x: rect.minX, y: bottom),
                    radius: radius)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: bottom), tangent2End: CGPoint(x: rect.minX, y: top),
                    radius: radius)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: top), tangent2End: CGPoint(x: rect.midX, y: top),
                    radius: radius)
        path.addLine(to: CGPoint(x: rect.midX, y: top))
    }
    return path
}

extension NSAppearance {
    /// A dynamic colour as it looks in this appearance, for layers, which do not follow appearance changes.
    fileprivate func resolved(_ color: NSColor) -> CGColor {
        var resolved = color.cgColor
        performAsCurrentDrawingAppearance { resolved = color.cgColor }
        return resolved
    }
}

extension NSScreen {
    /// Points between the top of the screen and its visible area; 0 while a full-screen app hides the menu bar.
    fileprivate var menuBarHeight: Double {
        Double(frame.maxY - visibleFrame.maxY)
    }
}
