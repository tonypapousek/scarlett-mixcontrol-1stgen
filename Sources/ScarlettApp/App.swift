import SwiftUI
import AppKit

// Swift Package executables don't have an Info.plist marking them as regular
// apps; without help the window comes up behind other apps with no Dock icon.
// Set activation policy after launch via an NSApplicationDelegate.
final class AppDelegate: NSObject, NSApplicationDelegate {
    override init() {
        // Without an .app bundle (we're a Swift Package executable),
        // NSApplication uses the executable filename ("scarlett-app") for
        // the menu-bar title and the Dock label.  Overriding the process
        // name BEFORE NSApp builds the default menu bar gets us the
        // "Scarlett MixControl" title we actually want.
        ProcessInfo.processInfo.processName = "Scarlett MixControl"
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Force AppKit-backed controls (Picker .menu = NSPopUpButton, Menu,
        // context menus, etc.) to use dark appearance regardless of the
        // user's system setting. SwiftUI's .preferredColorScheme only
        // affects SwiftUI views, not the embedded AppKit controls.
        NSApp.appearance = NSAppearance(named: .darkAqua)

        // Let the window content extend behind the title bar so the
        // sidebar's background can run continuously from the very top of
        // the window down — otherwise there's a strip of plain title-bar
        // chrome between the sidebar and the rest of the window.
        DispatchQueue.main.async {
            for win in NSApp.windows {
                win.titlebarAppearsTransparent = true
                win.styleMask.insert(.fullSizeContentView)
            }
        }

        // Dock icon — load the PNG from the resource bundle, round its
        // corners and inset it slightly so it matches the macOS visual
        // weight of other Dock icons (which use a squircle mask and have
        // built-in padding around the artwork).
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let raw = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = macOSStyleIcon(raw)
        }
    }

        /// Approximate Apple's standard Dock icon look:
    ///  - inset the source artwork ~10% so the rendered icon matches the
    ///    visual size of stock macOS apps
    ///  - clip the whole canvas with a rounded rectangle (~22% corner
    ///    radius, close enough to Apple's squircle for our purposes)
    private func macOSStyleIcon(_ src: NSImage,
                                inset: CGFloat = 0.08,
                                cornerFraction: CGFloat = 0.225) -> NSImage {
        let size = src.size
        let result = NSImage(size: size)
        result.lockFocus()
        let outer = NSRect(origin: .zero, size: size)
        let radius = min(size.width, size.height) * cornerFraction
        NSBezierPath(roundedRect: outer, xRadius: radius, yRadius: radius).addClip()
        let insetPx = min(size.width, size.height) * inset
        let drawRect = outer.insetBy(dx: insetPx, dy: insetPx)
        src.draw(in: drawRect,
                 from: .zero,
                 operation: .sourceOver,
                 fraction: 1.0)
        result.unlockFocus()
        return result
    }
}

@main
struct ScarlettApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var state = MixerState()

    var body: some Scene {
        Window("Scarlett MixControl", id: "main") {
            ContentView(state: state)
                .frame(
                    minWidth: 1100,
                    idealWidth: 1340,
                    maxWidth: .infinity,
                    minHeight: 580,
                    idealHeight: 720,
                    maxHeight: .infinity
                )
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    if UserDefaults.standard.bool(forKey: "scarlett.autoBackupOnQuit") {
                        state.userAutoSaveBackup(label: "at shutdown")
                    }
                }
        }
        .windowResizability(.contentSize)
        .commands {
            // Replace the default File-menu commands so we can plug in
            // snapshot Save/Open.  Removed-by-default items (New Window,
            // Print, etc.) stay removed; we just add ours.
            CommandGroup(replacing: .saveItem) {
                Button("Save snapshot…") {
                    exportSnapshot(state: state)
                }
                .keyboardShortcut("s", modifiers: [.command])

                Button("Open snapshot…") {
                    importSnapshot(state: state)
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
        }
    }
}

@MainActor
private func exportSnapshot(state: MixerState) {
    let panel = NSSavePanel()
    // No `allowedContentTypes`: NSSavePanel would otherwise auto-append
    // the canonical extension of the chosen UTType (e.g. ".json"), which
    // mangles our `.8i6` extension into "ScarlettSnapshot.8i6.json".
    panel.allowsOtherFileTypes = true
    panel.nameFieldStringValue = "ScarlettSnapshot.8i6"
    panel.title = "Save Scarlett snapshot"
    if panel.runModal() == .OK, let url = panel.url {
        do { try state.userExportSnapshot(to: url) }
        catch {
            NSAlert(error: error).runModal()
        }
    }
}

@MainActor
private func importSnapshot(state: MixerState) {
    let panel = NSOpenPanel()
    // No content-type filter — the user might have a `.8i6` file or a
    // `.json` file (both are valid, contents are checked at decode time).
    panel.allowsMultipleSelection = false
    panel.title = "Open Scarlett snapshot"
    if panel.runModal() == .OK, let url = panel.url {
        do { try state.userImportSnapshot(from: url) }
        catch {
            NSAlert(error: error).runModal()
        }
    }
}
