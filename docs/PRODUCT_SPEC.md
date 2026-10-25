# Product specification: Personal nutrition and activity tracker

**Status:** Product specification for the implemented local-first Android app; Firebase AI integration is optional and requires project-side App Check setup.
**Target:** Personal Android app built with Flutter and Dart.
**Product principles:** Premium minimal UI; local-first data; user control; deterministic nutrition totals; optional and explicitly invoked AI.

## 1. Product goals and non-goals

The app helps one person record food, nutrition, weight, gym sessions, and running; see progress; and optionally ask an AI assistant for meal interpretation or nutrition review. All core functions must work without a network, account, AI service, API key, or subscription. Records remain on the device unless the user explicitly exports them or submits selected content to an AI feature.

The app is not a medical device, a social network, an automatic activity tracker, or a source of medical advice. It does not sync to a cloud account. AI does not silently record meals, prescribe diets, or determine authoritative nutrition totals.

## 2. Navigation and screen-by-screen UX

Use a Material 3 Android shell with four primary destinations: **Today**, **Food**, **Activity**, and **Progress**. Settings and data management open from the app bar/profile control. Keep a consistent date selector, clear empty states, accessible labels, and a prominent add action. Support system, light, and dark theme selection.

### 2.1 First launch and goals

- Explain local storage and optional AI data sharing in plain language; no account creation.
- Seed editable goals: 2,100 kcal/day, 150 g protein/day, target weight range 77–78 kg.
- Ask for optional preferred units and theme. Do not collect unnecessary profile fields.
- Make clear that goals are user-entered guidance and can be changed later.
- AI remains disabled until the user opens Assistant settings and enables it. Enabling AI is not required for app use.

### 2.2 Today dashboard

- Default to the current local calendar day; allow browsing prior/future dates.
- Show energy eaten, remaining relative to the daily target, and macro totals (protein, carbohydrate, fat), with clear units and progress indicators.
- Show meals grouped by user-configurable meal labels (initially breakfast, lunch, dinner, snack); entries can be edited, duplicated, or deleted.
- Show today's weight if entered and a compact activity summary for planned/completed workout and run.
- Add food opens local search/manual entry; shortcuts open weight, workout completion, and run logging.
- Empty states explain the next action; zero entries are valid and never imply missing network data.

### 2.3 Food search and food detail

- Search the built-in/local catalog and user-created foods first. Matching is offline and must not invoke AI.
- Include a starter catalog of common Indian foods (e.g. dal, roti/chapati, rice, idli, dosa, paneer, curd, poha, upma, chole, common vegetables), with source and serving assumptions documented in the catalog. Values are estimates where recipes vary.
- Search results show food name, serving, kcal, and macro summary. Filters may include recent, saved, and catalog foods.
- Food detail lets the user choose/edit serving amount and unit, inspect nutrition, choose meal/date/time, and save to the log. Support gram and household servings where defined. Scale all nutrients deterministically from the base serving.
- Manual custom-food entry captures name, serving size/unit, kcal, protein, carbohydrate, fat, optional fiber, and notes/source. Validate non-negative finite values and allow later editing.
- If local search has no suitable match, offer manual food creation and a separate explicit **Estimate with AI** action if AI is enabled. Clearly distinguish estimates from verified catalog entries.

### 2.4 Meal log, recipes, and saved meals

- A logged entry records a nutrition snapshot so later catalog edits do not rewrite history. Quantity is editable; totals recalculate from the snapshot.
- Users can create custom recipes from ingredients and quantities, review summed per-serving nutrition and number of servings, then save. Recipe calculation uses local ingredient data only.
- Users can save a selection of foods/recipe as a reusable meal and add it later with editable quantities.
- Editing a past log changes only that log. Deleting requires a clear undo/confirmation affordance.
- Meal descriptions may be typed or dictated using the Android keyboard's built-in voice typing in a normal text field. Dictation text remains in the field until the user submits it. No speech API is used.

### 2.5 Weight history

- Quick entry records weight, date/time, and optional note; support kg and lb with canonical storage in kg.
- Display entries in reverse chronological order; edit/delete entries. Permit at most one primary measurement per timestamp, but allow multiple measurements on a day if the user chooses.
- Show the latest value, change over a selected period, target range, and seven-day average. Define the seven-day average as the arithmetic mean of available recorded daily values in the trailing seven local calendar days; do not fabricate missing days.
- Weight charts provide useful ranges (week, month, 3 months, year, all) and accessible values/labels. Empty and sparse data states remain legible.

