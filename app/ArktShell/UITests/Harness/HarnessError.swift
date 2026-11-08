/// A harness precondition that failed before or around a launch.
struct HarnessError: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}
