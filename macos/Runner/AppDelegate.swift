import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// "About Tryton Flutter Client" of the app menu (MainMenu.xib): the
  /// Flutter dialog instead of the standard panel (channel tryton/app_menu).
  @IBAction func showAboutPanel(_ sender: Any?) {
    guard let controller = mainFlutterWindow?.contentViewController
      as? FlutterViewController else { return }
    FlutterMethodChannel(
      name: "tryton/app_menu", binaryMessenger: controller.engine.binaryMessenger
    ).invokeMethod("about", arguments: nil)
  }
}
