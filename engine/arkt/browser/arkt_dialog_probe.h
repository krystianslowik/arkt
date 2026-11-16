#ifndef ARKT_BROWSER_ARKT_DIALOG_PROBE_H_
#define ARKT_BROWSER_ARKT_DIALOG_PROBE_H_

namespace base {
class FilePath;
}

namespace content {
class WebContents;
}

namespace arkt {

// Self-test only (#586), for the facade's self-test commands: where tab-modal
// dialogs and the file chooser show on an Arkt window. Each logs what it did
// with an "ARKT selftest" prefix.

// Leaves `count` test confirm infobars on `contents` (removes the earlier
// test ones first). They do not expire on navigation.
void SetTestInfobarsForSelfTest(content::WebContents* contents, int count);

// #478: adds (`add` true) or removes a stand-in for an infobar with Views of
// its own and no confirm delegate, under the sign-in QR code infobar's
// identifier, so the presenter's not-drawn path runs on a live tab. The real
// sign-in QR infobar only appears on Chromium's sign-in page with a hybrid
// passkey transport, which a self-test cannot reach.
void SetNonConfirmInfobarForSelfTest(content::WebContents* contents, bool add);

// Shows a Chromium tab-modal dialog on `contents` the way the extension
// dialogs do (constrained_window::ShowWebModal of a ui::DialogModel).
void ShowTabModalForSelfTest(content::WebContents* contents);

// Logs the tab's infobar rows, the top of its page view and every child
// window and sheet of its window, in screen points, and whether each child
// window's top is at or below the page's top (that is, below the rows).
void LogDialogGeometryForSelfTest(content::WebContents* contents);

// The folder a file chooser of `contents`' profile opens in when the page
// names none (Profile::last_selected_directory).
void SetFileChooserFolderForSelfTest(content::WebContents* contents,
                                     const base::FilePath& folder);

// Logs every open or save panel of the app: its parent window, whether it is
// a sheet of the tab's window, and the folder it shows; then cancels it.
// Every open or save panel in the process is cancelled, not only the tab's:
// use it only in a self-test run with no other panel up.
void CheckFilePanelsForSelfTest(content::WebContents* contents);

}  // namespace arkt

#endif  // ARKT_BROWSER_ARKT_DIALOG_PROBE_H_
