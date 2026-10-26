import Testing
@testable import Motion

/// `SpringField`: one interruptible spring per key, on a clock passed in (#109 folder motion).
struct SpringFieldTests {
  private let firm = SpringPreset.firm.parameters

  @Test func aNewKeyStartsWhereItIsToldAndSettlesAtItsTarget() throws {
    var field = SpringField<Int>()
    field.retarget(1, to: 1, from: 0, at: 0, parameters: firm)
    #expect(field.value(of: 1, at: 0) == 0)
    let middle = try #require(field.value(of: 1, at: 0.1))
    #expect(middle > 0 && middle < 1)
    #expect(field.value(of: 1, at: 5) == 1)
    #expect(field.settledKeys(at: 5) == [1])
    #expect(field.settledKeys(at: 0.05).isEmpty)
  }

  /// Retargeting mid-flight continues from the current value and velocity, never from the start value.
  @Test func retargetingKeepsTheCurrentValueAndVelocity() throws {
    var field = SpringField<Int>()
    field.retarget(7, to: 1, from: 0, at: 0, parameters: firm)
    let t = 0.08
    let value = try #require(field.value(of: 7, at: t))
    let velocity = field.velocity(of: 7, at: t)
    #expect(velocity > 0)
    field.retarget(7, to: 0, from: 1, at: t, parameters: firm)   // `from` is ignored for a running key
    #expect(abs(try #require(field.value(of: 7, at: t)) - value) < 1e-9)
    #expect(abs(field.velocity(of: 7, at: t) - velocity) < 1e-6, "the reversal carries the velocity over")
    #expect(field.value(of: 7, at: 5) == 0)
  }

  @Test func removeAndTargetsAreReported() {
    var field = SpringField<String>()
    field.retarget("a", to: 0, from: 1, at: 0, parameters: firm)
    #expect(field.target(of: "a") == 0)
    #expect(field.keys == ["a"])
    field.remove("a")
    #expect(field.keys.isEmpty)
    #expect(field.target(of: "a") == nil)
  }
}