### 2.6 Activity overview and weekly workout planner

- Activity screen shows a week selector and a seven-day plan with workout sessions and running sessions.
- Create/edit/reorder a gym workout template or scheduled session, assign it to a date/day, and optionally repeat it weekly.
- Each gym session contains ordered exercises. Exercise fields include name, optional notes, and one or more sets with target reps and optional target weight. Use kg/lb display conversion with canonical kg storage.
- During a session, mark each set complete and optionally record actual reps/weight; mark the session complete or abandoned. Progress is saved locally as the user works, and can be edited later.
- Exercise library starts with a small editable local set of common movements and permits custom exercises. No network is required.

### 2.7 Running schedule and logs

- Schedule runs by date with optional distance/time/pace goal and notes. Distance and duration goals are independently optional.
- Record a run manually: date/time, distance, duration, optional notes, and optional perceived effort. Calculate pace locally from distance and duration, with explicit unit (min/km or min/mi).
- Show scheduled versus completed runs, completion status, and goal comparison. Permit edit/delete; no GPS tracking or location permission in initial scope.
- A run can be logged without a prior scheduled plan.

### 2.8 Progress

- Provide date range controls and charts/cards for weight and seven-day average, calorie intake versus goal, macro trends, run distance/time/pace, and workout completion.
- All summaries derive from local records with documented date inclusion rules. Missing data is shown as missing, not zero.
- Charts provide accessible textual summaries and do not imply medical conclusions.

### 2.9 Optional nutrition assistant

- An assistant screen explains that submitted text/images go to Google's Gemini service through Firebase AI Logic and can be inaccurate. AI is disabled by default and can be disabled at any time.
- AI actions are explicit: (1) identify food and estimate portion from a user-selected photo, optionally combined with context text; (2) interpret a typed or Android-keyboard-dictated meal description with no image; (3) estimate an unknown food; (4) extract nutrition from a user-selected label photo; (5) review nutrition using only user-selected meal/day data.
- No AI request occurs during ordinary food searches when a local match exists. No background or automatic calls.
- Show the input and intended request before submission, then show structured proposals with uncertainty/source labels. The user can edit or reject every proposed food, portion, macro value, and meal before a normal local save. AI output alone never changes the database.
- Nutrition review must use only a user-selected scope and show exactly which fields will be sent. Do not send weight history or full profile. Ask explicit per-request approval before sending meal/day content.
- If offline, disabled, blocked by App Check, or out of quota, explain the failure and preserve manual entry without losing the draft.
- **Photo plus context logging flow:** The user takes a photo or selects one from the gallery. An optional ordinary text field accepts context about ingredients, quantities, cooking method, oil/ghee, serving size, or corrections. The user may type or use the Android keyboard's built-in microphone to dictate into that field. Dictated text is just field content: do not add a speech-recognition API, paid transcription service, or dedicated speech-to-text plugin. When the user taps **Analyze**, submit the selected image and context text together in the same Firebase AI Logic Gemini request. Show proposed foods, portions, estimates, and uncertainty for user review/editing before saving. Preserve text-only logging when no image is attached; the same explicit Analyze action submits text only.
- Photo capture/picker is user initiated. Keep the image transient and discard after request unless the user separately chooses to retain it as an attachment. Do not send the photo or its context before Analyze, and do not silently reuse either in another request.

### 2.10 Settings, export, and restore

- Edit calorie, protein, carbohydrate/fat (when set), and target-weight goals; theme; units; meal labels; and AI enablement. Do not add an application-owned AI request counter or daily cap; Firebase provider quotas and errors are authoritative.
- Never auto-retry an AI request. Explain provider quota failures and preserve manual logging.
- Export all local records and preferences to a versioned JSON backup via Android's document picker/share mechanism. Clearly state that exported files are unencrypted unless encryption is selected; do not upload automatically.
- Restore from a user-selected backup with schema validation, preview, and explicit replace/merge choice. Preserve a rollback copy until restore succeeds. Define duplicate handling by stable IDs.
- Provide delete-all-data with a clear confirmation and completion state.

## 3. Data model proposal

