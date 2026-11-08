# Shortcut gate boundaries

`ShortcutWiringTests` uses the production app, its Settings window, menu and regular window command target in a
throwaway defaults suite. The in-process menu test constructs and binds its own menu and target; it checks reusable
pieces, not app composition. The UI test covers New Tab only. A full action catalog and all App-only command targets
still need an audit. Keyboard delivery, focus, menu validation and macOS-reserved combinations need a real GUI run;
negative checks use a later ordinary key delivered to a loopback page as an ordered observation before checking
that the command bar remains closed. They do not click, dismiss a panel or start the next positive command between
the tested key and that observation. This bounds the check to delivery through that later event; it does not prove
that no arbitrary future callback can run. The fixture and its synchronization have not yet run in the GUI. Do not
interpret parsing as runtime coverage. The injected system-warning test does not audit the real macOS conflict source. Website priority remains
#441. The earlier Settings design specifies focus on Use and Escape as Keep (`docs/design/settings.md`, lines 238–240).
The later maintainer discussion in PR #828 (comment 6715272110) explicitly leaves the app-shortcut conflict default
unresolved. Initial focus and Return's default action are therefore not asserted or selected by this gate until that
answer arrives. Escape remains an explicit Keep cancellation action; both buttons are exercised directly.
The confirmation described there for Reset All Settings is in Advanced (line 83); no confirmation is specified for
Reset All Shortcuts. Extensions already use Keep Existing for Return; whether app shortcuts share that choice is pending.

The competing Cmd-W and Cmd-1–7 component gate installs the catalog menu temporarily and sends events through
`NSApplication.sendEvent`, with Settings as the key window. It checks captured bindings, pane and window survival
while recording, then the normal pane/close behavior after recording. The conflict explanation is asserted on the
identified message field itself, including the occupied action and binding, rather than matching a shortcut row.
These test-only revisions have been parsed but not compiled or executed; the first missing integration API failure
and the subsequent supported-environment GUI runs are still required.

The editable catalog currently recognizes only `newTab:` and `toggleSidebarVisibility:`. IDs come from those
selectors, not mutable menu titles; the first visible non-alternate occurrence defines each default. Hidden aliases
of a supported selector receive the same binding and are cleared with it. Dynamic Space items, tagged dispatcher
commands and all other menu actions remain read-only until their identities and defaults are audited. The existing
read-only listing and search continue to cover visible keyed menu items independently of this bounded catalog.
Binding a menu applies the model immediately and on subsequent changes; rebinding disconnects the old model. This
component does not install itself into the app or provide Settings controls.
