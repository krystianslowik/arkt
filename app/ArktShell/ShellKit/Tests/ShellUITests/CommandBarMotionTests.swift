import QuartzCore
import Testing
@testable import ShellUI

/// The bar's appear and dismiss fades as data (design/command-bar/README.md, Motion): a fade only, no scale, 0.1 s out;
/// Reduce Motion keeps them (it drops movement, and a fade is not movement).
struct CommandBarMotionTests {
  @Test func `appearing is a fade with no movement`() {
    let enter = CommandBarMotion.appear
    #expect(enter.fromOpacity == 0 && enter.toOpacity == 1)
    #expect(enter.duration == 0.1)
    #expect(enter.curve == CommandBarMotion.Curve(0.23, 1, 0.32, 1), "the strong ease-out")
  }

  @Test func `dismissing fades out in 0.1 s`() {
    let exit = CommandBarMotion.dismiss
    #expect(exit.fromOpacity == 1 && exit.toOpacity == 0)
    #expect(exit.duration == 0.1)
  }

  @Test func `the animations are made from the data, on opacity only`() {
    let fade = CommandBarMotion.animation(CommandBarMotion.appear)
    #expect(fade.keyPath == "opacity")
    #expect(fade.fromValue as? Float == 0 && fade.toValue as? Float == 1)
    #expect(fade.duration == 0.1)
    var points = [Float](repeating: 0, count: 4)
    for index in 1...2 {                                   // the curve's two control points
      var point: [Float] = [0, 0]
      fade.timingFunction?.getControlPoint(at: index, values: &point)
      points[(index - 1) * 2] = point[0]
      points[(index - 1) * 2 + 1] = point[1]
    }
    #expect(points == [0.23, 1, 0.32, 1])
    #expect(fade.isRemovedOnCompletion)
    let out = CommandBarMotion.animation(CommandBarMotion.dismiss)
    #expect(out.fromValue as? Float == 1 && out.toValue as? Float == 0)
  }

  @Test func `Reduce Motion keeps both fades`() {
    #expect(CommandBarMotion.entrance(reduceMotion: true) == CommandBarMotion.appear)
    #expect(CommandBarMotion.exit(reduceMotion: true) == CommandBarMotion.dismiss)
    #expect(CommandBarMotion.entrance(reduceMotion: false) == CommandBarMotion.appear)
  }
}