Use SQLite with foreign keys, transactions, schema versioning, and migrations. IDs are stable UUIDs. Store date-only keys in local `YYYY-MM-DD` form for daily aggregation; store instants as UTC epoch or ISO-8601 UTC plus the relevant local date key. Document timezone behavior and test daylight-saving/date-boundary cases. Store canonical units and convert only at presentation/input boundaries.

| Entity | Important fields and relationships |
|---|---|
| `Food` | id, name, normalized search name, category, source/notes, base serving quantity/unit, kcal, protein_g, carbs_g, fat_g, optional fiber_g, created/updated timestamps, built-in flag |
| `FoodLogEntry` | id, local_date, consumed_at, meal_label, food_id nullable, food_name_snapshot, original AI/manual baseline quantity and unit, original total kcal/macros for that baseline, current quantity and unit, derived current total, optional printed-label reference basis/values, confidence/source/assumptions, note, created/updated timestamps |
| `Recipe` | id, name, servings, notes, timestamps; related `RecipeIngredient` rows with food/recipe reference, quantity, unit, nutrition snapshot |
| `SavedMeal` | id, name, timestamps; related ordered `SavedMealItem` rows referencing food/recipe and default quantity plus nutrition snapshot |
| `WeightEntry` | id, local_date, measured_at, weight_kg, note, created/updated timestamps |
| `GoalSettings` | id/singleton, kcal/day, protein_g/day, optional carbs_g/fat_g targets, target_weight_min_kg/max_kg, effective date, updated timestamp |
| `Exercise` | id, name, muscle/group tags, instructions/notes, built-in flag, timestamps |
| `WorkoutTemplate` | id, name, notes, timestamps; ordered `WorkoutTemplateExercise` and target `WorkoutTemplateSet` rows |
| `WorkoutSession` | id, template_id nullable, scheduled date/time, status, started/completed timestamps, note; related session exercises/sets preserving planned and actual name/order/reps/weight/completion |
| `RunPlan` | id, scheduled date/time, optional distance_km, duration_seconds, pace_seconds_per_km, notes, status |
| `RunLog` | id, run_plan_id nullable, started_at/local_date, distance_km, duration_seconds, computed pace (derived preferred), notes, perceived effort |
| `AppSettings` | theme, display units, meal labels, AI enabled flag, timestamps |

Nutrition source/confidence is metadata. Totals are calculated from saved base values and quantities locally, not from AI or cached dashboard values. Use decimal-safe representation (e.g. integer milli-units or SQLite REAL with rounding policy) and specify rounding for displayed kcal/macros.

## 4. Architecture and dependencies

Proposed layering: `presentation` (screens/widgets), feature state/controllers, domain models/use cases, repositories, SQLite/local asset data source, and a narrowly scoped AI gateway. Features depend on repository interfaces. Domain calculations should be pure Dart and independent of Flutter and network SDKs. Keep Android-specific photo selection and keyboard behavior behind platform plugins where needed. The food-analysis input model should carry an optional image and optional context text; the AI gateway must serialize both as parts of one model request when both are present, or send text-only when the image is absent. Invoke it only from the explicit Analyze action.

Proposed dependencies (verify current stable compatible versions when implementation is approved):

- `sqflite` + `path`: SQLite persistence and database path.
- `flutter_riverpod`: feature state and dependency injection; alternatively choose a simpler state approach if complexity does not justify it.
- `fl_chart`: weight/nutrition/activity charts, with accessible text summaries.
- `image_picker`: user-initiated photo capture/selection for AI workflows; no location/audio-record permission.
- `firebase_core`, `firebase_ai`, `firebase_app_check`: optional Firebase AI Logic integration and App Check. Configure Gemini Developer API provider only; do not embed a Gemini API key. Use Android Play Integrity in production and App Check debug provider only in local development.
- `firebase_options.dart` holds the Android Firebase client configuration matching `android/app/google-services.json`; the Google Services Gradle plugin processes that file. AI initializes with the Gemini Developer API backend (`FirebaseAI.googleAI()`), not Agent Platform/Vertex AI.
- `file_picker` or Android Storage Access Framework integration: explicit backup import/export; choose one implementation after compatibility review.
- `uuid` if platform-independent UUID generation is not otherwise available.
- `flutter_test` and optionally `mocktail` for unit/widget/repository tests.

