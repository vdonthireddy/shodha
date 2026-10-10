import Cocoa
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState!
    private var avatarPanel: FloatingAvatarPanel!
    private var dialogPanel: SpeechDialogPanel!
    private var menuBarManager: MenuBarManager!
    private var clickOutsideMonitor: Any?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as accessory app (floating companion + menu bar, no dock clutter)
        NSApp.setActivationPolicy(.accessory)
        setupMainMenu()
        
        appState = AppState()
        
        avatarPanel = FloatingAvatarPanel(appState: appState)
        
        dialogPanel = SpeechDialogPanel(appState: appState, onClose: { [weak self] in
            self?.hideDialog()
        })
        
        appState.onRequestShowDialog = { [weak self] in
            self?.showDialog()
        }
        
        avatarPanel.onToggleDialog = { [weak self] in
            self?.toggleDialog()
        }
        
        menuBarManager = MenuBarManager(
            appState: appState,
            onToggleDialog: { [weak self] in
                self?.toggleDialog()
            },
            onResetPosition: { [weak self] in
                self?.avatarPanel.resetToDefaultPosition()
            }
        )
        
        // Listen for app resigning active (e.g. clicking another app or desktop)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
        
        // Show avatar on screen (always on screen)
        avatarPanel.orderFrontRegardless()
        
        // Show speech bubble briefly on first launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.showDialog()
        }
    }
    
    func toggleDialog() {
        if dialogPanel.isVisible {
            hideDialog()
        } else {
            showDialog()
        }
    }
    
    func showDialog() {
        dialogPanel.showNear(avatarPanel: avatarPanel)
        appState.isDialogVisible = true
        startClickOutsideMonitoring()
    }
    
    func hideDialog() {
        dialogPanel.orderOut(nil)
        appState.isDialogVisible = false
        stopClickOutsideMonitoring()
    }
    
    private func startClickOutsideMonitoring() {
        stopClickOutsideMonitoring()
        
        // Detect clicks outside our windows (e.g. clicking the desktop background or another window)
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self, self.dialogPanel.isVisible else { return }
            guard !self.appState.isPickingPhoto else { return }
            
            let mouseLoc = NSEvent.mouseLocation
            // If click is outside the avatar and outside the dialog, hide the dialog!
            if !self.avatarPanel.frame.contains(mouseLoc) && !self.dialogPanel.frame.contains(mouseLoc) {
                Task { @MainActor in
                    self.hideDialog()
                }
            }
        }
    }
    
    private func stopClickOutsideMonitoring() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }
    
    @objc private func handleAppDidResignActive() {
        guard !appState.isPickingPhoto else { return }
        if dialogPanel.isVisible {
            hideDialog()
        }
    }
    
    private func setupMainMenu() {
        let mainMenu = NSMenu()
        
        // Application Menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About Shodha", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Hide Shodha", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Shodha", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        
        // Edit Menu (Essential for routing Cmd+C, Cmd+V, Cmd+X, Cmd+A, Cmd+Z on macOS)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())
        
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: ""))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        
        NSApp.mainMenu = mainMenu
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        avatarPanel.orderFrontRegardless()
        showDialog()
        return true
    }
}

@main
struct ShodhaApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
