import Foundation
import Testing

/// The Distribution configuration (#334): the engine-backed shell app without test-only code. Its bundle links no
/// `EngineAPITestSupport` (so no contract runner), compiles the `ARKT_*` environment overrides and the test switches
/// out, writes the product `CrProductDirName` and is named Arkt. Reads the committed files only, like the other
/// isolation tests.
struct DistributionConfigurationTests {
  static let spec = WebKitIsolationTests.projectSpec
  static let appRoot = WebKitIsolationTests.appRoot

  static func projectSpec() throws -> String { try String(contentsOf: spec, encoding: .utf8) }

  static func text(_ path: String) throws -> String {
    try String(contentsOf: appRoot.appending(path: path), encoding: .utf8)
  }

  /// The compilation conditions the Distribution build sets: its own `SWIFT_ACTIVE_COMPILATION_CONDITIONS` on top of a
  /// release configuration, which defines none (`DEBUG` only comes with a debug configuration).
  static func distributionConditions(in spec: String) -> Set<String> {
    let lines = ChromiumEngineKitIsolationTests.settingLines("SWIFT_ACTIVE_COMPILATION_CONDITIONS", in: spec)
    let own = lines.filter { $0.configuration == "Distribution" }.flatMap { $0.value.trimmingCharacters(in: CharacterSet(charactersIn: "\"")).split(separator: " ") }
    return Set(own.map(String.init)).subtracting(["$(inherited)"])
  }

  /// The conditions the Engine build sets: `DEBUG` is not among them (XcodeGen only adds it to the configuration named
  /// Debug), so the Engine app's overrides come from `ARKT_TEST_SWITCHES`.
  static func engineConditions(in spec: String) -> Set<String> {
    let lines = ChromiumEngineKitIsolationTests.settingLines("SWIFT_ACTIVE_COMPILATION_CONDITIONS", in: spec)
    let own = lines.filter { $0.configuration == "Engine" }
      .flatMap { $0.value.trimmingCharacters(in: CharacterSet(charactersIn: "\"")).split(separator: " ") }
    return Set(own.map(String.init)).subtracting(["$(inherited)"])
  }

  // MARK: - Configuration shape

