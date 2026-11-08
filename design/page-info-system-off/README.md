# Page info: turned off in macOS (#786)

The page info panel's Location row when macOS has denied Arkt location access: "Turned off in macOS" under the row's
title, in the panel's secondary text, with the stored setting still in the pop-up. While macOS has not decided, the
row is unchanged.

`shots/` holds offscreen `cacheDisplay` renders of the panel from the GUI test harness on InMemoryEngine, drawn at 2x
and quantized to 256 colors with `pngquant`. They are not screen captures.
