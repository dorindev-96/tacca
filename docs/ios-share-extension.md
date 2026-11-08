# Sharing the prompt out, sharing the reply back

The keyless AI import (*Nuova scheda → Con la tua chat AI*) never talks to a
model. It builds a self-contained prompt, hands it to the **system share
sheet** so the user drops it straight into whatever AI chat they already use,
and then takes the reply back. The reply can come back two ways:

1. **shared with Tacca from the chat** — the user taps *Share* on the reply,
   picks Tacca in the list of apps, and the app opens on step 2 with the reply
   already read (if it parses, the review editor opens at once; if it does
   not, step 2 shows the parser's error with the usual two exits);
2. pasted by hand, as before — *Copia il prompt* and *Incolla dagli appunti*
   are still there on step 2 for chats the share sheet does not reach.

The first path needs the app to be a **share target**. That is one line of
manifest on Android and a second Xcode target on iOS.

## How the text travels

Neither platform lets another app call into a running Flutter engine, and the
text may well arrive with the app killed. So both sides do the same thing the
lock-screen confirmation does: the native side **stores** the text and the
Dart side **asks for it** when it comes to the foreground — which is exactly
when a share brings the app forward.

| | Android | iOS |
| --- | --- | --- |
| Entry point | `MainActivity` receives `ACTION_SEND` (`text/plain`) in `onCreate` or `onNewIntent` | the `TaccaShare` share extension, a separate process |
| Storage | a field on the activity | App Group `UserDefaults` (`SharedTextStore`, compiled in both targets) |
| Wake-up | the activity is brought to the front by the system | the extension opens `tacca://shared-text` (URL scheme declared in `Runner/Info.plist`) |
| Hand-over | `MethodChannel` `tacca/shared_text`, method `takePending` | same channel, `SharedTextBridge` in the Runner |

On the Dart side `SharedTextIntake` (mounted in `MaterialApp.builder`, inside
the legal gate) drains the channel after the first frame and on every resume
through `SharedTextCubit`, and opens `/plans/new/import/paste` unless it is
already the top route. The page takes the text and `AiPasteImportCubit`
decides what it is: on step 2 anything that arrives is the reply; on step 1 a
text containing a JSON object is a reply (go to step 2 and parse), a text
without one is a plan to convert (appended to the field). That also makes
"share a plan from Notes to Tacca" work for free.

### Android: why `singleTask`

`MainActivity` is declared `launchMode="singleTask"` instead of Flutter's
default `singleTop`. With `singleTop` and the template's `taskAffinity=""`, a
share started from another app creates a **second** `MainActivity` inside
*that* app's task — a second Flutter engine in the same process, which runs
`main()` again and opens ObjectBox on the same directory, which throws. With
`singleTask` the system reuses the existing instance (`onNewIntent`) or
creates exactly one in Tacca's own task.

## Xcode setup (iOS)

The share extension target `TaccaShare` is already in `ios/Runner.xcodeproj`,
with its sources (`ios/TaccaShare/`, plus `ios/SharedText/SharedTextStore.swift`
shared with the Runner), `Info.plist` and entitlements. As for the Live
Activity, two things still need a human with Xcode because they touch your
developer account:

1. **App Group.** Open `Runner.xcworkspace` → select the **TaccaShare** target
   → *Signing & Capabilities* → **+ Capability** → *App Groups*, and tick
   `group.com.tverdohleb.tacca` — the same group the Runner and
   `TaccaLiveActivity` already use. The identifier must match
   `SharedTextStore.appGroupId`. App Groups need a paid Apple Developer
   Program membership.
2. **Signing.** The extension has its own bundle id,
   `com.tverdohleb.tacca.Share`. With automatic signing Xcode creates the
   profile on first build; check that *Team* is set.

Then build as usual — `flutter run` builds and embeds the extension.

If Xcode refuses to open the project, recreate the target from its template:
*File → New → Target… → Share Extension*, name it `TaccaShare`, delete the
generated storyboard and view controller, drag in `ios/TaccaShare/` (extension
only) and `ios/SharedText/SharedTextStore.swift` (**both** targets), set the
deployment target to 15.6 and the base configuration to
`Flutter/ShareExtension.xcconfig`, and make sure `Info.plist` keeps
`NSExtensionPrincipalClass = $(PRODUCT_MODULE_NAME).ShareViewController` with
no `NSExtensionMainStoryboard`.

The extension has no UI of its own: its view is transparent, it reads the
first text attachment, writes it to the App Group and opens the app through
the responder chain (`openURL:`), the same mechanism the Flutter sharing
plugins use. `FlutterDeepLinkingEnabled` is `false` in `Runner/Info.plist` so
the URL is not handed to the router as a route.

## What to check on a device

CI builds neither side. The Dart contract — delivery outcomes, the shared-text
cubit, the intake opening the page once, the page taking the text — is
covered by `test/features/ai_import/`; the declarations (manifest filter and
launch mode, URL scheme, extension activation rule) by
`test/services/share/share_target_declarations_test.dart`.

- [ ] Step 1, *Condividi il prompt e continua*: the share sheet opens; pick a
      chat app → the chat receives the prompt and Tacca is on step 2 when you
      come back. Dismiss the sheet instead → Tacca stays on step 1.
- [ ] In the chat, *Share* on the reply → Tacca is in the list; pick it → the
      app comes to the front on step 2, and the review editor opens if the
      reply parses.
- [ ] Same, with Tacca killed first: the app starts and lands on step 2.
- [ ] Share a reply that is not JSON: step 2 shows the error and offers
      *Condividi il messaggio di correzione*, *Copia…*, *Tieni come testo
      libero*.
- [ ] Share plain plan text from Notes with the import closed: step 1 opens
      with the text in the field.
- [ ] Android: share while a workout session is open — one Tacca task, the
      session is still there behind the import.
