# Shortcut gate boundaries

`ShortcutWiringTests` uses the production app, its Settings window, menu and regular window command target in a
throwaway defaults suite. The in-process menu test constructs and binds its own menu and target; it checks reusable
pieces, not app composition. The UI test covers New Tab only. A full action catalog and all App-only command targets
still need an audit. Keyboard delivery, focus, menu validation and macOS-reserved combinations need a real GUI run;
negative checks use a later ordinary key delivered to a loopback page as an ordered observation before checking
that the command bar remains closed. They do not click, dismiss a panel or start the next positive command between
the tested key and that observation. This bounds the check to delivery through that later event; it does not prove
that no arbitrary future callback can run. The fixture and its synchronization have not yet run in the GUI. Do not
interpret parsing as runtime coverage. The injected system-warning test does not audit the real macOS conflict source. App shortcuts take priority over page shortcuts until RT-29/#78; per-action priority remains #441. The maintainer
[decided](https://github.com/krystianslowik/arkt/pull/828#issuecomment-6721408776) that app-shortcut conflicts
default to Keep Existing on Return, as extension shortcuts do. The Settings test now asserts initial Keep focus and
Return preserving both bindings; that new assertion has not been run. Escape also keeps both bindings, and Use
Shortcut must be explicit.
The confirmation described there for Reset All Settings is in Advanced (line 83); no confirmation is specified for
Reset All Shortcuts. Extensions already use Keep Existing for Return.

The competing Cmd-W and Cmd-1–7 component gate installs the catalog menu temporarily and sends events through
`NSApplication.sendEvent`, with Settings as the key window. It checks captured bindings, pane and window survival
while recording, then the normal pane/close behavior after recording. The conflict explanation is asserted on the
identified message field itself, including the occupied action and binding, rather than matching a shortcut row.
These test-only revisions have been parsed but not compiled or executed; the first missing integration API failure
and the subsequent supported-environment GUI runs are still required.

The initial editable catalog recognized `newTab:` and `toggleSidebarVisibility:`. IDs come from those
selectors, not mutable menu titles; the first visible non-alternate occurrence defines each default. Hidden aliases
of a supported selector receive the same binding and are cleared with it. Dynamic Space items, tagged dispatcher
commands and other unaudited menu actions remain read-only. The existing
read-only listing and search continue to cover visible keyed menu items independently of this bounded catalog.
Binding a menu applies the model immediately and on subsequent changes; rebinding disconnects the old model. This
component does not install itself into the app or provide Settings controls.

The catalog additionally supports the four distinct responder-chain selectors `copyCurrentURL:`,
`copyCurrentURLAsMarkdown:`, `copyCurrentURLAsQuote:` and `pasteURLAsNewTab:`. Their defaults are read from the
pristine menu items, not a second defaults table. The component test recreates the production menu entries; it does
not compile `MainMenu` or prove actual app dispatch.

Remaining read-only scope: `commandDispatch:` carries the EngineCommand tag for Save Page As, Print, Find/Next/
Previous, Stop, Reload/Force Reload, Actual Size/Zoom In/Out, View Source, Developer Tools, Inspect Elements,
JavaScript Console, Back, Forward, Show All History and Downloads; a selector alone conflates these rows. The
numbered `goToSpace:` rows use changing Space order and tags, `goToSidebarItem:` rows 1–9 use tags, and
`focusSplitPane:` rows 1–4 use tags. Their identity and persistence across dynamic rebuilds need separate design.
Next Tab and Previous Tab each have a visible arrow binding and a hidden, separately keyed brace alias; collapsing
both to one binding would erase an existing default. Other selector-based App, File, Edit, View, Spaces, Tabs,
Window and Help commands remain read-only pending their own identity, alias and routing audit. Visible keyed rows
remain listed by the existing read-only sections; unbound and hidden rows are not shown there.

The Settings component now provides the six audited recorder controls through the injected editor; AppSession and
MainMenu composition remains a later stage. CI run 42481041992 at `993a386` failed all five recorder scenarios on
the missing sidebar control, and the competing-key scenario also failed its initial key-window assertion. The
latter remains an independent setup/focus question. The new Return assertion was not reached. New-head GUI CI is
needed for the implemented controls and native event routing; source parsing does not establish either.
