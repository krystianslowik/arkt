import ArcProbe
import Foundation

// Counts-only probe of an Arc profile root, for the maintainer to run on their own Mac (#504).
// Copies the database files it needs into a temporary folder and reads the copies; never writes to Arc's folders,
// never touches the Keychain, and prints only counts, schema versions and schema key names.
//
// Usage: arkt-arc-probe [profile-root]
// Default root: ~/Library/Application Support/Arc/User Data

let root = CommandLine.arguments.count > 1
  ? URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
  : ArcProbe.defaultRoot()

do {
  for line in try ArcProbe.report(root: root) { print(line) }
} catch {
  // Only the error's type and code: descriptions can quote paths or stored values.
  print("error: \(type(of: error)) code \((error as NSError).code)")
  exit(1)
}
