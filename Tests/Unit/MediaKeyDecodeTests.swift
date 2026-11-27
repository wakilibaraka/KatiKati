import XCTest
@testable import KatiKati

final class MediaKeyDecodeTests: XCTestCase {
    private func data1(code: Int, state: Int, repeatBit: Bool = false) -> Int {
        (code << 16) | (state << 8) | (repeatBit ? 1 : 0)
    }

    func testDecodesVolumeBrightnessAndIlluminationKeys() {
        let down = MediaKeyDecode.decode(subtype: 8, data1: data1(code: 0, state: 0x0A), modifierFlagsRaw: 0)
        XCTAssertEqual(down, MediaKeyEvent(key: .volumeUp, isKeyDown: true, isRepeat: false, isFineStep: false))

        let upRepeat = MediaKeyDecode.decode(subtype: 8, data1: data1(code: 3, state: 0x0B, repeatBit: true), modifierFlagsRaw: 0)
        XCTAssertEqual(upRepeat, MediaKeyEvent(key: .brightnessDown, isKeyDown: false, isRepeat: true, isFineStep: false))

        let mute = MediaKeyDecode.decode(subtype: 8, data1: data1(code: 7, state: 0x0A), modifierFlagsRaw: 0)
        XCTAssertEqual(mute?.key, .mute)

        let kbd = MediaKeyDecode.decode(subtype: 8, data1: data1(code: 21, state: 0x0A), modifierFlagsRaw: 0)
        XCTAssertEqual(kbd?.key, .illuminationUp)
    }

    func testFineStepRequiresBothOptionAndShift() {
        let optOnly = MediaKeyDecode.decode(subtype: 8, data1: data1(code: 0, state: 0x0A),
                                            modifierFlagsRaw: MediaKeyDecode.alternateFlagMask)
        XCTAssertEqual(optOnly?.isFineStep, false)

        let optShift = MediaKeyDecode.decode(subtype: 8, data1: data1(code: 0, state: 0x0A),
                                             modifierFlagsRaw: MediaKeyDecode.alternateFlagMask | MediaKeyDecode.shiftFlagMask)
        XCTAssertEqual(optShift?.isFineStep, true)
    }

    func testIgnoresNonAuxSubtypeUnknownKeysAndInvalidStates() {
        XCTAssertNil(MediaKeyDecode.decode(subtype: 7, data1: data1(code: 0, state: 0x0A), modifierFlagsRaw: 0))
        XCTAssertNil(MediaKeyDecode.decode(subtype: 8, data1: data1(code: 16, state: 0x0A), modifierFlagsRaw: 0))
        XCTAssertNil(MediaKeyDecode.decode(subtype: 8, data1: data1(code: 0, state: 0x0C), modifierFlagsRaw: 0))
    }

    func testSteppedLevelStandardAndFineClamping() {
        XCTAssertEqual(MediaKeyDecode.stepAmount(fine: false), 1.0 / 16.0, accuracy: 0.0001)
        XCTAssertEqual(MediaKeyDecode.stepAmount(fine: true), 1.0 / 64.0, accuracy: 0.0001)
        XCTAssertEqual(MediaKeyDecode.steppedLevel(current: 0.5, increasing: true, fine: false), 0.5625, accuracy: 0.0001)
        XCTAssertEqual(MediaKeyDecode.steppedLevel(current: 0.02, increasing: false, fine: false), 0.0)
        XCTAssertEqual(MediaKeyDecode.steppedLevel(current: 0.99, increasing: true, fine: false), 1.0)
        XCTAssertEqual(MediaKeyDecode.steppedLevel(current: 0.5, increasing: false, fine: true), 0.5 - 1.0 / 64.0, accuracy: 0.0001)
    }
}
