# Page info: turned off in macOS (#786)

The page info panel's Location row when macOS has denied Arkt location access: "Turned off in macOS" under the row's
title, in the panel's secondary text, with the stored setting still in the pop-up. While macOS has not decided, the
row is unchanged.

`shots/` holds offscreen `cacheDisplay` renders of the panel on InMemoryEngine, from a throwaway harness test that is
not committed, drawn at 2x and quantized to 256 colors with `pngquant`. They are not screen captures.

## Location Services off for the whole Mac (#856)

When Location Services is off for the whole Mac, the Location row says "Location Services is off in macOS" instead, so
it reads differently from Arkt's own permission being off. It takes the same place and style, and the pop-up still
shows the stored setting. `services-off-light.png` and `services-off-dark.png` are rendered the same way.
