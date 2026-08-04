# Unflatten Engineering Guide

## Purpose

Unflatten is a native macOS utility for replacing OCR-detected text in flattened screenshots. It is optimized for diagrams, slides, charts, UI screenshots, memes, and other images with solid or nearly solid backgrounds.

## Repository layout

- `Unflatten/App`: application entry point and commands
- `Unflatten/Models`: immutable source document, text-region, and style state
- `Unflatten/Services`: import, Vision OCR, sampling, rendering, and export
- `Unflatten/Utilities`: coordinate conversion, pixel access, and AppKit bridges
- `Unflatten/Views`: SwiftUI welcome, editor, canvas, and inspector views
- `UnflattenTests`: deterministic unit and export-integrity tests

## Commands

Build:

```bash
xcodebuild -project Unflatten.xcodeproj -scheme Unflatten -configuration Debug -derivedDataPath /tmp/UnflattenDerived build
```

Test:

```bash
xcodebuild -project Unflatten.xcodeproj -scheme Unflatten -configuration Debug -derivedDataPath /tmp/UnflattenDerived -destination 'platform=macOS' test
```

Minimum deployment target: macOS 14.0.

## Invariants

- All OCR and image processing must remain local. Do not add network services, telemetry, or cloud APIs.
- Editing is non-destructive. Never replace or repeatedly render onto the imported source.
- Every preview and export must be rebuilt from the immutable canonical source pixel buffer plus current edit state.
- Pixels outside the union of declared cleanup and expanded drawing rectangles must remain byte-for-byte unchanged in the canonical RGBA representation.
- Complex backgrounds must be handled conservatively: warn and leave the region unchanged until the user opts into a custom background color or photo-aware reconstruction.

## Verification

- Build after changes to project configuration or application code.
- Run the focused tests for coordinate mapping, background sampling, text fitting, and export integrity.
- Before handoff, run the full test command and launch the app with a generated non-private fixture.
- Verify open/paste, OCR alignment, replacement rendering, undo/redo, before/after, copy, and PNG export.