Keep Firebase initialization and AI integration isolated so the app can start and all non-AI features operate without Firebase configuration/network. Avoid analytics, crash reporting, cloud database/storage, authentication, and speech-to-text packages in the initial dependency set.

## 5. AI request and response flows

### Common gate

1. AI must be enabled, the user must tap a named AI action, and the app must be online. The app does not impose a local request cap.
2. Resolve local matches first for normal search. Never call AI automatically to fill a search result.
3. Show the exact selected text/image/data scope and request purpose. For review workflows, get explicit confirmation before sending selected meal/day details.
4. Send the smallest necessary payload through Firebase AI Logic using a Gemini Developer API model available on its no-cost tier. App Check must be enforced. No Gemini secret is placed in the APK; Firebase configuration identifiers are not secrets but must not be treated as access control.
5. Parse constrained structured output, validate bounds/shape/units, then render as an editable proposal. Do not persist AI output until user accepts through the ordinary save flow.
6. Do not maintain local request counters or caps. Firebase/provider quota and rate-limit responses are surfaced as normal request errors.
7. On network, quota (429), App Check, provider, parse, or safety failure, preserve user input and offer manual flow. No automatic retry; user may retry explicitly when eligible.

### Workflow-specific payloads

- **Photo identification/portion:** selected image plus a narrow prompt asking for candidate food names, estimated edible portion/unit, nutrition estimate, uncertainty, and clarifying question when ambiguous. Do not include profile/weight. User edits quantities and nutrient values before saving.
- **Text meal interpretation:** user-submitted typed/dictated description, locale/units if needed, and instruction to return separate candidate foods/portions with uncertainty. Dictation is platform keyboard text; only tapping Analyze sends it.
- **Unknown food estimate:** user-entered food name and optional serving details; explicitly label estimate and preserve source metadata. User confirms or replaces values.
- **Nutrition label extraction:** selected image of label; extract serving size and listed nutrient fields with confidence. Do not infer unlisted values as facts. User verifies against image.
- **Nutrition review:** user selects a meal or day and confirms a preview of fields to send; send only that selected nutrition data and goal subset strictly needed for the requested review. Exclude weight/activity/profile unless later explicitly designed and separately consented.

## 6. Privacy, security, cost, and offline behavior

- Local database is default and source of truth. No account, sync, telemetry, or background upload. Use Android sandbox storage and review Android Auto Backup behavior; avoid unintended cloud backup of sensitive records unless the user explicitly chooses a backup destination.
- A selected photo and its optional context stay local until the user taps Analyze. Show that both are sent together to Gemini through Firebase AI Logic. Context may include sensitive dietary details, so include it in the same point-of-use disclosure and allow clearing/editing it before submission. Keep photo/context drafts after a request error for manual fallback, but never retry or resubmit automatically. Discard the image after analysis unless separately retained by user choice.
- Export is user initiated. Explain that shared backups can leave device control; consider optional passphrase encryption as a follow-up decision.
- Gemini Developer API free-tier use through Firebase AI Logic requires the Firebase project to remain on the no-cost Spark plan with no linked Cloud Billing account. Never configure or request billing/Blaze or paid services. Restrict selected model/features to those actually eligible for the no-cost tier and re-check current provider terms/quotas before release.
- Firebase AI Logic keeps the Gemini API key server-side; never add a direct Google AI SDK key. Firebase project configuration in the app is public configuration, not a substitute for App Check. Enforce App Check and use Play Integrity for release; use debug attestation only for development and do not ship debug tokens.
- A no-cost tier still has quotas, model restrictions, and provider data handling terms. Surface external processing at point of use and provide manual fallback. Do not promise zero provider-side retention; verify current Google terms/data handling before launch.
- Do not add a replacement application-level AI cap. Since no billing account is allowed, the project must remain Spark; provider quota errors must degrade gracefully. No auto-retry.
- Offline: all local search, logging, calculations, history, charts, scheduling, workouts, and backup generation remain available. AI-only actions are disabled with explanation; retain drafts.
- Permissions: request camera/photo access only when user invokes photo workflow; Android keyboard dictation is provided by the keyboard/OS and the app adds no speech-recognition permission. No location or microphone permission in scope.

## 7. Implementation plan

