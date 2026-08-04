# Unflatten

Unflatten is a native macOS app for editing text inside flattened screenshots. It uses Apple Vision OCR locally, identifies selectable text lines, reconstructs the background behind an edited line, and renders replacement text at the source image's original pixel dimensions.

## Best-supported images

- Flowcharts and diagrams
- Presentation slides
- Charts with solid label areas
- UI screenshots
- Memes and callouts
- PNG, JPEG, and HEIC images where text sits on a solid or nearly solid background

## Build

Requirements: Xcode 26.6 or another Xcode release with the macOS 14 SDK and SwiftUI, Vision, Core Graphics, Core Text, and XCTest.

```bash
xcodebuild \
  -project Unflatten.xcodeproj \
  -scheme Unflatten \
  -configuration Debug \
  -derivedDataPath /tmp/UnflattenDerived \
  build
```

Open `Unflatten.xcodeproj` in Xcode to run the app.

## Test

```bash
xcodebuild \
  -project Unflatten.xcodeproj \
  -scheme Unflatten \
  -configuration Debug \
  -derivedDataPath /tmp/UnflattenDerived \
  -destination 'platform=macOS' \
  test
```

The suite covers Vision/image/canvas coordinate conversions, letterboxing, background uniformity and outlier resistance, font fitting, PNG encoding, source dimensions, reset behavior, and unchanged pixels outside edit rectangles.

## Basic usage

1. Open, paste, or drop a PNG, JPEG, or HEIC image.
2. Wait for local Vision OCR to outline recognized text lines.
3. To edit existing text, click an outlined line or double-click it to focus the replacement field.
4. To create new text, click **Add Text** in the toolbar, then click where it should appear in the image. The new text is immediately selected for editing and is composited without erasing the background beneath it. Drag its outline to reposition it.
5. Type replacement text and adjust font, size, weight, color, and alignment. Choose a **Text area** mode: **Fixed** shrinks into the original area, **Auto** expands enough to preserve the requested size, and **Custom** lets you choose an intermediate width and height.
6. For photographed paper, gradients, or light textures, choose **Photo-aware** cleanup. For a known solid color, choose **Solid** and optionally enable **Use custom background**.
7. Switch between **Before** and **After**, undo or redo edits, then copy the result or export a PNG.

The imported image is never overwritten. Previews and exports are regenerated from an immutable canonical source buffer and the current edit state.

## Privacy

- OCR and rendering run entirely on the Mac.
- The app makes no network requests and has no network entitlement.
- There are no accounts, analytics, telemetry, ads, or external image uploads.
- Images are not added to a history or retained after the document is replaced or the app quits.
- File access comes only from the standard open/save panels or a user-initiated drag and drop.

## Current limitations

- Photo-aware cleanup reconstructs a text area from nearby pixels and is best suited to paper, gradients, and light textures. Detailed objects, strong edges, and complex scenes can still look imperfect.
- OCR is English-first and exposes one editable textbox for each line recognized by Vision.
- Replacement text is horizontal. Curved, rotated, perspective-distorted, and handwritten text is unsupported.
- Font family, weight, color, alignment, and size are estimates; exact source fonts are not recovered.
- Photo-aware cleanup is deterministic surrounding-pixel reconstruction, not generative inpainting. A true generative model would need to be separately bundled or explicitly connected.
- Imported pixels are normalized once to an 8-bit sRGB premultiplied-RGBA buffer so edits are deterministic and untouched canonical pixels remain exact.