  @Test func distributionIsAnOptimizedReleaseConfigurationAndEngineStaysDebug() throws {
    let spec = try Self.projectSpec()
    let lines = Set(spec.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) })
    #expect(lines.contains("Distribution: release"), "Distribution must be a release-type configuration")
    #expect(lines.contains("Engine: debug"), "Engine must stay the unoptimized development configuration")
    #expect(lines.contains("Release: release"))
    #expect(lines.contains("Debug: debug"))
  }

  @Test func distributionBuildsTheEngineApp() throws {
    let spec = try Self.projectSpec()
    let conditions = Self.distributionConditions(in: spec)
    #expect(conditions.contains("ARKT_CHROMIUM_ENGINE"), "conditions: \(conditions.sorted())")
    let principal = ChromiumEngineKitIsolationTests.settingLines("ARKT_PRINCIPAL_CLASS", in: spec)
      .filter { $0.configuration == "Distribution" }
    #expect(principal.map(\.value) == ["BrowserCrApplication"])
  }

  // MARK: - No test-only code

  @Test func distributionCompilesNoDebugOrSmokeConditions() throws {
    let conditions = Self.distributionConditions(in: try Self.projectSpec())
    #expect(conditions.isDisjoint(with: ["DEBUG", "ARKT_SMOKE_BUILD", "ARKT_TEST_SWITCHES"]), "conditions: \(conditions.sorted())")
  }

  @Test func onlyTheEngineConfigurationSetsTheTestSwitchesCondition() throws {
    let lines = ChromiumEngineKitIsolationTests.settingLines("SWIFT_ACTIVE_COMPILATION_CONDITIONS", in: try Self.projectSpec())
    let setters = lines.filter { $0.value.contains("ARKT_TEST_SWITCHES") }.map(\.configuration)
    #expect(setters == ["Engine"], "ARKT_TEST_SWITCHES set by: \(setters)")
  }

  @Test func distributionHasEnvironmentOverridesOff() throws {
    let spec = try Self.projectSpec()
    let values = ChromiumEngineKitIsolationTests.settingLines("ARKT_ENV_OVERRIDES", in: spec)
    #expect(values.contains { $0.configuration == "base" && $0.value == "\"NO\"" }, "base default must be NO")
    #expect(!values.contains { $0.configuration == "Distribution" }, "Distribution must inherit ARKT_ENV_OVERRIDES=NO")
    #expect(Set(values.filter { $0.value == "\"YES\"" }.compactMap(\.configuration)) == ["Debug", "Profile", "Engine"])
    #expect(spec.contains("ArktEnvironmentOverrides: $(ARKT_ENV_OVERRIDES)"))
  }

  @Test func distributionLinksNoTestSupport() throws {
    let spec = try Self.projectSpec()
    let flags = ChromiumEngineKitIsolationTests.settingLines("OTHER_LDFLAGS", in: spec)
    let distribution = flags.filter { $0.configuration == "Distribution" }
    #expect(distribution.count == 1, "Distribution must set OTHER_LDFLAGS once")
    for flag in distribution {
      #expect(flag.value.contains("$(BUILT_PRODUCTS_DIR)/ChromiumEngineKit.o"), "the engine kit must be linked")
      #expect(!flag.value.contains("EngineAPITestSupport"), "test support linked into Distribution: \(flag.value)")
    }
    for product in ChromiumEngineKitIsolationTests.packageDependencies(in: spec) where product.product == "EngineAPITestSupport" {
      #expect(!product.linked, "EngineAPITestSupport must stay link: false")
    }
  }

  // MARK: - Identity

  @Test func distributionProductIsNamedArkt() throws {
    let spec = try Self.projectSpec()
    let names = ChromiumEngineKitIsolationTests.settingLines("PRODUCT_NAME", in: spec)
    #expect(names.contains { $0.configuration == "base" && $0.value == "ArktShell" })
    #expect(names.filter { $0.configuration == "Distribution" }.map(\.value) == ["Arkt"])
  }

  @Test func distributionWritesTheProductDataFolderName() throws {
    let spec = try Self.projectSpec()
    #expect(spec.contains("Distribution: Distribution.xcconfig"), "Distribution needs its own configuration file")
    let xcconfig = try Self.text("Distribution.xcconfig")
    #expect(ProductIdentityTests.setting("ARKT_PRODUCT_DIR_NAME", in: xcconfig) == "Arkt/Engine")
    #expect(xcconfig.contains("ARKT_ENGINE_APP ="), "ARKT_ENGINE_APP is declared")
    #expect(!xcconfig.contains("Arkt Dev Engine"))
    // The development value stays with the Engine configuration.
    let engine = try Self.text("Engine.xcconfig")
    #expect(ProductIdentityTests.setting("ARKT_PRODUCT_DIR_NAME", in: engine) == "Arkt Dev Engine")
  }

  @Test func theEmbedPhaseRunsForEngineAndDistribution() throws {
    let spec = try Self.projectSpec()
    #expect(spec.contains("[[ $CONFIGURATION == Engine || $CONFIGURATION == Distribution ]] || exit 0"))
    #expect(!spec.contains("[[ $CONFIGURATION == Engine ]]"))
  }

  // MARK: - Overrides and test switches are compiled out

  /// Source lines of `App/` that read an `ARKT_*` override, parse a test switch or reach the contract runner, with the
  /// `#if` conditions that guard them.
  static func guardedTestLines() throws -> [(file: String, line: Int, text: String, active: (Set<String>) -> Bool)] {
    let root = appRoot.appending(path: "App")
    let files = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
    var found: [(String, Int, String, (Set<String>) -> Bool)] = []
    for case let url as URL in files where url.pathExtension == "swift" {
      let source = try String(contentsOf: url, encoding: .utf8)
      let relative = WebKitIsolationTests.relativeComponents(url).joined(separator: "/")
      var scanner = ConditionalScanner()
      for (index, raw) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if scanner.consume(line) { continue }
        guard !line.hasPrefix("//"), isTestOnly(line) else { continue }
        let guards = scanner.guards
        found.append((relative, index + 1, line, { flags in guards.allSatisfy { $0(flags) } }))
      }
      #expect(scanner.guards.isEmpty, "\(relative) has an unbalanced #if")
    }
    return found
  }

  /// A line that exists only for tests: an `ARKT_` key in a string, a `--arkt-engine-` switch, the contract runner
  /// or its page server, or an import of the shared contract.
  static func isTestOnly(_ line: String) -> Bool {
    line.contains("\"ARKT_") || line.contains("\"--arkt") || line.contains("EngineContractRunner")
      || line.contains("ContractPageServer") || line.contains("import EngineAPITestSupport")
      || line.contains("EnvironmentOverrides(") || line.contains("StandInShell") || line.contains("ReentrancyProbe")
      || (line.contains("CommandLine.arguments") && !line.contains(allowedArgumentsRead))
  }

  /// The one read of the process arguments Distribution keeps: the engine launch, which passes them on (URLs and
  /// Chromium's own switches) after `EngineLaunchArguments.strippingTestSwitches` removed the `--arkt-*` ones.
  static let allowedArgumentsRead = "strippingTestSwitches(CommandLine.arguments)"

  @Test func overridesAndTestSwitchesAreCompiledOutOfDistribution() throws {
    let conditions = Self.distributionConditions(in: try Self.projectSpec())
    let lines = try Self.guardedTestLines()
    let live = lines.filter { $0.active(conditions) }.map { "\($0.file):\($0.line): \($0.text)" }
    #expect(live.isEmpty, "compiled into Distribution (conditions \(conditions.sorted())): \(live)")
  }

  /// Not vacuous: the scan sees the overrides and the contract runner, and the Engine configuration (a debug build
  /// of the same engine app) still compiles them.
  @Test func engineConfigurationStillCompilesThemIn() throws {
    let lines = try Self.guardedTestLines()
    let engineFlags = Self.engineConditions(in: try Self.projectSpec())
    let active = lines.filter { $0.active(engineFlags) }
    let files = Set(active.map(\.file))
    #expect(files.contains("App/AppEnvironment.swift"), "\(files.sorted())")
    #expect(files.contains("App/EnvironmentOverrides.swift"))
    #expect(files.contains("App/Engine/EngineContractRunner.swift"))
    #expect(files.contains("App/Engine/ChromiumShell.swift"))
    #expect(lines.contains { $0.text.contains("\"ARKT_DATA_DIR\"") })
  }

  @Test func theEngineLaunchStripsTestSwitchesInDistribution() throws {
    let main = try Self.text("App/Engine/EngineMain.swift")
    #expect(main.contains(Self.allowedArgumentsRead))
  }

  @Test func contractRunnerAndProbeFilesAreEngineAndTestSwitchesOnly() throws {
    for name in ["EngineContractRunner", "ContractPageServer", "StandInShell", "ReentrancyProbe"] {
      let source = try Self.text("App/Engine/\(name).swift")
      let first = source.split(separator: "\n").first.map(String.init)
      #expect(first == "#if ARKT_CHROMIUM_ENGINE && ARKT_TEST_SWITCHES", "\(name).swift starts with \(first ?? "nothing")")
    }
  }
}

