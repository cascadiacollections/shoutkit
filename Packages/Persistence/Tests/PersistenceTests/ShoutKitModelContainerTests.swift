import SwiftData
import Testing

@testable import Persistence

@MainActor
struct ShoutKitModelContainerTests {
    private enum FixtureError: Error {
        case openFailed
    }

    @Test func persistentStoreSuccessKeepsAvailabilityTrue() {
        var openCalls = 0

        _ = ShoutKitModelContainer.makeContainer(inMemory: true) { configuration in
            openCalls += 1
            return try ModelContainer(for: ShoutKitModelContainer.schema, configurations: [configuration])
        }

        #expect(openCalls == 1)
        #expect(ShoutKitModelContainer.isPersistentStoreAvailable)
    }

    @Test func persistentStoreFailureRetriesOnceBeforeSuccess() {
        var openCalls = 0

        _ = ShoutKitModelContainer.makeContainer(inMemory: false) { configuration in
            openCalls += 1
            if openCalls == 1 {
                throw FixtureError.openFailed
            }
            return try ModelContainer(for: ShoutKitModelContainer.schema, configurations: [configuration])
        }

        #expect(openCalls == 2)
        #expect(ShoutKitModelContainer.isPersistentStoreAvailable)
    }

    @Test func persistentStoreFailureFallsBackToInMemoryAndMarksUnavailable() throws {
        var openCalls = 0

        let container = ShoutKitModelContainer.makeContainer(inMemory: false) { _ in
            openCalls += 1
            throw FixtureError.openFailed
        }

        #expect(openCalls == 2)
        #expect(ShoutKitModelContainer.isPersistentStoreAvailable == false)

        let context = ModelContext(container)
        context.insert(FavoriteStation(stationID: "fallback", name: "Fallback", genre: "Test"))
        try context.save()
    }
}
