# Background timer punctuality (spike S-01)

During a workout the rest countdown has to beep on time even when the phone is
in a pocket. In the foreground the app does it itself — `TimerEngine` ticks,
`audioplayers` beeps, `vibration` buzzes, `wakelock_plus` keeps the screen on.
Out of the foreground there is no Dart engine running, so the beep becomes a
**scheduled local notification**: on the way out the Bloc asks
`TimerEngine.upcomingSignalTimes()` for the instants the timer will signal at
and hands them to `SessionNotifier`; on the way back it cancels whatever is
still pending and recomputes the timer from the wall clock.

S-01 asks a narrow question about that path: **does the beep actually land at
the right moment?** This is what has been verified, what was wrong, and what
still needs a device.

## What the scheduler can and cannot express

`flutter_local_notifications` takes a `TZDateTime`, but **neither platform
schedules below the second, and neither rounds — both truncate**:

| | how the instant is turned into a trigger | effect on a sub-second instant |
| --- | --- | --- |
| iOS | `UNCalendarNotificationTrigger` built from calendar components down to `NSCalendarUnitSecond` — no nanoseconds | fires at the **start** of that second |
| Android | the Dart side sends `toIso8601String().split('.')[0]`, parsed as a `LocalDateTime` into epoch millis for `AlarmManager` | alarm set at `.000` of that second |

A rest timer starts when the user taps, so `startedAt` carries an arbitrary
fraction of a second and so does its end. Left alone, the notification
therefore fires **early** — on average about half a second, up to a full
second. Early is the harmful direction: the phone says "go" while the rest is
not over yet. A late beep on a 90-second rest is not noticeable; an early one
changes the set.

`scheduledInstantFor` (in `services/notifications/session_notifier.dart`)
rounds each instant **up** to the whole second before it reaches the plugin.
The signal is then never early, and at most one second late.

`TimerEngine` is deliberately left alone: its instants stay the true ones.
The rounding is a property of the notification scheduler, so it lives at that
boundary — which is also why `services/timer/` still has no idea a
notification exists.

## `inactive` is not backgrounding

iOS sends `AppLifecycleState.inactive` while the app is still in the
foreground and fully visible: Control Center, the notification shade, an
incoming-call banner, the app switcher, a Face ID prompt. The real transition
is `resumed → inactive → hidden → paused`, and it comes back up through
`hidden` and `inactive` again.

Treating everything that is not `resumed` as "backgrounded" cost two things:

- **a doubled signal.** With the app still on screen the engine beeps by
  itself; `kTimerSignalDetails` sets `presentAlert`/`presentSound`, so iOS
  also presents the scheduled notification in the foreground. Pull down
  Control Center while a rest is running and the beep arrives twice.
- **platform-call churn while iOS is suspending the process.** Each pass
  re-ran eleven `cancel` calls plus up to ten `zonedSchedule` calls, and a
  single round trip triggered several passes.

So `WorkoutSessionPage` now dispatches nothing on `inactive`, schedules from
`hidden` — the first moment the app is genuinely out of sight, still with time
before iOS suspends it — and the Bloc ignores a second "to background" until a
return to the foreground has happened. The return is never skipped: after a
process kill the Bloc starts fresh with no memory of having been away, and
that is exactly when it has to clear notifications armed by a previous process
or by the Android background isolate.

## What is covered by tests

Run on any machine, no device needed:

- `test/services/notifications/session_notifier_test.dart` — a scheduled
  instant is never before the true one, never more than a second after it, and
  always lands on a whole second; checked across every millisecond offset and
  against a real `TimerEngine` signal list.
- `test/features/workout/bloc/workout_session_bloc_test.dart` (`lifecycle`) —
  one scheduling pass per backgrounding, a fresh pass after each return, and a
  return that always cancels.
- `test/features/workout/pages/workout_session_page_test.dart` — `inactive`
  schedules and cancels nothing; `hidden` schedules once and `paused` does not
  repeat it.

## What still needs a real device

None of the above proves the OS *delivers* on time — that is the part of S-01
that only a device can close. The simulator is not evidence: it does not
suspend apps the way a real phone does and never enters low-power mode.

On an iPhone, with the app installed in release mode (`flutter run --release`):

1. **Baseline.** Start a 90-second rest, lock the phone, and time the beep
   against a stopwatch. Expect it on the second, never before.
2. **Pocket test.** Same, but leave the phone alone for a few minutes first so
   iOS settles the app, then start the rest and lock. Late by more than a
   second or two is the S-01 risk materialising — write down how late.
3. **Low Power Mode.** Repeat 1 with Low Power Mode on. This is the most
   likely place for delivery to slip.
4. **Control Center.** Start a rest with the app open, pull down Control
   Center, and wait past the end: the beep must sound **once**.
5. **EMOM.** Start a 5-minute EMOM, lock, and count the signals: four round
   starts plus the end, none missing, none doubled.
6. **Return.** Come back mid-rest and check the on-screen countdown matches
   the wall clock — `reconcile()` recomputing from `startedAt`, not resuming a
   tick count.
7. **Focus / Do Not Disturb.** With a Focus active the notification may be
   silenced entirely. If so, that is a limitation to document for users, not a
   bug to fix in code.

Cases 2, 3 and 7 are the ones that decide whether the notification path is
enough on its own. If delivery turns out to be unreliable there, the fallback
is not a code fix in this layer: it is the mode the app already treats as
primary — screen on, wake lock held, the app doing its own beeping.

## Known limits, unchanged by this spike

- The sound is the system notification sound, not a custom continuous tone.
- At most `kMaxScheduledSignals` (10) signals are scheduled per pass; a longer
  EMOM gets the rest of them on the next foreground round trip.
- A notification scheduled for an instant that has already passed never fires
  on iOS, where Android would fire it immediately. Rounding up keeps the
  instant in the future in the normal case; the residual window is under a
  second and falls where the app was still in the foreground and has already
  beeped by itself.