// MARK: - Conditional compilation

/// Tracks the `#if` blocks of a Swift file line by line, enough to tell which compilation conditions guard a line.
struct ConditionalScanner {
  private struct Block {
    var branches: [(Set<String>) -> Bool]
    var isElse = false
  }
  private var blocks: [Block] = []

  /// The condition of every open branch, innermost last; a line compiles when all hold. An `#elseif` or `#else`
  /// branch also requires every earlier branch of its block to be off.
  var guards: [(Set<String>) -> Bool] {
    blocks.map { block in
      let branches = block.branches
      return { flags in
        for branch in branches.dropLast() where branch(flags) { return false }
        return block.isElse ? true : (branches.last?(flags) ?? true)
      }
    }
  }

  /// True when `line` is a conditional directive (and updates the state).
  mutating func consume(_ line: String) -> Bool {
    if line.hasPrefix("#if ") {
      blocks.append(Block(branches: [ConditionParser.parse(String(line.dropFirst(4)))]))
      return true
    }
    if line.hasPrefix("#elseif "), !blocks.isEmpty {
      blocks[blocks.count - 1].branches.append(ConditionParser.parse(String(line.dropFirst(8))))
      return true
    }
    if line == "#else", !blocks.isEmpty {
      blocks[blocks.count - 1].branches.append { _ in true }
      blocks[blocks.count - 1].isElse = true
      return true
    }
    if line == "#endif", !blocks.isEmpty {
      blocks.removeLast()
      return true
    }
    return false
  }
}

