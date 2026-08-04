import Cocoa
import FlutterMacOS
import MediaPlayer

@main
class AppDelegate: FlutterAppDelegate {
  private var methodChannel: FlutterMethodChannel?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)

    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
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
    }

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
