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
        if let screen = NSScreen.main {
            let visibleFrame = screen.visibleFrame
            var savedX = UserDefaults.standard.double(forKey: userDefaultsXKey)
            var savedY = UserDefaults.standard.double(forKey: userDefaultsYKey)
            if savedX == 0 && savedY == 0 {
                savedX = UserDefaults.standard.double(forKey: "EchoBuddy.AvatarPosition.X")
                savedY = UserDefaults.standard.double(forKey: "EchoBuddy.AvatarPosition.Y")
            }
            
            var x: CGFloat = visibleFrame.maxX - 100
            var y: CGFloat = visibleFrame.minY + 120
            
            if savedX > 0 && savedY > 0 {
                x = CGFloat(savedX)
                y = CGFloat(savedY)
            }
            
            setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
    
    func resetToDefaultPosition() {
        if let screen = NSScreen.main {
            let visibleFrame = screen.visibleFrame
            let x = visibleFrame.maxX - 110
            let y = visibleFrame.minY + 140
            setFrameOrigin(NSPoint(x: x, y: y))
            savePosition(NSPoint(x: x, y: y))
        }
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