/// Parses a `#if` condition: identifiers, `!`, `&&`, `||` and parentheses. Anything else (`os(macOS)`, `canImport`)
/// counts as off, which is right for the flags this project sets.
enum ConditionParser {
  static func parse(_ source: String) -> (Set<String>) -> Bool {
    var tokens = tokenize(source)[...]
    let expression = parseOr(&tokens)
    return expression
  }

  private static func tokenize(_ source: String) -> [String] {
    var tokens: [String] = []
    var word = ""
    func flush() { if !word.isEmpty { tokens.append(word); word = "" } }
    let characters = Array(source.split(separator: "//", maxSplits: 1, omittingEmptySubsequences: false)[0])
    var index = 0
    while index < characters.count {
      let character = characters[index]
      if character.isLetter || character.isNumber || character == "_" || character == "." {
        word.append(character)
      } else if character == "&" || character == "|", index + 1 < characters.count, characters[index + 1] == character {
        flush()
        tokens.append(String([character, character]))
        index += 1
      } else if character == "!" || character == "(" || character == ")" {
        flush()
        tokens.append(String(character))
      } else {
        flush()
      }
      index += 1
    }
    flush()
    return tokens
  }

  private static func parseOr(_ tokens: inout ArraySlice<String>) -> (Set<String>) -> Bool {
    var terms = [parseAnd(&tokens)]
    while tokens.first == "||" {
      tokens.removeFirst()
      terms.append(parseAnd(&tokens))
    }
    return { flags in terms.contains { $0(flags) } }
  }

  private static func parseAnd(_ tokens: inout ArraySlice<String>) -> (Set<String>) -> Bool {
    var factors = [parseNot(&tokens)]
    while tokens.first == "&&" {
      tokens.removeFirst()
      factors.append(parseNot(&tokens))
    }
    return { flags in factors.allSatisfy { $0(flags) } }
  }

  private static func parseNot(_ tokens: inout ArraySlice<String>) -> (Set<String>) -> Bool {
    guard let token = tokens.popFirst() else { return { _ in false } }
    switch token {
    case "!":
      let inner = parseNot(&tokens)
      return { !inner($0) }
    case "(":
      let inner = parseOr(&tokens)
      if tokens.first == ")" { tokens.removeFirst() }
      return inner
    default:
      return { $0.contains(token) }
    }
  }
}

struct ConditionParserTests {
  @Test func conditionsAreEvaluatedAgainstTheFlags() {
    let condition = ConditionParser.parse("DEBUG || ARKT_SMOKE_BUILD")
    #expect(condition(["DEBUG"]))
    #expect(!condition(["ARKT_CHROMIUM_ENGINE"]))
    #expect(ConditionParser.parse("ARKT_CHROMIUM_ENGINE && DEBUG")(["ARKT_CHROMIUM_ENGINE", "DEBUG"]))
    #expect(!ConditionParser.parse("ARKT_CHROMIUM_ENGINE && DEBUG")(["ARKT_CHROMIUM_ENGINE"]))
    #expect(ConditionParser.parse("!DEBUG && (A || B)")(["B"]))
    #expect(!ConditionParser.parse("!DEBUG && (A || B)")(["B", "DEBUG"]))
    #expect(!ConditionParser.parse("os(macOS)")([]))
  }

  @Test func elseBranchesAreOffWhenAnEarlierBranchIsOn() {
    var scanner = ConditionalScanner()
    let openedIf = scanner.consume("#if A")
    let openedElseIf = scanner.consume("#elseif B")
    let guardsOfB = scanner.guards
    let openedElse = scanner.consume("#else")
    let guardsOfElse = scanner.guards
    let closed = scanner.consume("#endif")
    func compiles(_ guards: [(Set<String>) -> Bool], _ flags: Set<String>) -> Bool { guards.allSatisfy { $0(flags) } }
    #expect(openedIf && openedElseIf && openedElse && closed)
    #expect(compiles(guardsOfB, ["B"]) && !compiles(guardsOfB, ["A", "B"]))
    #expect(compiles(guardsOfElse, []) && !compiles(guardsOfElse, ["A"]) && !compiles(guardsOfElse, ["B"]))
    #expect(scanner.guards.isEmpty)
  }
}
