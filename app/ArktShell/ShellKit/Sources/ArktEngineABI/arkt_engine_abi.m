// SwiftPM needs one source file per C-family target. This one also compiles
// the facade header as Objective-C on every package build; it defines nothing,
// so the target adds no symbols.
#import "arkt_engine.h"
