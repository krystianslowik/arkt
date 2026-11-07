import QuartzCore
import Testing
@testable import ShellUI

/// The find bar's motion as data (design/find-in-page/README.md, Motion). It opens from the keyboard, often, so it is
/// short and travels little; closing and stepping do not animate; Reduce Motion keeps the fade and drops the movement.
struct FindBarMotionTests {
  @Test func `the strong ease-out and the system ease-out`() {
    #expect(FindBarMotion.strongEaseOut == FindBarMotion.Curve(0.23, 1, 0.32, 1))
    #expect(FindBarMotion.systemEaseOut == FindBarMotion.Curve(0, 0, 0.58, 1), "CSS ease-out")
  }

  @Test func `opening fades in and settles six points down in 0.12 s on the strong ease-out`() {
    let enter = FindBarMotion.entrance(reduceMotion: false)
    #expect(enter.startOffset == 6, "translateY(-6) in the design is six points above the resting place when y points up")
    #expect(enter.duration == 0.12)
    #expect(enter.curve == FindBarMotion.strongEaseOut)
    #expect(enter.movesInTransform)
  }

  @Test func `Reduce Motion opens with the fade only`() {
    let enter = FindBarMotion.entrance(reduceMotion: true)
    #expect(enter.startOffset == 0)
    #expect(enter.duration == 0.12)
    #expect(enter.curve == FindBarMotion.systemEaseOut)
    #expect(!enter.movesInTransform)
  }

  @Test func `no matches nudges the field 3 points each way in 0.24 s`() throws {
    let nudge = try #require(FindBarMotion.nudge(reduceMotion: false))
    #expect(nudge.duration == 0.24)
    #expect(nudge.keyTimes == [0, 0.2, 0.45, 0.7, 1])
    #expect(nudge.offsets == [0, -3, 3, -2, 0])
    #expect(nudge.curve == FindBarMotion.strongEaseOut, "applied to each step, as CSS keyframes do")
    #expect(nudge.keyTimes.count == nudge.offsets.count)
  }

  @Test func `Reduce Motion does not nudge, the text says it`() {
    #expect(FindBarMotion.nudge(reduceMotion: true) == nil)
  }

  @Test func `a pressed button shrinks to 0.94 in 0.12 s, and not with Reduce Motion`() {
    #expect(FindBarMotion.press(reduceMotion: false) == FindBarMotion.Press(scale: 0.94, duration: 0.12))
    #expect(FindBarMotion.press(reduceMotion: true) == nil)
  }

  @Test func `the animations are made from the data`() throws {
    let enter = FindBarMotion.entrance(reduceMotion: false)
    let fade = FindBarMotion.fadeAnimation(enter)
    #expect(fade.keyPath == "opacity")
    #expect(fade.fromValue as? Double == 0 && fade.toValue as? Double == 1)
    #expect(fade.duration == 0.12)
    let rise = try #require(FindBarMotion.riseAnimation(enter))
    #expect(rise.keyPath == "transform.translation.y")
    #expect(rise.fromValue as? Double == 6 && rise.toValue as? Double == 0)
    #expect(FindBarMotion.riseAnimation(FindBarMotion.entrance(reduceMotion: true)) == nil)

    let nudge = try #require(FindBarMotion.nudge(reduceMotion: false))
    let shake = FindBarMotion.nudgeAnimation(nudge)
    #expect(shake.keyPath == "transform.translation.x")
    #expect(shake.values as? [Double] == [0, -3, 3, -2, 0])
    #expect(shake.keyTimes?.map(\.doubleValue) == [0, 0.2, 0.45, 0.7, 1])
    #expect(shake.timingFunctions?.count == 4, "one curve per step")
    #expect(shake.duration == 0.24)
  }
}
