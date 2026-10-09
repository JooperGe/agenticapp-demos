# Urbanrun

Urbanrun is a desktop-first isometric exploration demo built with Flutter and Flame. Move a runner through a small procedural street, enter the coffee shop and convenience store, and complete the two-location exploration objective.

## Resolved toolchain

- Flutter 3.47.6 (stable, revision `5fc346839b`)
- Dart 3.13.5
- Flame 1.38.2 (resolved by `pubspec.lock`)

## Run locally

```bash
flutter pub get
flutter run -d macos
```

The primary target is macOS desktop. Other Flutter desktop targets may work, but are not part of this demo's acceptance scope.

## Verify

```bash
flutter test
flutter analyze
```

## Controls

- `WASD` or arrow keys: move
- `Shift`: run
- `E`: interact near a cyan entrance prompt
- Click the on-screen `E` prompt: perform the same interaction and return focus to keyboard movement

The HUD shows the current scene, a procedural minimap, exploration progress, and short-lived transition feedback. It does not display fake currency, stamina, or controls without behavior.

## Visual scope

The demo is desktop-first and responsive at common 16:10 window sizes, including 960x600 and 1440x900. HUD surfaces use translucent deep navy, warm off-white, cyan highlights, and rounded panels. The minimap is generated from the scene model and player ground coordinates; indoor scenes use their local interior bounds rather than a street position.

All world art and minimap marks are procedural Flutter/Flame drawing. No external art, image, font, or network resource is required or included. This is an intentional limitation of the demo rather than a claim of production-ready art direction.
