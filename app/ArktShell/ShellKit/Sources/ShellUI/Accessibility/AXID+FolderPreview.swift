extension AXID {
  /// Folder Preview (#109, BH-093): the list a closed folder shows on hover.
  public enum FolderPreview {
    /// The preview (a group labelled with the folder's title); absent while closed.
    public static let panel = "folderPreview"
    /// The search field: typing selects the first match.
    public static let search = "folderPreview.search"
    /// Label: the tab's title. Selected: the highlighted row.
    public static let row = "folderPreview.row"
  }
}
