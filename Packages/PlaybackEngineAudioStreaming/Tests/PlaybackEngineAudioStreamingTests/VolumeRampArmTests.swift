import Foundation
@testable import PlaybackEngineAudioStreaming
import Testing

struct VolumeRampArmTests {
    @Test func `a playing transition fades only after a silence`() {
        var arm = VolumeRampArm()
        #expect(arm.consume() == false)

        arm.arm()
        #expect(arm.consume())
        #expect(arm.consume() == false)
    }

    @Test func `arming again allows one more fade`() {
        var arm = VolumeRampArm()
        arm.arm()
        arm.arm()
        #expect(arm.consume())
        #expect(arm.isArmed == false)
    }
}
