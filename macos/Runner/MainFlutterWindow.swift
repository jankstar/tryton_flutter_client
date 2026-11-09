import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    // Size and position of the window are kept by macOS (user defaults
    // `NSWindow Frame TrytonMainWindow`): restored at the start, saved on
    // every change; the first start uses the frame of MainMenu.xib.
    let autosaveName = "TrytonMainWindow"
    if !self.setFrameUsingName(autosaveName) {
      self.setFrame(windowFrame, display: true)
    }
    self.setFrameAutosaveName(autosaveName)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