1. **Foundation and product shell:** confirm open decisions; establish feature-oriented architecture, theme system, navigation, date/unit utilities, database migrations, settings/goals, and app-level error/empty states.
2. **Food and dashboard:** local Indian starter catalog, search, manual foods, editable quantities, meal logging, recipes/saved meals, deterministic nutrient math, dashboard totals and goals.
3. **Weight and progress:** weight history/editing, seven-day averages, chart summaries, date-range aggregation and progress screen.
4. **Workout planner:** exercise library, templates/scheduled weekly sessions, planned and completed sets, actual reps/weights, completion tracking.
5. **Running:** schedule and manual run logs, distance/duration/pace conversion, goals and activity summaries.
6. **Backup, privacy, and polish:** versioned export/restore, delete data, theme/accessibility, Android backup policy, migration resilience, empty/error states, final Android debug/release readiness.
7. **Optional AI:** only after Firebase project ownership/configuration and policy/eligibility decisions; wire AI gateway, App Check, usage cap, proposal review UI, errors/quota fallback, and all five workflows. Core app must not depend on Firebase initialization.

## 8. Test and validation plan

Do not consider a feature complete without relevant coverage. Tests are planned here; none are run as part of this specification-only change.

### Unit tests

- Portion scaling, recipe aggregation, kcal/macros rounding, remaining calories, goal progress, validation, unit conversions, pace calculations, and zero/missing values.
- Seven-day average uses available daily measurements in the trailing seven local days, handles duplicate same-day entries according to the decided rule, and crosses month/year/timezone boundaries correctly.
- Trend aggregations distinguish missing from zero; date range boundaries are inclusive and consistent.
- AI response schema validation, uncertainty labeling, malformed/unsafe values, and no persistence before explicit acceptance.
- Food-analysis request construction includes the chosen image and optional context text in one multimodal request; omits absent image/context correctly and never sends before Analyze. Text-only Analyze works without an image.

### Database/repository tests

- CRUD and relational integrity for foods, logs, recipes, meals, weight, goals, exercises, workouts, runs, and settings.
- Migrations from each prior schema version, transaction rollback, stable snapshots after catalog changes, and persistence after close/reopen.
- Backup export/import round trip, malformed/unsupported backup rejection, merge/replace behavior, duplicate IDs, and rollback on restore failure.
- Queries for date selection and daily/weekly summaries; no network required.

### Widget and flow tests

- First-run goal defaults/editing, light/dark/system themes, accessible labels, empty states, and date navigation.
- Search prioritizes local results and never invokes AI; manual food/meal/recipe create-edit-delete and serving-size recalculation.
- Weight entry editing, chart summaries, workout planning/set completion, run planning/logging/pace, and dashboard refresh.
- AI disabled, user cancellation, proposal edit/reject/accept, quota cap, offline/provider/App Check/429/parse failures, and preservation of draft/manual fallback.
- Photo plus optional typed context and photo plus keyboard-dictated context are submitted together only on Analyze; test edits/clear before submission, no premature request, manual fallback after failure, image absence with text-only analysis, and that no speech plugin/service is invoked.
- Backup confirmation, restore preview, delete-all confirmation; ensure AI consent previews exact selected data and omit weight/profile by default.

### Android validation

- `flutter analyze`, `flutter test`, and `flutter build apk --debug` from the project root after implementation; inspect Android permissions, manifest, backup configuration, App Check release/debug provider behavior, and APK for embedded secrets/debug tokens.
- Validate on emulator and a physical Android device when available: keyboard dictation insertion in ordinary fields; system/light/dark themes; process death/restart; offline mode; photo picker/camera denial; timezone/date boundary; screen readers and text scaling; backup/restore using Android document picker.
- Verify Firebase project remains on Spark with no billing account, model/free-tier eligibility, App Check enforcement, quota/error fallbacks, and no AI calls without explicit action.

## 9. Acceptance criteria

