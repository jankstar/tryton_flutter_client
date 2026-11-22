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

    // Minimum size of the window's content: the tabs keep 360 px beside
    // the narrowest menu (160 px, `MenuWidthNotifier.minWidth`); forms are
    // laid out down to 320 px. Narrower windows overflowed the form grid.
    let minimum = NSSize(width: 540, height: 400)
    self.contentMinSize = minimum
    // a smaller frame saved before the minimum existed is enlarged
    let content = self.contentRect(forFrameRect: self.frame)
    if content.width < minimum.width || content.height < minimum.height {
      var frame = self.frame
      frame.size = self.frameRect(forContentRect: NSRect(
        origin: .zero,
        size: NSSize(width: max(content.width, minimum.width),
                     height: max(content.height, minimum.height)))).size
      self.setFrame(frame, display: true)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
