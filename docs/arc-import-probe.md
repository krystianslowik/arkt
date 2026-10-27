# Arc profile probe

`arkt-arc-probe` is a counts-only check of an Arc profile, written for the Arc import (#131). It tells us the shape
of a real profile (schema versions, row counts, where the auto-archive thresholds live) without reading or printing
any content. It exists so the import readers (#506 to #510) and the threshold mapping (#516) are built against real
schemas.

## What it does and does not do

- It copies the files it needs (`History`, `Login Data`, `Cookies` or `Network/Cookies`, `Web Data`, each with its
  `-wal` and `-shm`) into a temporary folder, reads the copies, and deletes the folder when it ends.
- It never writes to Arc's folders and never touches the Keychain, so macOS shows no Keychain prompt.
- It prints only counts, numeric schema versions and schema key names. No URL, title, name, cookie value, password,
  extension id or path is printed. Folder names other than `Default` and `Profile N` are shown as `other-N`.
- Auto-archive keys: it lists key names that contain "archive" in `Local State`, each profile's `Preferences` and
  `StorableSidebar.json`, with the value only when it is a number (booleans show as `bool`).

## Run it

Quit Arc first, so the copies are a consistent snapshot, then from a clone of this repository:

```zsh
cd app/ArktCore && swift run arkt-arc-probe
```

The default root is `~/Library/Application Support/Arc/User Data`. To point it at another root, pass it as the
only argument: `swift run arkt-arc-probe /path/to/User\ Data`. `StorableSidebar.json` is read from the folder above
the root (Arc's own folder) or from the root itself.

## Output

```text
arkt-arc-probe: counts only, no content
profiles found: 2
profile Default
  History: schema version N, compatible N, urls N, visits N
  Login Data: schema version N, compatible N, logins N
  Cookies: schema version N, compatible N, cookies N
  Web Data: schema version N, compatible N
  Bookmarks: bookmark_bar urls N folders N; other urls N folders N; synced urls N folders N
  Extensions: N (location 1: N, location 4: N)
StorableSidebar.json: present, version N, containers N, spaces N (undecodable N), items N (undecodable N), ...
StorableArchiveItems.json: present, version N, items N
archive threshold keys (key names only, numeric values only):
  Default/Preferences: some.key (86400)
```

`Extensions` counts ids in `extensions.settings` of `Preferences` and `Secure Preferences`, grouped by Chromium's
install location number (1 internal, 4 unpacked, 5 component, and so on). `absent` means the file does not exist;
`unreadable` means the table is missing or unreadable in that schema.

## Maintainer step

Paste the full output as a comment on #504. It contains only the counts above, so it is safe to post. The issue
closes when the output is posted and recorded.
