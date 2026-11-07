import Foundation
internal import ArktEngineABI
import EngineAPI

// MARK: - Infobars (#400, contract rule 21)

extension ChromiumEngine {
  /// The facade reports a tab's whole infobar list each time it changes (an infobar added, removed or replaced, or the
  /// whole list again after the tab moved to another window). An infobar keeps its id for as long as the facade keeps
  /// its object; one missing from the list is gone and its id refuses actions. A list for a tab this instance does not
  /// list (another instance's window) is not reported.
  func infobarsChanged(_ event: any ArktEngineEvent) {
    guard let handle = event.tab, let tab = tabByHandle[ObjectIdentifier(handle)], tabs[tab] != nil else { return }
    let reported = (event.infobars ?? []).filter { !$0.isEnded }
    var ids: [InfobarID] = []
    var values: [Infobar] = []
    for infobar in reported {
      let id = infobarIDByHandle[ObjectIdentifier(infobar)] ?? InfobarID()
      infobarHandles[id] = PendingInfobar(id: id, tab: tab, handle: infobar)
      infobarIDByHandle[ObjectIdentifier(infobar)] = id
      ids.append(id)
      values.append(Infobar(id: id, tab: tab, facade: infobar))
    }
    for gone in infobarsByTab[tab] ?? [] where !ids.contains(gone) { forgetInfobar(gone) }
    infobarsByTab[tab] = ids.isEmpty ? nil : ids
    hub.emit(.infobarsChanged(tab, values))
  }

  /// Reports the tab's list empty before its `.tabClosed` (the facade's own list for a closing tab may come after the
  /// close, or not at all), so the shell takes its row down with the tab.
  func endInfobars(of tab: TabID) {
    guard let had = infobarsByTab.removeValue(forKey: tab) else { return }
    for id in had { forgetInfobar(id) }
    hub.emit(.infobarsChanged(tab, []))
  }

  /// The facade runs the infobar's delegate; the delegate decides whether the infobar goes, and the next list says so.
  public func act(on infobar: InfobarID, action: InfobarAction) {
    guard let pending = infobarHandles[infobar] else { return }
    switch action {
    case .ok: _ = pending.handle.act(.ok, linkIndex: 0)
    case .cancel: _ = pending.handle.act(.cancel, linkIndex: 0)
    case .link: _ = pending.handle.act(.link, linkIndex: 0)
    case .messageLink(let index): _ = pending.handle.act(.messageLink, linkIndex: UInt(max(0, index)))
    case .close: _ = pending.handle.act(.close, linkIndex: 0)
    }
  }

  private func forgetInfobar(_ id: InfobarID) {
    guard let pending = infobarHandles.removeValue(forKey: id) else { return }
    infobarIDByHandle[ObjectIdentifier(pending.handle)] = nil
  }
}

extension Infobar {
  init(id: InfobarID, tab: TabID, facade infobar: any ArktInfobar) {
    var links: [InfobarLink] = []
    for (index, value) in infobar.messageLinkRanges.enumerated() {
      let range = value.rangeValue
      if range.location != NSNotFound, range.length > 0 {
        links.append(InfobarLink(index: index, range: range.location..<(range.location + range.length)))
      }
    }
    self.init(
      id: id, tab: tab, kind: InfobarKind(facade: infobar.kind), message: infobar.message, messageLinks: links,
      linkTitle: infobar.linkTitle, linkAccessibilityLabel: infobar.linkAccessibilityLabel,
      linkBeforeButtons: infobar.linkBeforeButtons,
      ok: infobar.okTitle.map { InfobarButton(title: $0, tooltip: infobar.okTooltip, isEnabled: infobar.okEnabled) },
      cancel: infobar.cancelTitle.map {
        InfobarButton(title: $0, tooltip: infobar.cancelTooltip, isEnabled: infobar.cancelEnabled)
      },
      closeLabel: infobar.closeAccessibilityLabel, iconPNG: infobar.iconPNG)
  }
}

extension InfobarKind {
  init(facade kind: ArktInfobarKind) {
    switch kind {
    case .debugger: self = .debugger
    case .automation: self = .automation
    case .reload: self = .reload
    case .other: self = .other
    @unknown default: self = .other
    }
  }
}
