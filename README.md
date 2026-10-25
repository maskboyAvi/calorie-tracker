# NutriTrack

Simple tracking. Healthier days.

An offline-first personal Android app for food and nutrition logging, weight trends, workouts, and running. Food, weight, goals, and activity records are stored in a local SQLite database. Optional AI analysis is explicitly user-triggered; manual logging works without Firebase, network access, an API key, or a subscription.

## Run and validate

```sh
flutter pub get
flutter analyze
flutter test
flutter run
```

Build a debug APK:

```sh
flutter build apk --debug
```

The APK is written to `build/app/outputs/flutter-apk/app-debug.apk`.

## Gemini AI setup

AI requests use the API key entered by the user in **Settings → AI Setup**, sent directly to Google Gemini over HTTPS. Flash-Lite is the default model, and the model can be changed there. Create a key at https://aistudio.google.com/apikey. The key is saved using encrypted platform storage on that installation. Google receives only content submitted for an explicit analysis. Usage and free-tier availability depend on the user's Google AI Studio project and model. Manual food logging works offline without a key.

Firebase AI Logic and App Check debug-token registration are not used by this app. Never commit or log a user's API key.
