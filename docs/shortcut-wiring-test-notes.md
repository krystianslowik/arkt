# Shortcut gate boundaries

`ShortcutWiringTests` uses the production app, its Settings window, menu and regular window command target in a
throwaway defaults suite. The in-process menu test constructs and binds its own menu and target; it checks reusable
pieces, not app composition. The UI test covers New Tab only. A full action catalog and all App-only command targets
still need an audit. Keyboard delivery, focus, menu validation and macOS-reserved combinations need a real GUI run;
the immediate negative checks cannot prove that a delayed event never arrives. Do not interpret parsing as runtime
coverage. The injected system-warning test does not audit the real macOS conflict source. Website priority remains
#441. The earlier Settings design specifies focus on Use and Escape as Keep (`docs/design/settings.md`, lines 238–240).
The later maintainer discussion in PR #828 (comment 6715272110) explicitly leaves the app-shortcut conflict default
unresolved. Initial focus and Return's default action are therefore not asserted or selected by this gate until that
answer arrives. Escape remains an explicit Keep cancellation action; both buttons are exercised directly.
The confirmation described there for Reset All Settings is in Advanced (line 83); no confirmation is specified for
Reset All Shortcuts. Extensions already use Keep Existing for Return; whether app shortcuts share that choice is pending.
