import Cocoa
import SwiftUI

@MainActor
final class FloatingAvatarPanel: NSPanel {
    var onToggleDialog: (() -> Void)?

    private let userDefaultsXKey = "Shodha.AvatarPosition.X"
    private let userDefaultsYKey = "Shodha.AvatarPosition.Y"

    init(appState: AppState) {
        super.init(
            contentRect: NSRect(x: 100, y: 100, width: 80, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.isFloatingPanel = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.isMovableByWindowBackground = false

        let avatarHost = AvatarHostView(appState: appState, onToggle: { [weak self] in
            self?.onToggleDialog?()
        }, onDidMove: { [weak self] newOrigin in
            self?.savePosition(newOrigin)
        })

        self.contentView = avatarHost

        restorePosition()
    }

    func savePosition(_ origin: NSPoint) {
        UserDefaults.standard.set(Double(origin.x), forKey: userDefaultsXKey)
        UserDefaults.standard.set(Double(origin.y), forKey: userDefaultsYKey)
    }

    func restorePosition() {
        let screens = NSScreen.screens
        guard let fallbackScreen = NSScreen.main ?? screens.first else { return }
        let fallbackVisible = fallbackScreen.visibleFrame

        let defaults = UserDefaults.standard
        let hasShodhaSaved = defaults.object(forKey: userDefaultsXKey) != nil && defaults.object(forKey: userDefaultsYKey) != nil
        let hasLegacySaved = defaults.object(forKey: "EchoBuddy.AvatarPosition.X") != nil && defaults.object(forKey: "EchoBuddy.AvatarPosition.Y") != nil

        var candidateOrigin = NSPoint(
            x: fallbackVisible.maxX - 100,
            y: fallbackVisible.minY + 120
        )

        if hasShodhaSaved {
            candidateOrigin = NSPoint(
                x: defaults.double(forKey: userDefaultsXKey),
                y: defaults.double(forKey: userDefaultsYKey)
            )
        } else if hasLegacySaved {
            candidateOrigin = NSPoint(
                x: defaults.double(forKey: "EchoBuddy.AvatarPosition.X"),
                y: defaults.double(forKey: "EchoBuddy.AvatarPosition.Y")
            )
        }

        let clampedOrigin = clampOriginToVisibleScreens(candidateOrigin, panelSize: frame.size, screens: screens, fallbackVisible: fallbackVisible)
        setFrameOrigin(clampedOrigin)
    }

    func resetToDefaultPosition() {
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let visibleFrame = screen.visibleFrame
            let x = visibleFrame.maxX - 110
            let y = visibleFrame.minY + 140
            let origin = NSPoint(x: x, y: y)
            setFrameOrigin(origin)
            savePosition(origin)
        }
    }

    private func clampOriginToVisibleScreens(
        _ origin: NSPoint,
        panelSize: NSSize,
        screens: [NSScreen],
        fallbackVisible: NSRect
    ) -> NSPoint {
        let candidateRect = NSRect(origin: origin, size: panelSize)
        if let matchingScreen = screens.first(where: { $0.visibleFrame.intersects(candidateRect) }) {
            let vf = matchingScreen.visibleFrame
            let clampedX = min(max(origin.x, vf.minX), vf.maxX - panelSize.width)
            let clampedY = min(max(origin.y, vf.minY), vf.maxY - panelSize.height)
            return NSPoint(x: clampedX, y: clampedY)
        }

        // Saved position was on a disconnected monitor; recover cleanly to fallback screen
        return NSPoint(
            x: fallbackVisible.maxX - 100,
            y: fallbackVisible.minY + 120
        )
    }
}

// Custom Host View that differentiates smooth dragging vs clicking
@MainActor
final class AvatarHostView: NSView {
    private let onToggle: () -> Void
    private let onDidMove: (NSPoint) -> Void
    private var clickOffsetInWindow: NSPoint = .zero
    private var startDragScreenPos: NSPoint = .zero
    private var hasDragged = false

    init(appState: AppState, onToggle: @escaping () -> Void, onDidMove: @escaping (NSPoint) -> Void) {
        self.onToggle = onToggle
        self.onDidMove = onDidMove
        super.init(frame: NSRect(x: 0, y: 0, width: 80, height: 80))

        let swiftUIView = AvatarView(appState: appState, onToggleDialog: onToggle)
        let hostingView = NSHostingView(rootView: swiftUIView)
        hostingView.frame = self.bounds
        hostingView.autoresizingMask = [.width, .height]
        addSubview(hostingView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        clickOffsetInWindow = event.locationInWindow
        startDragScreenPos = NSEvent.mouseLocation
        hasDragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        let currentMouseScreen = NSEvent.mouseLocation
        let dx = currentMouseScreen.x - startDragScreenPos.x
        let dy = currentMouseScreen.y - startDragScreenPos.y

        if !hasDragged && (dx * dx + dy * dy > 16) {
            hasDragged = true
        }

        if hasDragged, let window = self.window {
            let newOrigin = NSPoint(
                x: currentMouseScreen.x - clickOffsetInWindow.x,
                y: currentMouseScreen.y - clickOffsetInWindow.y
            )
            window.setFrameOrigin(newOrigin)
            onDidMove(newOrigin)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if !hasDragged {
            onToggle()
        }
        hasDragged = false
    }
}
