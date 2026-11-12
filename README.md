# TaskPomo

A few minutes a day, every day. Duolingo-style streaks for anything you want to
practise: give a task a daily target and the days it's due, then work on it in
pomodoro sessions. The sessions add up. Hit the target on a due day and the
streak lives on.

Flutter app for Android (with a homescreen widget) and the web, backed by
Firebase: Google sign-in, Firestore, Hosting, and Firebase AI Logic (Gemini) for
the fun recap.

## How it works

| | |
|---|---|
| **Task** | Name, icon, colour, daily target (5 min to hours), schedule (daily / weekdays / weekends / custom days). |
| **Sessions** | Start a task to start a pomodoro (25 min by default, configurable). Keep it running through as many pomodoros as you like, pause, or stop whenever. All of today's sessions count toward the target. |
| **Streak** | Per task: counts that task's due days that hit their target. Missing one task never touches the others. Days that aren't due never break it. A due day you miss breaks it at midnight. |
| **Clean streak** | The same, but reset by freezes. Milestone bonuses are paid on this one. |
| **Points** | Scale with the work: a task earns about 1 point per 3 minutes of its daily target (5 min → 2, 15 min → 5, 1 h → 20, 2 h → 40). Clean-streak bonuses pay a modest multiple of the task's daily points: 10 and 20 days 1×, 50 days 3×, 100 and 150 days 5×, 200 days 6×, 300 days 7×, 365 days 10×, then 7× every hundred. A year of milestones totals 38 days' worth, about a tenth of what the practice earns. |
| **Freezes** | Per task and per day. One day costs 5 days of that task's points for tasks of 5 min or less, sliding (log scale) to 3 days' worth at 2 h or more: 5 min → 10, 15 min → 22, 1 h → 69, 2 h → 120. Freeze one task from its timer menu, or several at once (Me → Going away?, pick tasks and days). With **auto-freeze** on, a missed day spends points if you have enough. Freeze a day and then do it anyway, and you get the points back. |
| **Look** | "Ledger": warm paper, ink type, Instrument Serif numerals with Geist and Geist Mono, hairline rules, one rust accent for "today". Always light. No emoji. The paper yellows through the day while work is left (time since 9 am × share of today's minutes left) and is fresh again once everything is done. |
| **Privacy** | The homescreen widget and notifications never show task names or icons. The widget shows minutes done today, the week (each day filled by how much got done), how many are left, minutes to go, and numbered progress lines (01, 02…) with each task's streak. |
| **Insights** | Week / Month / Year / All. Hours, days showed up, sessions, median session, best day; the year in squares; where the time went (by task, stacked); when you focus (weekday × hour); session lengths; target vs actual; streak runs per task; which habits travel together. Tap any mark for its numbers. Plus the weekly note from Gemini. |
| **Monthly recap** | On the 1st a notification (no task names) opens last month's page: totals vs the month before, a calendar, a written note from your numbers and session notes, and a per-task table. Past months stay under Insights → Recaps. |
| **Wrapped** | A year in review as tap-through story pages, in December and for every past year. A preview of the year so far is at the bottom of Insights. |
| **Export** | Insights or Me → Export as CSV: tasks.csv, days.csv (the full task-by-day ledger), sessions.csv (with notes) and points.csv, plus a README describing every column, via the share sheet. |
| **Scroll minutes** | Points double as time on apps you choose to limit (Me → Scroll minutes): 1 point = 1 minute, all chosen apps combined. A reserve (default: two freezes of your biggest task) can't be scrolled away. At zero a full-screen page covers the app; once a day 5 grace minutes are available, repaid from future points. Uses an Android accessibility service that only sees which app is in front (window changes from real app screens), never screen content. Needs a one-time setup: App info → ⋮ → Allow restricted settings, then Accessibility → TaskPomo scroll minutes → on. |
| **Streak moment** | Completing a day opens a full-screen page where the streak number rolls over, the dial moves toward the next bonus and today's square fills; ink page and a dial sweep on bonus milestones. |

The rules live in `lib/logic/streaks.dart` (constants at the top) and are
covered by `test/widget_test.dart`.

## Project layout

```
lib/
  logic/        streak + points rules, headline wording, week strip, paper aging, analytics, CSV (pure Dart, tested)
  ui/           Ledger components, the chart kit (charts.dart) and the icon set
  models/       Task, DayLog, Profile, LedgerEntry
  data/repo.dart  all Firestore reads/writes (users/{uid}/tasks|days|sessions|ledger)
  state/        AppController (live data, daily streak check), TimerController (pomodoro)
  services/     notifications, widget sync, Gemini recap
  screens/      Today, Timer, Task detail/editor, Insights, Me, Sign-in
android/app/src/main/kotlin/.../PomoWidgetProvider.kt   the homescreen widget
assets/fonts/          Instrument Serif, Geist, Geist Mono (SIL Open Font License)
```

## Setup

Flutter is installed at `C:\src\flutter`. Add `C:\src\flutter\bin` to your
PATH (Windows search → "Edit the system environment variables" → Path).

### 1. Android tooling (once)

1. Install [Android Studio](https://developer.android.com/studio). On first
   launch let it install the Android SDK.
2. In Android Studio: Settings → Languages & Frameworks → Android SDK → SDK Tools,
   tick **Android SDK Command-line Tools**.
3. Accept the licences and check everything is green:
   ```
   flutter doctor --android-licenses
   flutter doctor
   ```

### 2. Firebase project (once)

1. In the [Firebase console](https://console.firebase.google.com) create a project
   (the free Spark plan is enough).
2. **Authentication** → Get started → Sign-in method → enable **Google**.
3. **Firestore Database** → Create database (production mode, region near you).
4. **AI Logic** → Get started → choose the **Gemini Developer API** (free tier).
5. Connect the app:
   ```
   firebase login
   dart pub global activate flutterfire_cli
   flutterfire configure --platforms=android,web
   ```
   Pick your project. This replaces `lib/firebase_options.dart` and adds
   `android/app/google-services.json`.
6. Deploy the security rules (each user can only touch their own data):
   ```
   firebase use --add        # pick the project
   firebase deploy --only firestore
   ```
7. Add your debug key's SHA-1 to the Android app in Firebase (Project settings →
   Your apps → Android → Add fingerprint). Get it with:
   ```
   cd android && gradlew signingReport
   ```

### 3. Run it

Phone: enable Developer options → USB debugging, plug it in, then
```
flutter run
```

Install a standalone build on your phone:
```
flutter build apk --release
```
and copy `build/app/outputs/flutter-apk/app-release.apk` to the phone.

**Widget:** long-press the homescreen → Widgets → TaskPomo, and drag it out.
Tapping a task row on the widget opens its timer.

### 4. Web (optional)

```
flutter build web
firebase deploy --only hosting
```

## Notes

- Everything works offline; Firestore syncs when you're back online.
- The running timer lives on the device (it survives the app being closed). It
  shows a live counter in the notification shade and on the widget.
- Pomodoro bells use inexact alarms, so with the screen off Android may ring
  them a minute or so late.
- The Gemini model is set in `lib/services/ai_recap.dart` (`AiRecap.model`).
  The recap is cached per week, so normal use is about one call a week.
- Colours live in `lib/theme.dart` (`Ledger.paper`) and, for the widget,
  `android/app/src/main/res/values/colors.xml`. Keep the two in step.
- Widgets can't use custom fonts, so the widget draws its serif number and
  headline into bitmaps with the bundled Instrument Serif.
