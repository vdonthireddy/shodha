import Cocoa
import SwiftUI
import Combine

@MainActor
final class SpeechDialogPanel: NSPanel {
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }
    
    private let dialogWidth: CGFloat = 360
    private var appState: AppState
    private var cancellables = Set<AnyCancellable>()
    
    private var currentTargetHeight: CGFloat {
        appState.activeTab == .chat ? 310 : 380
    }
    
    init(appState: AppState, onClose: @escaping () -> Void) {
        self.appState = appState
        let initialHeight: CGFloat = appState.activeTab == .chat ? 310 : 380
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: initialHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        self.isFloatingPanel = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        
        let dialogView = SpeechDialogView(appState: appState, onClose: onClose)
        let hostingView = NSHostingView(rootView: dialogView)
        hostingView.frame = NSRect(x: 0, y: 0, width: dialogWidth, height: initialHeight)
        hostingView.autoresizingMask = [.width, .height]
        self.contentView = hostingView
        
        // Listen to tab changes to smoothly adjust window height
        appState.$activeTab
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newTab in
                self?.animateHeightChange(for: newTab)
            }
            .store(in: &cancellables)
    }
    
    private func animateHeightChange(for tab: DialogTab) {
        let newHeight: CGFloat = tab == .chat ? 310 : 380
        var currentFrame = self.frame
        let dy = newHeight - currentFrame.height
        currentFrame.origin.y -= dy // Keep top edge anchored so it expands downwards
        currentFrame.size.height = newHeight
        
        // If window goes below screen bottom, adjust origin.y up
        if let screen = self.screen ?? NSScreen.main {
            let minY = screen.visibleFrame.minY + 10
            if currentFrame.origin.y < minY {
                currentFrame.origin.y = minY
            }
        }
        
        self.setFrame(currentFrame, display: true, animate: true)
    }
    
    func showNear(avatarPanel: NSPanel) {
        let avatarFrame = avatarPanel.frame
        let targetScreen = NSScreen.screens.first(where: { $0.frame.intersects(avatarFrame) }) ?? NSScreen.main
        let visibleFrame = targetScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        
        let height = currentTargetHeight
        
        var originX: CGFloat
        if avatarFrame.midX > visibleFrame.midX {
            originX = avatarFrame.minX - dialogWidth - 10
        } else {
            originX = avatarFrame.maxX + 10
        }
        
        originX = max(visibleFrame.minX + 10, min(originX, visibleFrame.maxX - dialogWidth - 10))
        
        var originY = avatarFrame.midY - (height / 2)
        originY = max(visibleFrame.minY + 10, min(originY, visibleFrame.maxY - height - 10))
        
        setFrame(NSRect(x: originX, y: originY, width: dialogWidth, height: height), display: true)
        
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            if let chars = event.charactersIgnoringModifiers {
                switch chars.lowercased() {
                case "c":
                    // 1. Try sending copy: to first responder
                    if NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self) {
                        return true
                    }
                    // 2. Fallback: Copy the assistant's last response
                    if !appState.agent.lastResponse.isEmpty {
                        appState.copyResponseToClipboard()
                        return true
                    }
                case "v":
                    // 1. Try sending paste: to first responder
                    if NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self) {
                        return true
                    }
                    // 2. Fallback: Paste clipboard text into inputText
                    if let str = NSPasteboard.general.string(forType: .string), !str.isEmpty {
                        appState.pasteIntoInput()
                        return true
                    }
                case "x":
                    if NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self) {
                        return true
                    }
                case "a":
                    if NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self) {
                        return true
                    }
                case "z":
                    let sel = event.modifierFlags.contains(.shift) ? Selector(("redo:")) : Selector(("undo:"))
                    if NSApp.sendAction(sel, to: nil, from: self) {
                        return true
                    }
                default:
                    break
                }
            }
        }
        return super.performKeyEquivalent(with: event)
    }
    
    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}
