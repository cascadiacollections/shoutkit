import AVFoundation
import os

/// Something a playback engine hands rendered PCM to: a level meter, a loudness
/// or silence detector, a recorder. The engine owns the tap; plug-ins only see
/// buffers.
///
/// - Important: ``process(_:at:)`` runs on the engine's tap thread, never the
///   main thread, and must not block — the same rules as an
///   `AVAudioNode.installTap` block. Copy what you need out of the buffer; it is
///   not yours after the call returns.
///
/// Class-bound so an engine can remove a plug-in by identity.
public protocol AudioTapPlugin: AnyObject, Sendable {
    func process(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime?)
}

/// The engine side of ``AudioTapPlugin``: a thread-safe set an engine adds and
/// removes plug-ins on from its own isolation, and dispatches to from its tap
/// thread. One engine tap, any number of plug-ins.
///
/// ```swift
/// let taps = AudioTapPluginSet()
/// mixer.installTap(onBus: 0, bufferSize: 1024, format: nil) { [taps] buffer, time in
///     taps.dispatch(buffer, at: time)
/// }
/// ```
public final class AudioTapPluginSet: Sendable {
    private let plugins = OSAllocatedUnfairLock<[any AudioTapPlugin]>(initialState: [])

    public init() {}

    /// Adds `plugin`. Adding one already present does nothing.
    public func add(_ plugin: any AudioTapPlugin) {
        plugins.withLock { plugins in
            guard plugins.contains(where: { $0 === plugin }) == false else { return }
            plugins.append(plugin)
        }
    }

    public func remove(_ plugin: any AudioTapPlugin) {
        plugins.withLock { $0.removeAll { $0 === plugin } }
    }

    public var isEmpty: Bool {
        plugins.withLock { $0.isEmpty }
    }

    public var count: Int {
        plugins.withLock { $0.count }
    }

    /// Hands `buffer` to every plug-in, in the order they were added. The lock is
    /// held only to snapshot the list, never across a plug-in's call, so a
    /// plug-in that adds or removes taps can't deadlock.
    public func dispatch(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime?) {
        for plugin in plugins.withLock({ $0 }) {
            plugin.process(buffer, at: time)
        }
    }
}
