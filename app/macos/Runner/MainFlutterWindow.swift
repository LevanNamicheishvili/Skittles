import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  // The smallest target is a 13-inch laptop; see docs/decisions.md (D2).
  static let minimumContentSize = NSSize(width: 1280, height: 720)
  static let preferredContentSize = NSSize(width: 1440, height: 900)

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.contentMinSize = MainFlutterWindow.minimumContentSize

    let visible = self.screen?.visibleFrame.size ?? MainFlutterWindow.preferredContentSize
    self.setContentSize(NSSize(
      width: max(MainFlutterWindow.minimumContentSize.width, min(MainFlutterWindow.preferredContentSize.width, visible.width)),
      height: max(MainFlutterWindow.minimumContentSize.height, min(MainFlutterWindow.preferredContentSize.height, visible.height))
    ))
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
