# ``ImageIODownsample``

Decode an image at the size you are going to draw it, not the size it was published at.

## Overview

A leaf module — no dependencies, one type — wrapping `CGImageSourceCreateThumbnailAtIndex`.
Station artwork routinely arrives far larger than the row, tile, or Live Activity that renders
it, and decoding at full resolution costs memory proportional to the source pixels rather than
the destination.

```swift
let thumbnail = ImageIODownsampler.decodeCGImage(data, maxPixelSize: 120)
```

``ImageIODownsampler/encode(_:maxPixelSize:outputType:)`` additionally re-encodes, which is what
staging artwork into a shared App Group container for a widget extension needs.

Both entry points return `nil` rather than throwing, and both are gated on
`canImport(ImageIO)`, so the module compiles — as an empty enum — on platforms without it.

## Topics

### Downsampling

- ``ImageIODownsampler``
