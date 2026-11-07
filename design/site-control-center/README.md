# Site Control Center design

The Site Control Center (#651): one popover per site from the address pill, the page info panel grown into one
scrolling list. Prototype: [`prototype.html`](prototype.html), states `#<default|insecure|long|file|reset|changed>`,
each with `[&dark][&rm][&shot]`. Screens: `screens/site-control-center-<state>-<light|dark>.png` (2x). Hosts are
synthetic; `long` is a punycode host with 10 permissions and a large data count.

**This extends the page info panel (#582, `design/extensions` `surf-pageinfo`).** Same anchor (below the address
pill), same 330 pt width, same header and permission pop-ups; it adds Auto Picture in Picture, the data summary,
Reset site and Site Settings. One panel, not two. Picked over B (tiles and a drill-in) and C (tabs).

Everyday chrome. Changes apply at once, so there is no Save or Done pill and no mustard in the panel. Switches are
graphite when on (porcelain in dark), as in `design/settings`. The only primary is the existing reload infobar's
Reload (`changed`), raised when a change needs a reload.

## Layout

| Part | Value |
|---|---|
| Panel | 330 pt wide, radius 12, `surfaceBrand`, `overlayShadow`; anchored 12 pt from the sidebar's leading edge, below the address pill |
| Height | 300 to 552 pt, then the list scrolls with a 12 pt fade at the bottom edge |
| Header | 30 pt badge (radius 8, `sidebarItemBackground`) with the site glyph; host 13 semibold (truncates in the middle); connection line 12 secondary with a lock or warning glyph; padding 12 / 14 / 10 |
| Sections | 1 pt `sidebarDivider` above each; section title 11 semibold secondary |
| Rows | 32 pt, padding 0 / 14, 16 pt glyph in `sidebarForeground`, label, trailing control |
| Site section | Auto Picture in Picture (switch, 32 x 20); Cookies and site data (count and size, chevron, opens the data sheet) |
| Permissions | every permission with a 22 pt pop-up (Allow, Ask, Block), radius 6, `sidebarItemHovered` |
| Footer | 1 pt divider above; quiet buttons "Reset site" (leading) and "Site Settings..." (trailing) |

## States

| State | What it shows |
|---|---|
| `default` | host, "Connection is secure", Auto Picture in Picture on, data summary, four permissions |
| `insecure` | "Not secure: this site has no encrypted connection" in primary text with a warning glyph (never red) |
| `long` | a long punycode host truncated; 10 permissions; the list scrolls past 552 pt with the bottom fade |
| `file` | a local file: "Local files have no site settings." and nothing else; internal pages open nothing (the pill is inert) |
| `reset` | Reset site asks once: "Reset settings for fieldguide.example?" |
| `changed` | after a change that needs a reload: the reload infobar on the card, Reload as the one primary pill |

## Behavior

- Opens on a click on the lock or site glyph in the address pill. Esc or a click outside closes it.
- Keyboard shortcut: none yet. The proposed Cmd-Option-I is already Developer Tools (`MainMenu.swift`), so it is not
  used; the panel opens from the address pill and through VoiceOver until a free shortcut is chosen.
- Every change persists per host at once.
- Reset site asks for confirmation: an alert over the panel, title "Reset settings for fieldguide.example?", body
  "Permissions and Auto Picture in Picture go back to their defaults. Cookies and site data stay.", buttons Cancel and
  Reset. Reset is a neutral pill with a red title and has no Return key (as Clear Archive and Delete Space); Esc
  cancels.
- Site Settings opens Settings > Sites filtered to the host.

## Motion

| Moment | Motion | Reduce Motion |
|---|---|---|
| Open | opacity 0 to 1, scale 0.97 to 1, translateY -4 to 0, 0.22 s `firmFast` (the extensions panel values) | opacity only, 0.15 s |
| Reset confirmation | the alert fades in over 0.15 s with a dimmed panel behind it | same |
| Switch | the system switch animation | same |

## VoiceOver and keyboard

- The panel is a dialog "Site controls for fieldguide.example".
- Rows read "Camera, Block, pop-up button" and "Auto Picture in Picture, on, switch".
- Tab moves through the controls; focus starts on the first control.
- The confirmation is an alert dialog "Reset settings for fieldguide.example?"; focus starts on Cancel.
- Increase Contrast adds the 1 pt `increasedContrastEdge` to pop-ups and the panel edge.

## Answered questions

1. Direction: A, page info grown.
2. Keyboard shortcut: the proposed Cmd-Option-I collides with Developer Tools, so the panel ships without a shortcut
   until a free one is picked.
3. Reset site asks for confirmation: yes, as drawn in `reset`.
