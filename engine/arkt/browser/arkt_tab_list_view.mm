#import "arkt/browser/arkt_tab_list_view.h"

#include <algorithm>

#import "arkt/browser/arkt_window_host.h"

namespace {

NSString* const kTitleColumn = @"title";

}  // namespace

// One mirrored tab.
@interface ArktTabListRow : NSObject
@property(nonatomic) int32_t tabId;
@property(nonatomic, copy) NSString* title;
@end

@implementation ArktTabListRow
@end

@interface ArktTabListView () <NSTableViewDataSource, NSTableViewDelegate>
@end

@implementation ArktTabListView {
  NSTableView* __strong _tableView;
  NSMutableArray<ArktTabListRow*>* __strong _rows;
  int32_t _activeTabId;
  // True while the table mirrors an event, so the selection change it makes
  // is not reported back as a user choice.
  BOOL _applying;
}

@synthesize tabSelected = _tabSelected;

- (instancetype)initWithFrame:(NSRect)frame {
  if ((self = [super initWithFrame:frame])) {
    _rows = [[NSMutableArray alloc] init];
    _activeTabId = -1;

    _tableView = [[NSTableView alloc] initWithFrame:self.bounds];
    NSTableColumn* column =
        [[NSTableColumn alloc] initWithIdentifier:kTitleColumn];
    column.title = @"Tabs";
    column.resizingMask = NSTableColumnAutoresizingMask;
    [_tableView addTableColumn:column];
    _tableView.headerView = nil;
    _tableView.columnAutoresizingStyle =
        NSTableViewUniformColumnAutoresizingStyle;
    _tableView.allowsEmptySelection = YES;
    _tableView.allowsMultipleSelection = NO;
    _tableView.style = NSTableViewStyleSourceList;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.accessibilityLabel = @"Tabs";
    [column setWidth:NSWidth(self.bounds)];

    self.documentView = _tableView;
    self.hasVerticalScroller = YES;
    self.drawsBackground = NO;
    // Scripts address the table as `table 1 of scroll area "Tabs"`; the web
    // page exposes scroll areas of its own.
    self.accessibilityLabel = @"Tabs";
  }
  return self;
}

- (void)dealloc {
  _tableView.dataSource = nil;
  _tableView.delegate = nil;
}

- (NSTableView*)tableView {
  return _tableView;
}

- (NSInteger)rowForTabId:(int32_t)tabId {
  for (NSUInteger i = 0; i < _rows.count; ++i) {
    if (_rows[i].tabId == tabId) {
      return static_cast<NSInteger>(i);
    }
  }
  return -1;
}

- (void)applyEvent:(ArktTabEvent*)event {
  NSInteger count = static_cast<NSInteger>(_rows.count);
  switch (event.kind) {
    case ArktTabEventKindInserted: {
      ArktTabListRow* row = [[ArktTabListRow alloc] init];
      row.tabId = event.tabId;
      row.title = event.title;
      [_rows insertObject:row
                  atIndex:static_cast<NSUInteger>(
                              std::clamp<NSInteger>(event.index, 0, count))];
      break;
    }
    case ArktTabEventKindRemoved: {
      NSInteger row = [self rowForTabId:event.tabId];
      if (row >= 0) {
        [_rows removeObjectAtIndex:static_cast<NSUInteger>(row)];
      }
      if (event.tabId == _activeTabId) {
        _activeTabId = -1;
      }
      break;
    }
    case ArktTabEventKindMoved: {
      NSInteger from = [self rowForTabId:event.tabId];
      if (from < 0) {
        break;
      }
      ArktTabListRow* row = _rows[static_cast<NSUInteger>(from)];
      [_rows removeObjectAtIndex:static_cast<NSUInteger>(from)];
      [_rows insertObject:row
                  atIndex:static_cast<NSUInteger>(std::clamp<NSInteger>(
                              event.index, 0, count - 1))];
      break;
    }
    case ArktTabEventKindActivated:
      _activeTabId = event.tabId;
      break;
    case ArktTabEventKindUpdated: {
      int32_t lookup =
          event.previousTabId >= 0 ? event.previousTabId : event.tabId;
      NSInteger row = [self rowForTabId:lookup];
      if (row < 0) {
        break;
      }
      _rows[static_cast<NSUInteger>(row)].tabId = event.tabId;
      _rows[static_cast<NSUInteger>(row)].title = event.title;
      if (_activeTabId == lookup) {
        _activeTabId = event.tabId;
      }
      break;
    }
  }
}

- (void)applyEvents:(NSArray<ArktTabEvent*>*)events {
  _applying = YES;
  for (ArktTabEvent* event in events) {
    [self applyEvent:event];
  }
  [_tableView reloadData];
  NSInteger active = [self rowForTabId:_activeTabId];
  if (active >= 0) {
    [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:active]
            byExtendingSelection:NO];
  } else {
    [_tableView deselectAll:nil];
  }
  _applying = NO;
}

// NSTableViewDataSource:

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView {
  return static_cast<NSInteger>(_rows.count);
}

// NSTableViewDelegate:

- (NSView*)tableView:(NSTableView*)tableView
    viewForTableColumn:(NSTableColumn*)tableColumn
                   row:(NSInteger)row {
  NSTextField* cell = [tableView makeViewWithIdentifier:kTitleColumn
                                                  owner:self];
  if (!cell) {
    cell = [NSTextField labelWithString:@""];
    cell.identifier = kTitleColumn;
    cell.lineBreakMode = NSLineBreakByTruncatingTail;
  }
  NSString* title = _rows[static_cast<NSUInteger>(row)].title;
  cell.stringValue = title.length ? title : @"Untitled";
  return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification*)notification {
  if (_applying) {
    return;
  }
  NSInteger row = _tableView.selectedRow;
  if (row < 0 || row >= static_cast<NSInteger>(_rows.count)) {
    return;
  }
  int32_t tabId = _rows[static_cast<NSUInteger>(row)].tabId;
  if (tabId != _activeTabId && _tabSelected) {
    _tabSelected(tabId);
  }
}

@end
