import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var menuChannel: FlutterMethodChannel?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    // Force app to take focus immediately - fixes double-click issue
    NSApp.activate(ignoringOtherApps: true)
    if let window = NSApp.windows.first {
      window.makeKeyAndOrderFront(nil)
    }

    // Setup menu channel
    setupMenuChannel()

    // Build native menus
    buildNativeMenus()

    super.applicationDidFinishLaunching(notification)
  }

  private func setupMenuChannel() {
    guard let window = mainFlutterWindow as? MainFlutterWindow,
          let controller = window.contentViewController as? FlutterViewController else {
      return
    }

    menuChannel = FlutterMethodChannel(
      name: "fluxforge/menu",
      binaryMessenger: controller.engine.binaryMessenger
    )
  }

  private func sendMenuAction(_ action: String) {
    menuChannel?.invokeMethod("menuAction", arguments: action)
  }

  // MARK: - Build Native Menus

  private func buildNativeMenus() {
    guard let mainMenu = NSApp.mainMenu else { return }

    // Insert File menu after APP_NAME menu (index 1)
    let fileMenu = buildFileMenu()
    mainMenu.insertItem(fileMenu, at: 1)

    // Find and update Edit menu with FluxForge items
    // (Keep macOS standard Edit menu, it's already there)

    // Update View menu with FluxForge items
    if let viewMenuItem = mainMenu.item(withTitle: "View") {
      updateViewMenu(viewMenuItem.submenu)
    }

    // Insert Project menu before Window
    let projectMenu = buildProjectMenu()
    let windowIndex = mainMenu.indexOfItem(withTitle: "Window")
    if windowIndex >= 0 {
      mainMenu.insertItem(projectMenu, at: windowIndex)
    }

    // Insert Studio menu before Window (need to re-get index since we just inserted)
    let studioMenu = buildStudioMenu()
    let windowIndex2 = mainMenu.indexOfItem(withTitle: "Window")
    if windowIndex2 >= 0 {
      mainMenu.insertItem(studioMenu, at: windowIndex2)
    }
  }

  // MARK: - File Menu

  private func buildFileMenu() -> NSMenuItem {
    let fileMenuItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
    let fileMenu = NSMenu(title: "File")

    fileMenu.addItem(withTitle: "New Project", action: #selector(menuNewProject), keyEquivalent: "n")
    fileMenu.addItem(withTitle: "Open Project...", action: #selector(menuOpenProject), keyEquivalent: "o")
    fileMenu.addItem(NSMenuItem.separator())

    fileMenu.addItem(withTitle: "Save", action: #selector(menuSave), keyEquivalent: "s")
    let saveAsItem = fileMenu.addItem(withTitle: "Save As...", action: #selector(menuSaveAs), keyEquivalent: "S")
    saveAsItem.keyEquivalentModifierMask = [.command, .shift]
    fileMenu.addItem(NSMenuItem.separator())

    fileMenu.addItem(withTitle: "Import Routes JSON...", action: #selector(menuImportJSON), keyEquivalent: "i")
    let exportJSONItem = fileMenu.addItem(withTitle: "Export Routes JSON...", action: #selector(menuExportJSON), keyEquivalent: "E")
    exportJSONItem.keyEquivalentModifierMask = [.command, .shift]
    fileMenu.addItem(NSMenuItem.separator())

    fileMenu.addItem(withTitle: "Import Audio Folder...", action: #selector(menuImportAudioFolder), keyEquivalent: "")
    let importAudioItem = fileMenu.addItem(withTitle: "Import Audio Files...", action: #selector(menuImportAudioFiles), keyEquivalent: "I")
    importAudioItem.keyEquivalentModifierMask = [.command, .shift]
    fileMenu.addItem(NSMenuItem.separator())

    let exportAudioItem = fileMenu.addItem(withTitle: "Export Audio...", action: #selector(menuExportAudio), keyEquivalent: "E")
    exportAudioItem.keyEquivalentModifierMask = [.command, .option]
    let batchExportItem = fileMenu.addItem(withTitle: "Batch Export...", action: #selector(menuBatchExport), keyEquivalent: "E")
    batchExportItem.keyEquivalentModifierMask = [.option, .shift]
    fileMenu.addItem(withTitle: "Export Presets...", action: #selector(menuExportPresets), keyEquivalent: "")
    fileMenu.addItem(NSMenuItem.separator())

    let bounceItem = fileMenu.addItem(withTitle: "Bounce to Disk...", action: #selector(menuBounce), keyEquivalent: "B")
    bounceItem.keyEquivalentModifierMask = [.option]
    let renderItem = fileMenu.addItem(withTitle: "Render in Place", action: #selector(menuRenderInPlace), keyEquivalent: "R")
    renderItem.keyEquivalentModifierMask = [.option]

    fileMenuItem.submenu = fileMenu
    return fileMenuItem
  }

  // MARK: - View Menu Updates

  private func updateViewMenu(_ menu: NSMenu?) {
    guard let menu = menu else { return }

    // Add FluxForge View items at the beginning
    let insertIndex = 0

    menu.insertItem(withTitle: "Toggle Left Panel", action: #selector(menuToggleLeftPanel), keyEquivalent: "L", at: insertIndex)
    menu.item(at: insertIndex)?.keyEquivalentModifierMask = [.command]

    menu.insertItem(withTitle: "Toggle Right Panel", action: #selector(menuToggleRightPanel), keyEquivalent: "R", at: insertIndex + 1)
    menu.item(at: insertIndex + 1)?.keyEquivalentModifierMask = [.command]

    menu.insertItem(withTitle: "Toggle Lower Panel", action: #selector(menuToggleLowerPanel), keyEquivalent: "B", at: insertIndex + 2)
    menu.item(at: insertIndex + 2)?.keyEquivalentModifierMask = [.command]

    menu.insertItem(NSMenuItem.separator(), at: insertIndex + 3)

    menu.insertItem(withTitle: "Audio Pool", action: #selector(menuShowAudioPool), keyEquivalent: "P", at: insertIndex + 4)
    menu.item(at: insertIndex + 4)?.keyEquivalentModifierMask = [.option]

    menu.insertItem(withTitle: "Markers", action: #selector(menuShowMarkers), keyEquivalent: "M", at: insertIndex + 5)
    menu.item(at: insertIndex + 5)?.keyEquivalentModifierMask = [.option]

    menu.insertItem(withTitle: "MIDI Editor", action: #selector(menuShowMidiEditor), keyEquivalent: "E", at: insertIndex + 6)
    menu.item(at: insertIndex + 6)?.keyEquivalentModifierMask = [.option]

    menu.insertItem(NSMenuItem.separator(), at: insertIndex + 7)

    // Advanced panels
    menu.insertItem(withTitle: "Logical Editor", action: #selector(menuShowLogicalEditor), keyEquivalent: "L", at: insertIndex + 8)
    menu.item(at: insertIndex + 8)?.keyEquivalentModifierMask = [.command, .shift]

    menu.insertItem(withTitle: "Scale Assistant", action: #selector(menuShowScaleAssistant), keyEquivalent: "K", at: insertIndex + 9)
    menu.item(at: insertIndex + 9)?.keyEquivalentModifierMask = [.command, .shift]

    menu.insertItem(withTitle: "Groove Quantize", action: #selector(menuShowGrooveQuantize), keyEquivalent: "Q", at: insertIndex + 10)
    menu.item(at: insertIndex + 10)?.keyEquivalentModifierMask = [.command, .shift]

    menu.insertItem(withTitle: "Audio Alignment", action: #selector(menuShowAudioAlignment), keyEquivalent: "A", at: insertIndex + 11)
    menu.item(at: insertIndex + 11)?.keyEquivalentModifierMask = [.command, .shift]

    menu.insertItem(withTitle: "Track Versions", action: #selector(menuShowTrackVersions), keyEquivalent: "V", at: insertIndex + 12)
    menu.item(at: insertIndex + 12)?.keyEquivalentModifierMask = [.command, .shift]

    menu.insertItem(withTitle: "Macro Controls", action: #selector(menuShowMacroControls), keyEquivalent: "M", at: insertIndex + 13)
    menu.item(at: insertIndex + 13)?.keyEquivalentModifierMask = [.command, .shift]

    menu.insertItem(withTitle: "Clip Gain Envelope", action: #selector(menuShowClipGainEnvelope), keyEquivalent: "G", at: insertIndex + 14)
    menu.item(at: insertIndex + 14)?.keyEquivalentModifierMask = [.command, .shift]

    menu.insertItem(NSMenuItem.separator(), at: insertIndex + 15)

    menu.insertItem(withTitle: "Reset Layout", action: #selector(menuResetLayout), keyEquivalent: "", at: insertIndex + 16)

    menu.insertItem(NSMenuItem.separator(), at: insertIndex + 17)
  }

  // MARK: - Project Menu

  private func buildProjectMenu() -> NSMenuItem {
    let projectMenuItem = NSMenuItem(title: "Project", action: nil, keyEquivalent: "")
    let projectMenu = NSMenu(title: "Project")

    projectMenu.addItem(withTitle: "Project Settings...", action: #selector(menuProjectSettings), keyEquivalent: ",")
    projectMenu.addItem(NSMenuItem.separator())

    let templatesItem = projectMenu.addItem(withTitle: "Track Templates...", action: #selector(menuTrackTemplates), keyEquivalent: "T")
    templatesItem.keyEquivalentModifierMask = [.option]

    let historyItem = projectMenu.addItem(withTitle: "Version History...", action: #selector(menuVersionHistory), keyEquivalent: "H")
    historyItem.keyEquivalentModifierMask = [.option]
    projectMenu.addItem(NSMenuItem.separator())

    let freezeItem = projectMenu.addItem(withTitle: "Freeze Selected Tracks", action: #selector(menuFreezeSelectedTracks), keyEquivalent: "F")
    freezeItem.keyEquivalentModifierMask = [.option]
    projectMenu.addItem(NSMenuItem.separator())

    let validateItem = projectMenu.addItem(withTitle: "Validate Project", action: #selector(menuValidateProject), keyEquivalent: "V")
    validateItem.keyEquivalentModifierMask = [.command, .shift]

    projectMenu.addItem(withTitle: "Build Project", action: #selector(menuBuildProject), keyEquivalent: "b")

    projectMenuItem.submenu = projectMenu
    return projectMenuItem
  }

  // MARK: - Studio Menu

  private func buildStudioMenu() -> NSMenuItem {
    let studioMenuItem = NSMenuItem(title: "Studio", action: nil, keyEquivalent: "")
    let studioMenu = NSMenu(title: "Studio")

    let audioSettingsItem = studioMenu.addItem(withTitle: "Audio Settings...", action: #selector(menuAudioSettings), keyEquivalent: "A")
    audioSettingsItem.keyEquivalentModifierMask = [.command, .option]

    let midiSettingsItem = studioMenu.addItem(withTitle: "MIDI Settings...", action: #selector(menuMidiSettings), keyEquivalent: "M")
    midiSettingsItem.keyEquivalentModifierMask = [.command, .option]
    studioMenu.addItem(NSMenuItem.separator())

    let pluginManagerItem = studioMenu.addItem(withTitle: "Plugin Manager...", action: #selector(menuPluginManager), keyEquivalent: "P")
    pluginManagerItem.keyEquivalentModifierMask = [.command, .option]

    let keyboardShortcutsItem = studioMenu.addItem(withTitle: "Keyboard Shortcuts...", action: #selector(menuKeyboardShortcuts), keyEquivalent: "K")
    keyboardShortcutsItem.keyEquivalentModifierMask = [.command, .option]

    studioMenuItem.submenu = studioMenu
    return studioMenuItem
  }

  // MARK: - File Menu Actions

  @objc func menuNewProject() { sendMenuAction("newProject") }
  @objc func menuOpenProject() { sendMenuAction("openProject") }
  @objc func menuSave() { sendMenuAction("save") }
  @objc func menuSaveAs() { sendMenuAction("saveAs") }
  @objc func menuImportJSON() { sendMenuAction("importJSON") }
  @objc func menuExportJSON() { sendMenuAction("exportJSON") }
  @objc func menuImportAudioFolder() { sendMenuAction("importAudioFolder") }
  @objc func menuImportAudioFiles() { sendMenuAction("importAudioFiles") }
  @objc func menuExportAudio() { sendMenuAction("exportAudio") }
  @objc func menuBatchExport() { sendMenuAction("batchExport") }
  @objc func menuExportPresets() { sendMenuAction("exportPresets") }
  @objc func menuBounce() { sendMenuAction("bounce") }
  @objc func menuRenderInPlace() { sendMenuAction("renderInPlace") }

  // MARK: - Edit Menu Actions (handled by Flutter via keyboard shortcuts)

  @objc func menuUndo() { sendMenuAction("undo") }
  @objc func menuRedo() { sendMenuAction("redo") }
  @objc func menuCut() { sendMenuAction("cut") }
  @objc func menuCopy() { sendMenuAction("copy") }
  @objc func menuPaste() { sendMenuAction("paste") }
  @objc func menuDelete() { sendMenuAction("delete") }
  @objc func menuSelectAll() { sendMenuAction("selectAll") }

  // MARK: - View Menu Actions

  @objc func menuToggleLeftPanel() { sendMenuAction("toggleLeftPanel") }
  @objc func menuToggleRightPanel() { sendMenuAction("toggleRightPanel") }
  @objc func menuToggleLowerPanel() { sendMenuAction("toggleLowerPanel") }
  @objc func menuShowAudioPool() { sendMenuAction("showAudioPool") }
  @objc func menuShowMarkers() { sendMenuAction("showMarkers") }
  @objc func menuShowMidiEditor() { sendMenuAction("showMidiEditor") }
  @objc func menuShowLogicalEditor() { sendMenuAction("showLogicalEditor") }
  @objc func menuShowScaleAssistant() { sendMenuAction("showScaleAssistant") }
  @objc func menuShowGrooveQuantize() { sendMenuAction("showGrooveQuantize") }
  @objc func menuShowAudioAlignment() { sendMenuAction("showAudioAlignment") }
  @objc func menuShowTrackVersions() { sendMenuAction("showTrackVersions") }
  @objc func menuShowMacroControls() { sendMenuAction("showMacroControls") }
  @objc func menuShowClipGainEnvelope() { sendMenuAction("showClipGainEnvelope") }
  @objc func menuResetLayout() { sendMenuAction("resetLayout") }

  // MARK: - Project Menu Actions

  @objc func menuProjectSettings() { sendMenuAction("projectSettings") }
  @objc func menuTrackTemplates() { sendMenuAction("trackTemplates") }
  @objc func menuVersionHistory() { sendMenuAction("versionHistory") }
  @objc func menuFreezeSelectedTracks() { sendMenuAction("freezeSelectedTracks") }
  @objc func menuValidateProject() { sendMenuAction("validateProject") }
  @objc func menuBuildProject() { sendMenuAction("buildProject") }

  // MARK: - Studio Menu Actions

  @objc func menuAudioSettings() { sendMenuAction("audioSettings") }
  @objc func menuMidiSettings() { sendMenuAction("midiSettings") }
  @objc func menuPluginManager() { sendMenuAction("pluginManager") }
  @objc func menuKeyboardShortcuts() { sendMenuAction("keyboardShortcuts") }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
