import Foundation
@testable import PlaybackEngineAudioStreaming
import Testing

struct VolumeRampArmTests {
    @Test func `a playing transition fades only after a silence`() {
        var arm = VolumeRampArm()
        #expect(arm.consume() == false)

        arm.arm()
        let faded = arm.consume()
        let fadedAgain = arm.consume()
        #expect(faded)
        #expect(fadedAgain == false)
    }

    @Test func `arming again allows one more fade`() {
        var arm = VolumeRampArm()
        arm.arm()
        arm.arm()
        let faded = arm.consume()
        #expect(faded)
        #expect(arm.isArmed == false)
    }
}
