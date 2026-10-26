// Space theme creator identifiers (#410). Kept beside `AXID.swift` like the other feature files; no imports.
extension AXID {
  /// The Space theme creator popover (`ThemeCreatorView`).
  public enum ThemeCreator {
    /// The popover. Role dialog, label "Space Theme", title: the Space name.
    public static let popover = "themeCreator.popover"
    /// The colour pad, a group labelled "Colour".
    public static let pad = "themeCreator.pad"
    /// A colour dot, adjustable. Label "Colour 1" or "Colour 2"; value a colour name and tone.
    public static let dot = "themeCreator.dot"
    /// The colour-count button: "Add a second colour" or "Use one colour".
    public static let colourCount = "themeCreator.colourCount"
    /// The texture radio group.
    public static let textures = "themeCreator.textures"
    /// One texture swatch, a radio button labelled None, Grain, Sand, Denim or Tweed.
    public static let texture = "themeCreator.texture"
    /// The texture amount slider; disabled with None.
    public static let amount = "themeCreator.amount"
    /// The opacity slider.
    public static let opacity = "themeCreator.opacity"
  }
}
