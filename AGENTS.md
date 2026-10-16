# Project instructions

## Product and architecture
- Build a premium, minimal, Android-first personal nutrition and exercise tracker with Flutter/Dart. Support light and dark themes.
- Keep core food, weight, workout, and running flows offline-first and available without AI, a subscription, or a network connection. Use SQLite as the local source of truth.
- Organize `lib/` by feature (`dashboard`, `food`, `weight`, `workouts`, `running`, `assistant`, `settings`) with shared app/theme and data layers. Keep widgets focused on presentation; put calculations and persistence behind repositories/services.
- Treat [docs/PRODUCT_SPEC.md](docs/PRODUCT_SPEC.md) as the product source of truth. It is a specification; do not implement application features until requested.
- Use deterministic local calculations and saved nutrition data for meal totals. AI output is a user-reviewed proposal, never authoritative nutrition data.

## Dart and UI conventions
- Follow `analysis_options.yaml` (`flutter_lints`), sound null safety, descriptive names, focused classes, and `const` where practical.
- Use Material 3 with accessible contrast, readable hierarchy, consistent spacing, and Android-native interaction patterns. Respect the user's light/dark/system theme setting.
- Keep units explicit (kcal, g, kg, km, minutes, pace). Make quantities, goals, workouts, and logs editable; do not hard-code derived totals in UI.
- Add focused unit, widget, repository, and flow tests for changed behavior, including offline/error cases.

## Privacy, AI, and security
- Keep personal meals, weight history, exercise plans/logs, and settings on-device by default. No cloud sync, analytics, or background AI calls without a new explicit product decision.
- Voice input means ordinary text fields accept Android keyboard dictation. Do not add a speech-recognition service or call AI to transcribe.
- AI is opt-in and user-triggered through Firebase AI Logic with the Gemini Developer API free tier only, when eligible. Require App Check; do not link billing or use paid services. If eligibility, free quota, or connectivity is unavailable, preserve a manual workflow.
- Never embed a Gemini secret, private API key, token, or signing credential in the app. Do not send full profile or weight history to AI. Show the proposed payload/purpose, label uncertainty, and let users inspect and correct every AI-proposed entry before saving.
- Request platform permissions only for a user-invoked feature, and handle denial gracefully. Keep selected photos transient unless the user chooses to save them.

## Validation
- From the project root (`projects/calorie_tracker/`), run `flutter pub get` after dependency changes, `flutter analyze`, and `flutter test` for code changes.
- Run `flutter build apk --debug` after Android build configuration/plugin changes and before considering Android delivery complete.
- Test persistence across restarts, date boundaries, migrations, offline behavior, export/restore, AI quota/error fallback, and light/dark themes. Android is the supported local target; Xcode/CocoaPods and Chrome are currently unavailable.
