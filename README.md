# Family Growth & Weight Tracker (Flutter + Material 3)

A Flutter application for tracking height and weight across multiple profiles, such as:

- a baby's development timeline
- a parent's weight-loss journey

The app includes:

- Material 3 UI
- multiple profiles
- profile creation with **name, predefined purpose, birth date, weight unit, and height unit**
- age-aware insights (infant/toddler vs adult mode)
- charts for weight and height trends
- measurement history table
- persistent local storage with SQLite (`sqflite`)
- selected profile memory via Shared Preferences
- optional measurement submission (weight-only, height-only, or both)
- hamburger menu profile switcher

## Requirements

- Flutter SDK (3.22+ recommended)
- Dart SDK (bundled with Flutter)

## Run locally

1. Install Flutter: <https://docs.flutter.dev/get-started/install>
2. From this project folder, fetch packages:

   ```bash
   flutter pub get
   ```

3. Run the app:

   ```bash
   flutter run
   ```

## First launch behavior

- The app starts with an **empty database** (no dummy/default data).
- On first launch, you are taken directly to registration to create your first profile.
- Each new profile requires: **name, predefined purpose, birth date**, and supports optional initial weight/height.
- Data is stored locally in SQLite and persists between app restarts.

## Build release artifacts

### Android APK

```bash
flutter build apk --release
```

### iOS (on macOS with Xcode)

```bash
flutter build ios --release
```

## Project structure

- `lib/main.dart`: main app, models, profile management, charts, and entry forms.
- `pubspec.yaml`: dependencies and Flutter configuration.
