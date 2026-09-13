# Lock-screen confirmation

During a workout the current exercise is published to the phone's lock screen,
with a button that ticks the set you just finished. You confirm the set,
the rest countdown starts, and you never unlock the phone.

The two platforms get there differently:

| | iOS | Android |
| --- | --- | --- |
| Surface | Live Activity (ActivityKit) + Dynamic Island | ongoing notification |
| Countdown | `Text(timerInterval:)`, drawn by the system | `usesChronometer` + `chronometerCountDown` |
| Button | App Intent, run by iOS in the app's process even while it sleeps (iOS 17+) | notification action → broadcast |
| Minimum version | iOS 16.2 for the banner, 17.0 for the button | Android 8.0 (`minSdk 26`) |
| Extra setup | **yes** — a second Xcode target, see below | one `<receiver>` line in `AndroidManifest.xml`, see below |

Below 16.2 (or with Live Activities switched off in Settings) `isSupported`
answers `false` and the session behaves exactly as it did before: no banner,
no button, everything else unchanged.

## How a confirmation travels

The tap does not reach the Dart engine. On iOS the App Intent runs with the
app suspended and no Dart engine alive; on Android the broadcast may arrive
after the app's process has been killed. Neither can open ObjectBox. So both
do the same thing:

1. write the action into a durable queue — App Group `UserDefaults` on iOS, a
   small JSON file on Android — synchronously, because it is the only step
   that cannot fail without losing the user's work;
2. update the surface optimistically, so the tap has a visible effect;
3. schedule the rest-end notification, because the app is not awake to beep.

Step 2 is why the payload carries the whole displayed state and not just the
coordinates of the set: neither the App Intent nor the background isolate can
ask the app what the banner currently says. On iOS that state is
`Activity.content.state`; on Android it rides in the notification's payload
and comes back through `LiveSessionSnapshot.tryParse`. The arithmetic that
produces the next state is written twice — `LiveSessionSnapshot`
`afterSetCompleted` in Dart, `CompleteSetIntent.swift` in Swift — and the two
copies must stay identical. The Dart one has tests; the Swift one does not.

That step is also where the snapshot's `next*` fields earn their keep. The
intent knows how to count the sets of the exercise on screen, but nothing else
about the workout, so the app ships the following exercise along with the
current one: confirming the last set moves the banner onto it instead of
counting a set that does not exist ("4/3"). That is **one** step — after the
sets of that exercise are gone too the button disappears until the app is
reopened and recomputes the lookahead. Because each redraw republishes the new
state into the payload, consecutive taps chain correctly without the app.

`WorkoutSessionBloc` drains the queue when a session opens **and** every time
the app returns to the foreground, then applies each action **with the
timestamp of the tap** — the rest timer starts from when the set actually
ended, not from when the app woke up. Both moments are needed: after the
process is killed the bloc is built from scratch and no lifecycle change ever
arrives. An action whose `logId` belongs to another session is discarded, and
every action carries an id so the same confirmation delivered twice (once
live, once from the queue) is applied once.

On Android the queue is not a fallback, it is *the* delivery path. An action
with `showsUserInterface: false` is sent to `ActionBroadcastReceiver`, which
spins up a background isolate and calls
`onDidReceiveBackgroundNotificationResponse` — even when the app is alive and
in the foreground. The plugin's foreground callback never sees it.

That isolate is a full Flutter engine, so plugins are registered in it
(`AndroidFlutterLocalNotificationsPlugin.registerWith()` runs from the
generated Dart plugin registrant, which the engine executes for every
isolate). That is what lets the handler redraw the notification and schedule
the beep on its own. It deliberately does *not* call `initialize` again: the
default icon is already in shared preferences, and re-initialising would
rewrite the stored callback handles from an isolate that is about to be torn
down. The rest-end reminder is scheduled with `kBackgroundRestReminderId`,
which sits at the end of the id range `SessionNotifier` owns — so the app
cancels it with all the other timer signals the moment it takes the session
back.

### Android manifest

`flutter_local_notifications` ships no receivers in its own manifest, so the
app must declare the one that handles action buttons:

```xml
<receiver
    android:exported="false"
    android:name="com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver" />
```

Without it the action's `PendingIntent` resolves to no component at all: the
button is drawn, it is tappable, and the tap goes nowhere — no crash, no log,
nothing. It is already in `android/app/src/main/AndroidManifest.xml`; do not
remove it when tidying the file.

Known limitation, Android only: steps 2 and 3 run on an engine the system may
tear down as soon as the broadcast has been served, and the very first tap
after the process was killed also pays for starting that engine. If they do
not finish, what is lost is the banner refresh and the beep — never the set,
which was already written to the queue synchronously, and never the rest
countdown that is already on screen, because the system draws it from
`countdownEndsAt`.

## Xcode setup (iOS)

The widget extension target `TaccaLiveActivity` is already in
`ios/Runner.xcodeproj`, with its sources, `Info.plist` and entitlements. Two
things still need a human with Xcode, because they touch your developer
account:

