import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Make the title bar transparent and extend content under it
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)
    
    // Allow dragging the window from any empty background area
    self.isMovableByWindowBackground = true

    // Match window background color with the app's premium dark slate color (#121214)
    self.backgroundColor = NSColor(red: 0x12/255.0, green: 0x12/255.0, blue: 0x14/255.0, alpha: 1.0)

    self.minSize = NSSize(width: 360, height: 480)

    super.awakeFromNib()

    // Dispatch frame setting on main thread so it reliably overrides XIB restoration
    DispatchQueue.main.async { [weak self] in
      guard let self = self, let screen = NSScreen.main else { return }
      self.setFrame(screen.visibleFrame, display: true, animate: false)
    }
  }
}
