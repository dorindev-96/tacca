# Tacca

[![CI](https://github.com/dorex96/tacca/actions/workflows/ci.yml/badge.svg)](https://github.com/dorex96/tacca/actions/workflows/ci.yml)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.35-02569B?logo=flutter&logoColor=white)](https://flutter.dev)

An offline-first Flutter app for gym workout plans: write or photograph your plan, run the session with block-aware timers, and keep a log of every set.

Everything except the optional AI import works with no network connection, and all data stays on the device — there is no account, no backend, no telemetry.

> **Language note.** The app UI, the source comments and the specification are in Italian (*"tacca"* is the tally mark you scratch down after a set). This README and the contributor docs are in English. There is currently one locale, `it`; the strings live in `lib/l10n/app_it.arb`, so adding another one is a translation, not a refactor.

| Archivio schede | Dettaglio scheda | Sessione |
|---|---|---|
| <img src="docs/screenshots/plans.png" width="220" alt="Archivio delle schede, con la scheda in uso in evidenza"> | <img src="docs/screenshots/plan-detail.png" width="220" alt="Dettaglio di una scheda con blocchi ed esercizi"> | <img src="docs/screenshots/session.png" width="220" alt="Sessione di allenamento con serie spuntate e recupero"> |

## Project status

Personal project, pre-1.0. What is actually built:

| Area | State |
| --- | --- |
| Plans archive, manual editor | ✅ done |
| Share a plan as an image | ✅ done |
| Workout session, timers, crash recovery | ✅ done |
| Lock-screen set confirmation | ✅ done — iOS needs a one-off Xcode setup |
| History | ✅ done |
| AI import from photo / gallery / pasted text | ✅ done, **OpenRouter, Anthropic and Google Gemini** |
| AI import through your own chat, no key needed | ✅ done — copy the prompt, paste the answer back |
| AI chat to create/edit a plan | 🚫 not planned — importing a plan and then editing it by hand covers the need |
| Providers | ✅ done |

## Features

**Plans.** Archive with search, active/archived sections and an "in use" badge; duplicate, archive, restore, delete. Deleting a plan never deletes the history attached to it. *Condividi* exports the whole plan — every day, every block, every exercise — as a single PNG and hands it to the system share sheet, so a plan can reach someone who does not have the app: a chat, not an interchange format. The image is not a screenshot; the plan is taller than the screen, so it is laid out again off-screen at a fixed width and whatever height it needs.

**Manual editor.** A plan is *days → blocks → exercises*. A block is a grouping with a type: `standard`, `superset`, `circuit`, `EMOM`, `AMRAP`, `Tabata`, `For Time`, or free text for anything that resists structure. Each type exposes only its own parameters (interval and total minutes for EMOM, work/rest/rounds for Tabata, time cap for For Time, …).

**Guided session.** Log weight, reps and notes per set, with the previous session's numbers shown as a reference ("last time"). Rest starts automatically after you tick a set; block timers cover EMOM/AMRAP/Tabata/round rest. Only one timer runs at a time, and the timer is **wall-clock based** — it stays exact after the screen turns off or the app is backgrounded, where it hands over to a local notification. Beep, vibration and wakelock while in the foreground. Every action is persisted immediately, so a crash or an accidental exit leaves a session you can resume: an open workout shows up on top of the plans archive as long as it is open — a crash, a swipe away or just leaving the screen — and one tap goes back into it. **One workout at a time**: starting another while one is open asks first, and closes the previous one as interrupted (it stays in history with everything you logged).

**Lock screen.** While a session is open the current exercise is published to the lock screen — a Live Activity (and Dynamic Island) on iOS, an ongoing notification on Android — with the rest countdown drawn by the system and a **Serie fatta** button that ticks the set without unlocking the phone. The tap runs outside the Dart engine — an App Intent on iOS, a background isolate on Android — and on both platforms it does the same three things without waking the app: it queues the confirmation, moves the banner on to the next set with the rest countdown already running, and schedules the rest-end alert. The app applies the queued confirmation when it comes back, **with the time the button was pressed**: the rest starts from when the set actually ended. iOS needs a one-off Xcode setup, described in [docs/ios-live-activity.md](docs/ios-live-activity.md).

**History.** Snapshot-based: each log stores the plan and exercise *names* it was recorded with, so past sessions stay readable after you edit or delete the plan. Filter by plan, drill into a session, see every set.

**AI import (optional, bring your own key).** Photograph a paper plan, pick images from the gallery, or paste text; the model returns a structured plan that lands in the manual editor for review — nothing is saved until you press save. If the selected model has no vision support, the photos go through the phone's on-device OCR first and only the text is sent. If the model fails to produce valid JSON twice in a row, the raw answer is kept as a free-text block: your input is never discarded.

**AI import through your own chat (no key at all).** The same import with the model outside the app, in two guided steps. Step one takes your plan — typed, pasted, or photographed and read by the phone's on-device OCR into an editable field — and copies a self-contained prompt to the clipboard. You paste it into whichever AI chat you already use, then step two takes the answer back. The pasted text goes through the very same pipeline as the API route, and it does not have to be clean JSON: the parser digs the plan out of greetings, code fences, whole pasted conversations, trailing commas and stray comments. If it still cannot read it, you get the parser's own error formulated as a correction to paste back into the chat — the manual twin of the automatic retry — and, as a last resort, the answer is kept as a free-text block. No API key, no account, no network call: the app never talks to anyone here.

**First-run notice.** Before anything else opens, a blocking disclaimer states what the app is and is not: not a medical app and not medical advice, you train under your own responsibility, the plans and photos you load are yours and stay your responsibility, and an AI import can misread a plan — check it before you train. Acceptance is *versioned*: bumping `AppConstants.legalNoticeVersion` puts the notice back in front of everyone who accepted an older wording. The full terms live on the web and open in the **system browser** — the app embeds no WebView. The same text stays readable from *Impostazioni → Termini e responsabilità*.

## Getting started

Requirements: **Flutter 3.35.x** (Dart 3.9), and Android 8.0+ (`minSdk 26`) or iOS 15.6+.

On iOS the lock-screen Live Activity is a second Xcode target that needs an App Group enabling once on your developer account — [docs/ios-live-activity.md](docs/ios-live-activity.md). Skip it and the app still builds and runs; you just get no banner.

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # ObjectBox + freezed + json_serializable
flutter run
```

`*.g.dart` and `*.freezed.dart` are generated and git-ignored, so the `build_runner` step is mandatory on a fresh clone — a clean checkout does not compile without it. `lib/objectbox-model.json` is the opposite: it **is** versioned, and its UIDs must never be reused.

### AI setup (optional)

The app ships no API key and calls no service on its own. To enable the import: **Impostazioni → Intelligenza artificiale**, choose a provider — [OpenRouter](https://openrouter.ai), [Anthropic](https://console.anthropic.com) or [Google Gemini](https://aistudio.google.com/apikey) — paste its key, pick a model, and use *Prova connessione* to verify it. Key and model are stored **per provider**, so switching back and forth costs nothing: the key is kept in the platform secure storage (iOS Keychain / Android Keystore) — never logged, never exported, never written to the database. Requests are billed to *your* account with the provider you picked.

A key is only needed for the automatic route. **Schede → Nuova scheda → Con la tua chat AI** does the same import with no key and no setup at all, by handing the prompt to whatever AI chat you already have open.

Providers and models are **configuration, not code**: edit [`assets/ai/models.json`](assets/ai/models.json), which is read once at startup.

| Provider field | Meaning |
| --- | --- |
| `id` | `openrouter`, `anthropic` or `google` — the three implementations; any other id is ignored |
| `label` | Name shown in the settings dropdown, and in the privacy notice |
| `keyHint` | Placeholder of the API key field (e.g. `sk-ant-…`) |
| `defaultModelId` | The model used before the user picks one |
| `models` | The models offered for this provider |

| Model field | Meaning |
| --- | --- |
| `id` | Model id at the provider (`anthropic/claude-sonnet-5` on OpenRouter, `claude-opus-5` on Anthropic, `gemini-3.7-flash` on Google) |
| `label` | Name shown in the settings dropdown |
| `supportsVision` | `false` ⇒ photos are OCR'd on-device and only text is sent |
| `supportsJsonSchema` | `false` ⇒ falls back to prompt-based JSON extraction |
| `maxOutputTokens` | Output budget for one answer (default 8192); too low truncates long plans |
| `disableReasoning` | OpenRouter only: sends `reasoning: {effort: none}` — reasoning tokens eat the same budget |
| `effort` | Where thinking is dosed rather than switched off: `output_config.effort` on Anthropic (`low`…`max`), `thinkingConfig.thinkingLevel` on Google (`low`/`medium`/`high`). Omit it for Claude Haiku 4.5, which rejects the parameter; Gemini 3.7 Flash rejects `minimal` |

Top-level, `defaultProviderId` picks the provider preselected before the user chooses.

## Architecture

Dependencies point strictly downward:

```
Widgets (features/*/pages, widgets)
   └─> Cubit / Bloc (feature state)
         └─> Repository interfaces (PlanRepository, WorkoutLogRepository, SettingsRepository)
               ├─> ObjectBox Store / Box
               └─> AiProvider ──> dio ──> OpenRouter | Anthropic | Google
```

`AiProvider` is one interface with one implementation per provider; the shared §6.2 pipeline (transcribe → structure → retry → free-text fallback) lives in `ChatPlanProvider`, so a provider only has to speak its own protocol. Which one runs is decided per call by `RoutingAiProvider`, from the choice saved in settings.

The UI never touches a repository or a service directly; a Cubit never touches `Box`, `dio` or secure storage. `Box`/`Store` may only appear inside `data/`. DI is explicit composition in `lib/app/di.dart` — no service locator.

```
lib/
  app/        composition root, router, theme
  core/       design tokens (colour, type, radius, spacing, icons), shared widgets
  data/       ObjectBox store, entities, repositories
  features/   plans · ai_import · workout · history · settings · legal
  services/   ai · timer · notifications · live_session · images (OCR, off-screen rendering) · share · clipboard · feedback · wakelock · links
```

Decisions worth knowing before you read the code:

- **ObjectBox entities double as the domain model.** They are plain Dart objects; the repository pattern is the boundary, and there is no parallel domain layer. DTOs exist only at the AI edge.
- **Cubit for CRUD, list and form state; Bloc only where the flow is genuinely event-driven.** The single Bloc is `WorkoutSessionBloc`, whose inputs arrive from the user, the timer and the app lifecycle, and where ordering matters.
- **ObjectBox does not cascade updates**, so repositories walk the object tree, `put` every child explicitly, and delete the ids that disappeared. That is what makes the editor and the session autosave actually persist.
- **`ToMany` does not preserve order**, so every child carries an `int sortOrder` and repositories return already-sorted lists. Enums are persisted as strings.
- **One AI pipeline, in `plan_parser.dart`**: extract JSON → decode → validate → normalize → one automatic retry with the validation error fed back to the model → free-text fallback. Both import routes end here, the keyless one included — what changes is only who performs the corrective retry. Normalization exists because models emit one block per exercise while a block is a *grouping*.
- **Appearance lives in two places only** — `lib/app/theme.dart` (every component theme) and `lib/core/design/` (colour, spacing, radius, typography and icon tokens). Pages pass no hand-written colours, radii or paddings; user-facing strings go through the ARB file, never inline.
- **One visual language, one theme.** The look comes from a design file, not from a Material seed colour: near-white background, white cards at radius 26, ink `#192126`, a single lime accent `#BBF246` reserved for the one live thing on screen (the plan in use, the current exercise, the active tab). Lato for the interface, the platform font for prose. There is deliberately no dark theme — it was never designed — so `themeMode` is pinned to light.
- **Nothing opens inside the app.** The one external link — the terms and conditions — is handed to the system browser through `LinkOpener` (`url_launcher` in `LaunchMode.externalApplication`), and the app copies the link to the clipboard if no browser answers. There is deliberately no in-app browser: a WebView is one more surface to declare and maintain.
- **The lock screen is a service, not a widget.** `services/live_session/` publishes an immutable snapshot to whatever surface the platform offers and hands back the confirmations that arrive from it; the two implementations share nothing but that contract. Because the button runs without the app (an iOS App Intent, an Android background isolate), confirmations go through a durable queue and are applied with the timestamp of the tap, while the surface itself is moved forward one step on the spot — the same arithmetic written once in Dart and once in Swift.
- **Exporting a plan means re-drawing it, not screenshotting it.** `WidgetImageRenderer` mounts a throwaway element tree with its own `RenderView`, constrained in width and free in height, and paints it into a `RepaintBoundary`. A boundary inside the real page could only ever capture the visible part of the viewport. The consequence is that the widget it draws (`PlanShareImage`) has to carry its own `Directionality`, `MediaQuery`, `Localizations` and `Theme`: there is no `MaterialApp` above it.
- **Icons are drawn, not fonted.** `lib/core/design/linear_icons.dart` holds the real glyphs of the design's icon set as SVG path data, painted by `LinearIcon`. Material icons are not used in the UI: their optical grid is visibly foreign next to these shapes.

The visual design (colours, typography scale, icon set, layout) is adapted from the free [Gym Full](https://www.figma.com/community/file/1415305484748482666/gym-full-figma) Figma community file.

## Testing

```bash
flutter test                          # unit + widget tests
flutter test test/path/to/foo_test.dart
flutter analyze
dart format .
```

`test/` mirrors `lib/`. The repository tests need the ObjectBox **native library** on the host; without it they skip themselves instead of failing. To run them locally:

```bash
bash <(curl -s https://raw.githubusercontent.com/objectbox/objectbox-dart/main/install.sh)
```

`integration_test/` holds end-to-end flows and needs a device or emulator (`flutter test integration_test`). Note that `bloc_test` is deliberately absent — its `test` constraint conflicts with `json_serializable` on Dart 3.9 — so Bloc tests dispatch events and assert on `bloc.state` after `pumpEventQueue()`.

## Roadmap

- Locales beyond Italian
- Verifying background timer punctuality on iOS

Conversational plan creation is *not* on the list: the AI is there to digitise a plan you already have, and editing it afterwards is the manual editor's job.

## How this was built

This app was developed with the help of AI coding assistants, working against a written functional and technical specification. The specification, the architecture decisions and the review of what goes in are the maintainer's; `CLAUDE.md` in the repository root is the working agreement those tools follow, which is why it reads like a style guide rather than documentation.

Said plainly so nobody has to guess: a large part of this code was written by a model and read by a human, not the other way round. Judge it on the tests, the CI and the code itself.

## Contributing

Bug reports and pull requests are welcome — start with [CONTRIBUTING.md](CONTRIBUTING.md). For anything security-related, read [SECURITY.md](SECURITY.md) first and do not open a public issue.

## License

Licensed under the [Apache License 2.0](LICENSE) — Copyright © 2026 Dorin Tverdohleb.

You may use, modify and redistribute this code, including commercially, provided you keep the copyright notice, the license and the [NOTICE](NOTICE) file, and state the changes you made. The license covers the code: it does not grant rights to the "Tacca" name as a project identity (Apache-2.0, section 6).