1. **App Group.** Open `Runner.xcworkspace` → select the **Runner** target →
   *Signing & Capabilities* → **+ Capability** → *App Groups*, and tick (or
   add) `group.com.tverdohleb.tacca`. Repeat on the **TaccaLiveActivity**
   target. The identifier must match `LiveSessionShared.appGroupId` in
   `ios/LiveSessionShared/TaccaSessionAttributes.swift` — it is the only
   channel between the app and the extension. App Groups need a paid Apple
   Developer Program membership; free personal teams cannot enable them.
2. **Signing.** The extension has its own bundle id,
   `com.tverdohleb.tacca.LiveActivity`. With automatic signing Xcode creates
   the profile on first build; check that *Team* is set on both targets.

Then build as usual — `flutter run` builds and embeds the extension, no
separate step:

```bash
flutter run --release        # Live Activities also work on the simulator (16.2+)
```

If Xcode ever refuses to open the project, the target can be recreated from
its template: *File → New → Target… → Widget Extension*, name it
`TaccaLiveActivity`, tick *Include Live Activity*, then delete the generated
sources and drag in the files under `ios/TaccaLiveActivity/` (extension target
only) and `ios/LiveSessionShared/` (**both** targets — the attributes, the
queue and the intent are compiled into each process; see below for why the
intent is not optional). Set the deployment target to 16.2 and
the base configuration to `Flutter/LiveActivity.xcconfig`, which is what keeps
the extension's version in step with the app's; Apple rejects a bundle whose
extension version differs.

### `CompleteSetIntent` belongs to both targets

`ios/LiveSessionShared/CompleteSetIntent.swift` must be ticked for **Runner**
as well as for **TaccaLiveActivity**. A `LiveActivityIntent` is run by iOS in
the *app's* process (waking it in the background if needed); the extension
compiles it only because that is the type `Button(intent:)` names. When the
type is missing from the app binary the system does not fail loudly — it runs
the intent out of process, in `WFIsolatedShortcutRunner`, where
`Activity.activities` is empty, so `perform()` returns at its first `guard` and
the button does nothing at all: no counter advancing, no countdown, nothing in
the queue to drain.

To check it from the command line, the app bundle — not just the appex — must
carry the intent:

```bash
grep -c CompleteSetIntent \
  build/ios/iphonesimulator/Runner.app/Metadata.appintents/extract.actionsdata
```

## What to check on a device

Nothing here is covered by CI: the Linux runner cannot build iOS, and the
Swift side has no tests. The Dart side of the contract — snapshot payload,
action parsing, the queue, and the Bloc applying a confirmation with the tap's
timestamp — is covered by `test/services/live_session/` and the *schermata di
blocco* group in `test/features/workout/bloc/workout_session_bloc_test.dart`.

Worth walking through by hand at least once:

- [ ] Start a session: the banner appears on the lock screen and in the
      Dynamic Island.
- [ ] Lock the phone, press **Serie fatta**: the set counter advances and the
      rest countdown starts, without opening the app.
- [ ] Keep pressing to the end of the exercise: the banner moves to the next
      exercise at set 1 — the counter must never read "4/3".
- [ ] Wait for the countdown to end: the notification fires **once** (the app
      cancels the extension's reminder when it wakes up — a double beep here
      means that cancellation is not working).
- [ ] Reopen the app: the set is in the log with the time you pressed the
      button, and the rest timer shows the time actually left.
- [ ] Confirm the last set of an exercise: the button disappears until the app
      is reopened, then the banner moves to the next exercise.
- [ ] Finish the session: the banner disappears.
- [ ] On an iPhone without Dynamic Island, and on iOS 16.x: banner yes, button
      only from 17.

## Testi dei permessi in più lingue (una volta, a mano)

Le traduzioni dei due permessi di sistema (fotocamera e galleria, RF-03) sono
già scritte in `ios/Runner/<lingua>.lproj/InfoPlist.strings`, una cartella per
`it`, `fr`, `es`, `de`, `sv`. **Finché non sono registrate nel progetto Xcode
non le legge nessuno**: iOS continua a mostrare a tutti la stringa italiana
scritta dentro `Info.plist`. La registrazione non si può fare da qui perché
tocca `Runner.xcodeproj/project.pbxproj`, che la CI (runner Linux) non compila.

In Xcode, una volta sola:

1. seleziona il progetto *Runner* → *Info* → *Localizations*, e aggiungi
   italiano, francese, spagnolo, tedesco e svedese;
2. trascina `ios/Runner/it.lproj/InfoPlist.strings` dentro il gruppo *Runner*
   (spuntando *Copy items if needed* → no, i file ci sono già);
3. selezionalo e, nell'inspector a destra, premi *Localize…*: Xcode raggruppa
   da solo le altre lingue che trova nelle `.lproj` accanto;
4. verifica che il file compaia in *Build Phases* → *Copy Bundle Resources*;
5. prova su device cambiando lingua di sistema: il pop-up del permesso
   fotocamera deve arrivare tradotto.

Le stringhe dell'interfaccia non c'entrano: quelle passano dagli ARB
(`lib/l10n/`) e non richiedono niente lato Xcode.
