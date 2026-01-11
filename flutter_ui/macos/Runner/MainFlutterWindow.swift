import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Maximize window to fill screen (not fullscreen mode, just maximized)
    if let screen = NSScreen.main {
      let visibleFrame = screen.visibleFrame
      self.setFrame(visibleFrame, display: true)
    }

    // Enable fullscreen button
    self.collectionBehavior = [.fullScreenPrimary]

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Register native file picker channel
    let channel = FlutterMethodChannel(
      name: "reelforge/file_picker",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )

    channel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "pickAudioFiles":
        self.pickAudioFiles(result: result)
      case "pickAudioFolder":
        self.pickAudioFolder(result: result)
      case "pickJsonFile":
        self.pickJsonFile(result: result)
      case "saveFile":
        if let args = call.arguments as? [String: Any],
           let suggestedName = args["suggestedName"] as? String,
           let fileType = args["fileType"] as? String {
          self.saveFile(suggestedName: suggestedName, fileType: fileType, result: result)
        } else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing arguments", details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }

  private func pickAudioFiles(result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      let panel = NSOpenPanel()
      panel.allowsMultipleSelection = true
      panel.canChooseDirectories = false
      panel.canChooseFiles = true
      panel.title = "Import Audio Files"

      if #available(macOS 11.0, *) {
        panel.allowedContentTypes = [
          UTType.audio,
          UTType.wav,
          UTType.mp3,
          UTType.aiff,
          UTType(filenameExtension: "flac") ?? UTType.audio,
          UTType(filenameExtension: "ogg") ?? UTType.audio,
          UTType(filenameExtension: "m4a") ?? UTType.audio,
        ]
      } else {
        panel.allowedFileTypes = ["wav", "mp3", "aiff", "flac", "ogg", "m4a", "aac"]
      }

      panel.begin { response in
        if response == .OK {
          let paths = panel.urls.map { $0.path }
          result(paths)
        } else {
          result(nil)
        }
      }
    }
  }

  private func pickAudioFolder(result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      let panel = NSOpenPanel()
      panel.allowsMultipleSelection = false
      panel.canChooseDirectories = true
      panel.canChooseFiles = false
      panel.title = "Import Audio Folder"

      panel.begin { response in
        if response == .OK, let url = panel.url {
          result(url.path)
        } else {
          result(nil)
        }
      }
    }
  }

  private func pickJsonFile(result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      let panel = NSOpenPanel()
      panel.allowsMultipleSelection = false
      panel.canChooseDirectories = false
      panel.canChooseFiles = true
      panel.title = "Open Project"

      if #available(macOS 11.0, *) {
        panel.allowedContentTypes = [UTType.json]
      } else {
        panel.allowedFileTypes = ["json"]
      }

      panel.begin { response in
        if response == .OK, let url = panel.url {
          result(url.path)
        } else {
          result(nil)
        }
      }
    }
  }

  private func saveFile(suggestedName: String, fileType: String, result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      let panel = NSSavePanel()
      panel.nameFieldStringValue = suggestedName
      panel.title = "Save Project"

      if #available(macOS 11.0, *) {
        if fileType == "json" {
          panel.allowedContentTypes = [UTType.json]
        }
      } else {
        panel.allowedFileTypes = [fileType]
      }

      panel.begin { response in
        if response == .OK, let url = panel.url {
          result(url.path)
        } else {
          result(nil)
        }
      }
    }
  }
}
