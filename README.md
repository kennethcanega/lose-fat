# Family Growth & Weight Tracker (Flutter + Material 3)

A Flutter application for tracking height and weight across multiple profiles, such as:

- a baby's development timeline
- a parent's weight-loss journey

The app includes:

- Material 3 UI
- multiple profiles
- profile creation with **name, purpose, age, weight, height**
- age-aware insights (infant/toddler vs adult mode)
- charts for weight and height trends
- measurement history table

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
