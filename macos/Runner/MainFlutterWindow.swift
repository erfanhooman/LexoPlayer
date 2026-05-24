import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Make the title bar transparent and extend content under it
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)
    
    // Allow dragging the window from any empty background area
    self.isMovableByWindowBackground = true

    // Match window background color with the app's premium dark slate color (#121214)
    self.backgroundColor = NSColor(red: 0x12/255.0, green: 0x12/255.0, blue: 0x14/255.0, alpha: 1.0)

    super.awakeFromNib()
  }
}
