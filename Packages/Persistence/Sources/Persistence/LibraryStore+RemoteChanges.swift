import CoreData
import Foundation

public extension LibraryStore {
    /// Brings this store's own state in line after rows arrive from another
    /// device: merges stations that are now duplicated and reloads
    /// ``favoriteIDs``, which is a cache the import does not touch.
    func reconcileAfterRemoteChange() {
        mergeDuplicateStations()
        reloadFavoriteIDs()
    }

    /// Calls ``reconcileAfterRemoteChange()`` whenever the persistent store
    /// reports a change made outside this process. Only a container opened
    /// with iCloud sync produces such changes, so starting this without sync
    /// costs nothing.
    ///
    /// - Returns: The observer token. The observation lasts until it is passed
    ///   to `NotificationCenter.removeObserver(_:)`; the app never does.
    @discardableResult
    func observeRemoteChanges(in center: NotificationCenter = .default) -> any NSObjectProtocol {
        // `queue: .main` is what makes `MainActor.assumeIsolated` safe below.
        center.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reconcileAfterRemoteChange()
            }
        }
    }
}
