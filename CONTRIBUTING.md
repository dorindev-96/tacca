# Contributing to Tacca

Thanks for taking a look. Tacca is a personal project built against a written specification, so the fastest way to get a change merged is to understand the constraints before writing code.

## Before you start

- **Open an issue first** for anything larger than a typo, a bug fix or a translation. Describe the problem, not only the patch.
- **The architecture decisions are settled**: ObjectBox as the database, `flutter_bloc` for state, `go_router` for navigation, `dio` for HTTP, bring-your-own-key AI with no backend of our own. A PR that swaps one of them out will be declined however good it is — those are load-bearing choices, not defaults nobody thought about.
- **The full functional and technical specification is not public** (it lives outside this repository, in Italian). If a behaviour looks arbitrary, it usually encodes a requirement — ask in the issue and you'll get the reasoning.
- `CLAUDE.md` at the repository root is the working agreement used when this codebase is edited with AI assistance. It is also the shortest complete description of the conventions below; read it.

## Setup

Flutter **3.35.x** (Dart 3.9), Android 8.0+ or iOS 15.6+.

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run

dart run build_runner watch     # regenerate while you work
```

`*.g.dart` and `*.freezed.dart` are generated and git-ignored, so a fresh clone does not compile before the `build_runner` step. `lib/objectbox-model.json` is the exception: it **is** versioned. Commit it whenever you touch an entity, and never reuse or hand-edit its UIDs — that file is how ObjectBox knows a field was renamed rather than dropped and re-added.

The launcher icons are generated, not hand-drawn per size. The four 1024×1024 sources live in `assets/icons/`; `flutter_launcher_icons.yaml` turns them into the iOS asset catalog, the Android mipmaps and the adaptive icon:

```bash
dart run flutter_launcher_icons
```

Afterwards check `git diff ios/Runner.xcodeproj/project.pbxproj` and revert it: the package rewrites every line containing `ASSETCATALOG`, which breaks a build setting of the Live Activity extension. The Android status-bar icon (`res/drawable-*/ic_notification.png`) is **not** produced by that command — it is a separate monochrome silhouette at 24dp.

To run the repository tests locally you also need the ObjectBox native library on the host; without it they skip themselves:

```bash
bash <(curl -s https://raw.githubusercontent.com/objectbox/objectbox-dart/main/install.sh)
```

## Conventions

**Dependencies point downward, never up.** Widgets → Cubit/Bloc → repository interfaces → ObjectBox / `AiProvider`. The UI never touches a repository or a service directly, and a Cubit never touches `Box`, `dio` or secure storage. `Box`/`Store` may only appear inside `data/`. Dependency injection is explicit composition in `lib/app/di.dart` — no service locator, no `get_it`.

**Layout and naming.** Feature-first under `features/`, shared data layer under `data/`, no barrel files (import directly). Files are `snake_case.dart`; classes end in `Cubit`, `Bloc`, `Repository`, `Page` or `Dto`.

**State management.** Cubit for CRUD, lists and forms. Bloc only where the flow is genuinely event-driven and ordering matters — today that means `WorkoutSessionBloc` alone. Two rules there: every state-mutating handler persists the log immediately (that autosave *is* the crash-recovery feature, not a periodic save), and nothing ever emits from an external callback — the Bloc subscribes to `TimerEngine.stream` and re-dispatches a `TimerTicked` event.

**Exporting a plan as an image.** *Condividi* in the plan detail does not screenshot the page — a `RepaintBoundary` inside a `ListView` only ever holds the visible part of the viewport. `WidgetImageRenderer` (`services/images/`) mounts a throwaway element tree with its own `RenderView`, tight in width and unbounded in height, and paints `PlanShareImage` into it. Two rules follow: the exported widget must be self-sufficient (no `Expanded`, no scrollable, and it carries its own `Directionality`, `MediaQuery`, `Localizations` and `Theme`, because nothing sits above it), and the read-only plan widgets it shares with the detail page live in `features/plans/widgets/plan_day_view.dart` — one plan, one layout, whether you are reading it or sending it.

**Native code.** There is a little, and it is the part CI cannot see: the iOS Live Activity (`ios/TaccaLiveActivity/`, `ios/LiveSessionShared/`, `ios/Runner/LiveSessionBridge.swift`) and the Android ongoing notification. Keep the platform-specific part behind a Dart interface — `LiveSessionController` is the example — so the logic worth testing stays in Dart and the native side only draws and forwards. If you touch it, say in the PR what you ran it on: the Linux runner builds neither, and the checklist in [docs/ios-live-activity.md](docs/ios-live-activity.md) is the substitute for tests.

**Data layer.** `ToMany` does not preserve order, so every child has an `int sortOrder` and repositories return sorted lists. Enums are stored as `String` with a `@Transient()` getter. Block parameters are flat nullable fields — no polymorphism, no JSON blobs. ObjectBox does **not** cascade updates: a repository that writes an aggregate must walk the tree, `put` every child explicitly and delete the ids that disappeared, exactly like `savePlan` and `saveLog`. History is snapshot-based on purpose: logs keep the plan and exercise names so they stay readable after the plan changes.

**Appearance.** Component themes live in `lib/app/theme.dart`; the tokens they are built from live in `lib/core/design/` — `AppColors`, `AppTypography`, `AppRadius`, `AppSpacing`, plus the icon set in `linear_icons.dart`. Pages pass no hand-tuned numbers and no raw hex.

The visual language is fixed: background `#F4F4F6`, white surfaces at radius 26, ink `#192126`, prose in `#232A3A`, secondary text `#8C9092`, hairlines `#D4D8E0`, and one lime accent `#BBF246` — text on lime is always ink. **One lime element per screen**, because that is the whole mechanism by which "what is live right now" reads at a glance; a second one destroys the first. Pink `#FF5678` is destructive, and it appears as text (menu entries, "Rimuovi serie") everywhere except the final delete confirmation, which is the only place it becomes a fill.

Type is Lato for the interface and the platform font for paragraphs — a long paragraph set in tight Lato does not read. Google Fonts publishes Lato at 400/700/900 only; the design's nominal 500 and 800 do not exist, so the tokens use the real weights.

Icons come from `AppIcons` (the design's own set, drawn by `LinearIcon` from SVG paths). Do not reach for `Icons.*` in the UI; if a glyph is missing, take it from the design file rather than substituting a Material one.

Recurring pieces live in `lib/core/widgets/`: `AppScaffold` (page shell: header of square icon buttons, big title, docked pill), `PillButton`, `SquareIconButton`/`GhostIconButton`, `SurfaceCard`, `MetaChip`, `Section`/`SectionHeader`, `EmptyState`, `InfoBanner`, `AppSheet`/`showAppSheet`, `AppField`, `AppMenuButton`, `showConfirmDialog`. Tap targets stay ≥ 48dp even where the design draws 40 — `SquareIconButton` paints 40 inside a 48 target on purpose.

Bottom sheets must open on the **root** navigator (`showAppSheet` does): the floating tab bar lives in the shell's `Stack`, so a sheet opened on the branch navigator renders underneath it.

**Strings.** Every user-facing string goes through `lib/l10n/app_it.arb`. Never hardcode text in a widget, not even temporarily.

**Legal notice.** The first-run disclaimer (`features/legal`) is a gate mounted above the router: nothing else is built until it is accepted, and acceptance is stored as a *version*, not a boolean. Its wording lives in exactly one widget and one ARB block, shown both by the gate and by *Impostazioni → Termini e responsabilità*; if the substance of the terms changes, bump `AppConstants.legalNoticeVersion` so everyone sees it again. The full terms open in the system browser through `LinkOpener` — there is no in-app WebView, and adding one would need a reason.

**AI layer.** All provider responses go through the single pipeline in `plan_parser.dart` (extract → decode → validate → normalize → one retry → free-text fallback). Validation runs before normalization deliberately: its messages are fed back to the model. API keys are read from secure storage, never logged, never persisted anywhere else. No network call happens without an explicit user action, and everything except the AI import must keep working offline. The selectable providers and models are configuration in `assets/ai/models.json` — adding a model is not a code change. Adding a *provider* is: the shared pipeline lives in `ChatPlanProvider`, so a new implementation only translates turns into its own protocol and maps its errors, plus an `AiProviderId` value and an entry in the map in `di.dart`. The keyless import (`AiPasteImportCubit`, `/plans/new/import/paste`) shares that same pipeline without any provider: it copies `externalChatPrompt` to the clipboard and parses whatever the user pastes back, so prompt rules changed for one route must stay shared with the other — they live together in `prompts.dart`.

**Comments.** The existing comments and docs in the code are in Italian; match the language of the file you are editing. Issues and PR descriptions can be in Italian or English.

**Dependencies.** Adding a package is a real cost for an offline app that stores personal data. Say in the PR why the standard library or the existing dependencies are not enough.

## Tests

`test/` mirrors `lib/`.

```bash
flutter test
flutter test test/services/timer/timer_engine_test.dart
flutter test --name "substring"
flutter test integration_test          # needs a device or emulator
```

Things that will bite you:

- `bloc_test` is deliberately absent — its `test` constraint conflicts with `json_serializable` on Dart 3.9. Bloc tests dispatch events and assert on `bloc.state` after `pumpEventQueue()`.
- Tests touching localized dates need `initializeDateFormatting('it')` in `setUpAll` (production does it in `main()`).
- A widget test that mounts a session must inject a `TimerEngine` with a long `tickInterval`, otherwise the periodic timer keeps scheduling frames and `pumpAndSettle` never settles.
- Repository tests open a real ObjectBox `Store` in a temp directory created in `setUp` and removed in `tearDown`; Cubit and Bloc tests use `mocktail` or the in-memory fakes in `test/support/fakes.dart` over the repository interfaces — never a real database.

## Before opening a pull request

```bash
dart format .
flutter analyze
flutter test
```

CI runs the same three on Ubuntu and fails on any formatting difference. Keep the PR focused on one thing, explain the why in the description, and call out explicitly if you changed `lib/objectbox-model.json` (database schema) or added a dependency.

Using an AI assistant to write the patch is fine — this codebase was built that way. What is not fine is submitting code you cannot explain: you own what you open the PR with, and "the model wrote it" is not a review answer.

## Licensing of contributions

By submitting a pull request you agree that your contribution is licensed under the [Apache License 2.0](LICENSE), the same license as the project, as described in section 5 of that license. Copyright stays with you; the project keeps the right to distribute it under Apache-2.0.

## Conduct

Be civil, be concrete, assume the other person had a reason. Harassment, personal attacks or bad-faith argument get the thread locked and the account blocked — there is no longer document behind this one.
