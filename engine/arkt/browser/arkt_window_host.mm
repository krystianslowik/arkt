#import "arkt/browser/arkt_window_host.h"

@implementation ArktTabEvent

@synthesize kind = _kind;
@synthesize tabId = _tabId;
@synthesize index = _index;
@synthesize fromIndex = _fromIndex;
@synthesize previousTabId = _previousTabId;
@synthesize title = _title;
@synthesize url = _url;

- (instancetype)initWithKind:(ArktTabEventKind)kind
                       tabId:(int32_t)tabId
                       index:(NSInteger)index {
  return [self initWithKind:kind
                      tabId:tabId
                      index:index
                  fromIndex:-1
              previousTabId:-1
                      title:nil
                        url:nil];
}

- (instancetype)initWithKind:(ArktTabEventKind)kind
                       tabId:(int32_t)tabId
                       index:(NSInteger)index
                   fromIndex:(NSInteger)fromIndex
               previousTabId:(int32_t)previousTabId
                       title:(NSString*)title
                         url:(NSString*)url {
  if ((self = [super init])) {
    _kind = kind;
    _tabId = tabId;
    _index = index;
    _fromIndex = fromIndex;
    _previousTabId = previousTabId;
    _title = [title copy];
    _url = [url copy];
  }
  return self;
}

- (NSString*)kindName {
  switch (_kind) {
    case ArktTabEventKindInserted:
      return @"inserted";
    case ArktTabEventKindRemoved:
      return @"removed";
    case ArktTabEventKindMoved:
      return @"moved";
    case ArktTabEventKindActivated:
      return @"activated";
    case ArktTabEventKindUpdated:
      return @"updated";
  }
  return @"unknown";
}

@end
