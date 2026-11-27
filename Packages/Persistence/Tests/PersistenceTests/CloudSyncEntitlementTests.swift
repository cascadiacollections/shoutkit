import Foundation
@testable import Persistence
import Testing

struct CloudSyncEntitlementTests {
    @Test func `a build that says it was unsigned has no entitlement`() {
        #expect(CloudSyncEntitlement.isPresent(infoDictionaryValue: "NO") == false)
        #expect(CloudSyncEntitlement.isPresent(infoDictionaryValue: " no ") == false)
    }

    @Test func `anything else counts as signed`() {
        #expect(CloudSyncEntitlement.isPresent(infoDictionaryValue: "YES"))
        #expect(CloudSyncEntitlement.isPresent(infoDictionaryValue: ""))
        #expect(CloudSyncEntitlement.isPresent(infoDictionaryValue: "$(CODE_SIGNING_ALLOWED)"))
        #expect(CloudSyncEntitlement.isPresent(infoDictionaryValue: nil))
        #expect(CloudSyncEntitlement.isPresent(infoDictionaryValue: true))
    }

    @Test func `a bundle without the key counts as signed`() {
        #expect(CloudSyncEntitlement.isPresent(in: Bundle(for: BundleToken.self)))
    }
}

private final class BundleToken {}