1. User can launch and use food, weight, workouts, runs, dashboard, and progress with airplane mode enabled and without account/API key/subscription.
2. Defaults are editable and initially 2,100 kcal, 150 g protein, and 77–78 kg target range.
3. Dashboard values exactly match locally stored food entries and serving quantities; changing catalog data does not silently rewrite historical snapshots.
4. User can find common Indian foods offline, create custom foods/recipes/meals, adjust quantities, and review/edit/delete logs.
5. User can create/edit weight history, see a correct seven-day average and accessible weight chart, and inspect sparse/missing data accurately.
6. User can plan weekly gym sessions with exercises and sets/reps/weights, record actuals and completion, and edit history.
7. User can schedule/log runs with distance/duration/pace/goal comparisons; pace and unit conversions are correct.
8. Voice-assisted input relies only on dictated text inserted by the Android keyboard; no app speech service or transcription AI call exists.
9. AI is disabled by default; every request follows an explicit user action, avoids unnecessary profile/weight data, and returns an editable proposal before any saved change. For photo logging, image and optional context are submitted together in one request only after Analyze; text-only analysis also works.
10. App Check is enforced, no Gemini secret/private key/debug App Check token is embedded, Firebase uses eligible Gemini Developer API free tier on Spark with no linked billing account, and unavailable/quota cases retain manual operation.
11. Daily usage control, no background calls, local export/restore, and delete-all are functional and explained.
12. Light/dark themes, accessibility basics, persistence across restart, migrations, and Android build/test/analyze checks pass.

## 10. Open decisions and blockers

- **Firebase Console verification:** Android configuration now matches project `calorietrackerpersonal-d3fb3` and registered app `com.example.calorie_tracker`. The client explicitly uses Firebase AI Logic's Gemini Developer API (`FirebaseAI.googleAI()`) with `gemini-3.8-flash`. Confirm in Firebase Console that AI Logic uses the Gemini Developer API, remains on Spark without linked billing, and App Check is enforced for Firebase AI Logic. Register each development device's App Check debug token; register Play Integrity for release builds.
- **Android identity and minimum SDK:** application ID is confirmed as `com.example.calorie_tracker`; verify the configured Flutter minimum SDK remains compatible with the selected Firebase plugin versions when upgrading dependencies.
- **Food catalog provenance:** decide the nutrition source/licensing and serving conventions for the Indian starter dataset; recipes vary and the app must show estimates where appropriate.
- **Goals:** initial kcal/protein/weight values are agreed. Decide whether carbohydrate/fat targets are unset, calculated, or user-entered; do not infer personal targets silently.
- **Weight average:** proposed trailing seven calendar days and available daily observations. Decide whether multiple same-day observations are averaged, latest selected, or user chooses a primary entry.
- **AI usage cap and model:** proposed 5 user-triggered attempts/day. Confirm cap and choose only a currently free-tier-eligible model after checking live terms/limits. Firebase quotas vary and are provider controlled.
- **Backup:** decide optional encryption/passphrase, Android OS backup policy, and whether restore defaults to replace (recommended) or merge.
- **Workout/run scope:** decide if recurring plan templates need advanced recurrence and whether actual workout set weight/reps are required fields (proposed optional).
- **Charts and localization:** initial language is English and units are selectable; confirm whether Hindi/localized labels are in scope for first release.
- **AI data handling:** review current Gemini Developer API data-use/retention terms and user-facing disclosure before enabling any production AI request.
- **Photo context retention (resolved):** copy the user's context into the note on accepted food entries so assumptions remain visible; discard the selected image after analysis and do not retain it.

## 11. Official references checked

- [Firebase AI Logic overview](https://firebase.google.com/docs/ai-logic) — Flutter client SDK and proxy/App Check model.
- [Firebase AI Logic pricing](https://firebase.google.com/docs/ai-logic/pricing) — Gemini Developer API free tier uses Spark without linking Cloud Billing; paid tier requires billing; models/features differ.
- [Firebase AI Logic getting started](https://firebase.google.com/docs/ai-logic/get-started?platform=flutter) — current Flutter setup and provider selection.
- [Firebase for Flutter setup](https://firebase.google.com/docs/flutter/setup) — FlutterFire configuration and `firebase_options.dart` initialization.
- [Google Services Gradle plugin](https://firebase.google.com/docs/android/google-services-plugin-and-file) — Android JSON config processing.
- [Firebase AI Logic App Check](https://firebase.google.com/docs/ai-logic/app-check) — App Check protection and production attestation.
- [Firebase AI Logic quotas](https://firebase.google.com/docs/ai-logic/quotas) — model/project quotas and 429 behavior.
- [Firebase pricing plans](https://firebase.google.com/docs/projects/billing/firebase-pricing-plans) — Spark/Blaze billing relationship.
