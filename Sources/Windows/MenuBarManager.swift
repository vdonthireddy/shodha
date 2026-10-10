import Cocoa

@MainActor
final class MenuBarManager {
    private var statusItem: NSStatusItem?
    private let appState: AppState
    private let onToggleDialog: () -> Void
    private let onResetPosition: () -> Void
    
    init(appState: AppState, onToggleDialog: @escaping () -> Void, onResetPosition: @escaping () -> Void) {
        self.appState = appState
        self.onToggleDialog = onToggleDialog
        self.onResetPosition = onResetPosition
        setupStatusItem()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            if let image = NSImage(systemSymbolName: "face.smiling", accessibilityDescription: "Shodha") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "✨"
            }
            button.toolTip = "Shodha Assistant"
        }
        
        let menu = NSMenu()
        
        let titleItem = NSMenuItem(title: "Shodha Assistant", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())
        
        let toggleItem = NSMenuItem(title: "Open / Close Shodha", action: #selector(toggleAction), keyEquivalent: "s")
        toggleItem.target = self
        menu.addItem(toggleItem)
        
        let resetPosItem = NSMenuItem(title: "Reset Avatar Position", action: #selector(resetPositionAction), keyEquivalent: "")
        resetPosItem.target = self
        menu.addItem(resetPosItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let mascotItem = NSMenuItem(title: "🌟 Switch to Cute Mascot", action: #selector(resetMascotAction), keyEquivalent: "")
        mascotItem.target = self
        menu.addItem(mascotItem)
        
        let photoItem = NSMenuItem(title: "📷 Add Photos from Mac...", action: #selector(choosePhotoAction), keyEquivalent: "")
        photoItem.target = self
        menu.addItem(photoItem)
        
        let replayItem = NSMenuItem(title: "Replay Last Speech", action: #selector(replayAction), keyEquivalent: "r")
        replayItem.target = self
        menu.addItem(replayItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit Shodha", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    @objc private func toggleAction() {
        onToggleDialog()
    }
    
    @objc private func resetPositionAction() {
        onResetPosition()
    }
    
    @objc private func choosePhotoAction() {
        appState.promptChoosePhotos()
    }
    
    @objc private func resetMascotAction() {
        appState.selectAvatar(id: nil)
    }
    
    @objc private func replayAction() {
        appState.replayLastText()
    }
    
    @objc private func quitAction() {
        NSApp.terminate(nil)
    }
}
