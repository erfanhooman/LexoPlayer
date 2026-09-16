import Cocoa
import FlutterMacOS
import MediaPlayer

@main
class AppDelegate: FlutterAppDelegate {
  private var methodChannel: FlutterMethodChannel?
  private var openFileChannel: FlutterMethodChannel?

  /// Queue of files delivered by macOS "Open With". Every incoming file is
  /// buffered here so none can be lost, even if the Dart side hasn't finished
  /// launching when the event arrives. The Dart side drains it via
  /// `getInitialFile` (at startup and again when the UI mounts) and live events
  /// are pushed over the `onFileOpened` method.
  private var pendingOpenFiles: [String] = []

  /// Register all channels as early as possible (before the app launches),
  /// so "Open With" events that arrive between `applicationWillFinishLaunching`
  /// and `applicationDidFinishLaunching` are captured reliably.
  override func applicationWillFinishLaunching(_ notification: Notification) {
    setupChannels()
    super.applicationWillFinishLaunching(notification)
    installOpenFileEventHandler()
  }

  /// Registers a direct handler for the `kAEOpenDocuments` Apple Event.
  ///
  /// Whether the app is launched by macOS to open a file (cold start) or an
  /// "Open With" request arrives while the app is already running (warm start),
  /// the open-documents Apple Event is delivered to the process. Depending on
  /// the macOS version it is not always routed to `application(_:openFile:)`,
  /// so handling the event ourselves guarantees the file is always picked up.
  private func installOpenFileEventHandler() {
    NSAppleEventManager.shared().setEventHandler(
      self,
      andSelector: #selector(handleOpenDocumentsEvent(_:withReplyEvent:)),
      forEventClass: AEEventClass(kCoreEventClass),
      andEventID: AEEventID(kAEOpenDocuments)
    )
  }

  @objc private func handleOpenDocumentsEvent(
    _ event: NSAppleEventDescriptor,
    withReplyEvent reply: NSAppleEventDescriptor
  ) {
    guard let direct = event.paramDescriptor(forKeyword: keyDirectObject) else { return }
    guard let list = direct.coerce(toDescriptorType: typeAEList) else { return }
    for index in 1...list.numberOfItems {
      guard let item = list.atIndex(index) else { continue }
      if let path = filePath(from: item), !path.isEmpty {
        enqueueOpenFile(path)
      }
    }
  }

  /// Resolves a file URL, alias, or bookmark descriptor to a filesystem path.
  private func filePath(from descriptor: NSAppleEventDescriptor) -> String? {
    if let url = descriptor.fileURLValue {
      return url.path
    }
    // Fallback: resolve raw bookmark data embedded in a 'bmrk' descriptor.
    let data = descriptor.data
    do {
      let url = try NSURL(
        resolvingBookmarkData: data,
        options: [],
        relativeTo: nil,
        bookmarkDataIsStale: nil
      )
      return url.path
    } catch {
      return nil
    }
  }

  override func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    enqueueOpenFile(filename)
    return true
  }

  override func application(_ sender: NSApplication, openFiles filenames: [String]) {
    for filename in filenames {
      enqueueOpenFile(filename)
    }
  }

  private func enqueueOpenFile(_ filename: String) {
    guard !filename.isEmpty else { return }
    pendingOpenFiles.append(filename)
    // Best-effort live delivery. If the Dart handler isn't registered yet the
    // message is dropped, but the file stays in `pendingOpenFiles` so the Dart
    // side can still pick it up later via `getInitialFile`.
    openFileChannel?.invokeMethod("onFileOpened", arguments: filename)
  }

  private func setupChannels() {
    guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController else {
      return
    }

    methodChannel = FlutterMethodChannel(
      name: "com.lexoplayer/now_playing",
      binaryMessenger: controller.engine.binaryMessenger
    )

    methodChannel?.setMethodCallHandler { [weak self] (call, result) in
      switch call.method {
      case "updateNowPlayingInfo":
        if let args = call.arguments as? [String: Any] {
          self?.updateNowPlayingInfo(args: args)
        }
        result(nil)
      case "clearNowPlayingInfo":
        self?.clearNowPlayingInfo()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    openFileChannel = FlutterMethodChannel(
      name: "com.lexoplayer/open_file",
      binaryMessenger: controller.engine.binaryMessenger
    )

    openFileChannel?.setMethodCallHandler { [weak self] (call, result) in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "getInitialFile":
        if pendingOpenFiles.isEmpty {
          result(nil)
        } else {
          let first = pendingOpenFiles.removeFirst()
          pendingOpenFiles.removeAll(where: { $0 == first })
          result(first)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    // Safety net: if the window wasn't ready during applicationWillFinishLaunching.
    if openFileChannel == nil {
      setupChannels()
    }
    super.applicationDidFinishLaunching(notification)
    setupRemoteCommandCenter()
  }

  private func setupRemoteCommandCenter() {
    let commandCenter = MPRemoteCommandCenter.shared()

    commandCenter.playCommand.isEnabled = true
    commandCenter.playCommand.addTarget { [weak self] _ in
      self?.methodChannel?.invokeMethod("onPlay", arguments: nil)
      return .success
    }

    commandCenter.pauseCommand.isEnabled = true
    commandCenter.pauseCommand.addTarget { [weak self] _ in
      self?.methodChannel?.invokeMethod("onPause", arguments: nil)
      return .success
    }

    commandCenter.togglePlayPauseCommand.isEnabled = true
    commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
      self?.methodChannel?.invokeMethod("onTogglePlayPause", arguments: nil)
      return .success
    }

    commandCenter.nextTrackCommand.isEnabled = true
    commandCenter.nextTrackCommand.addTarget { [weak self] _ in
      self?.methodChannel?.invokeMethod("onNext", arguments: nil)
      return .success
    }

    commandCenter.previousTrackCommand.isEnabled = true
    commandCenter.previousTrackCommand.addTarget { [weak self] _ in
      self?.methodChannel?.invokeMethod("onPrevious", arguments: nil)
      return .success
    }

    commandCenter.changePlaybackPositionCommand.isEnabled = true
    commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
      if let positionEvent = event as? MPChangePlaybackPositionCommandEvent {
        self?.methodChannel?.invokeMethod("onSeek", arguments: ["position": positionEvent.positionTime])
        return .success
      }
      return .commandFailed
    }
  }

  private func updateNowPlayingInfo(args: [String: Any]) {
    var nowPlayingInfo = [String: Any]()

    if let title = args["title"] as? String {
      nowPlayingInfo[MPMediaItemPropertyTitle] = title
    } else {
      nowPlayingInfo[MPMediaItemPropertyTitle] = "LexoPlayer"
    }

    nowPlayingInfo[MPMediaItemPropertyArtist] = "LexoPlayer"

    if let duration = args["duration"] as? Double, duration > 0 {
      nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
    }

    if let position = args["position"] as? Double, position >= 0 {
      nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
    }

    if let isPlaying = args["isPlaying"] as? Bool {
      nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
      
      // Crucial for macOS 10.13+ Control Center & Menu Bar Now Playing Widget to display active playback:
      if #available(macOS 10.13, *) {
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
      }
      
      // Update macOS Dock Tile badge to indicate playing state
      NSApp.dockTile.badgeLabel = isPlaying ? "▶" : nil
    }

    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
  }

  private func clearNowPlayingInfo() {
    if #available(macOS 10.13, *) {
      MPNowPlayingInfoCenter.default().playbackState = .stopped
    }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    NSApp.dockTile.badgeLabel = nil
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      for window in sender.windows {
        window.makeKeyAndOrderFront(self)
      }
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
