# Security Policy

Tacca stores workout data locally and, if you enable the AI import, talks to a third-party API with **your** key. That makes two things worth protecting: the API key and the data on the device.

## Supported versions

This is a pre-1.0 personal project. Only the current `main` branch is supported — fixes land there, and there are no backports.

## Reporting a vulnerability

**Do not open a public issue for a security problem.**

Use GitHub's private vulnerability reporting: go to the [Security tab](https://github.com/dorex96/tacca/security) of this repository and choose *Report a vulnerability*. That opens a private thread visible only to the maintainer.

If you'd rather not use GitHub, email **dorin@tverdohleb.dev** instead. Plain email is not encrypted, so keep the first message short — "there is an issue in X, can we move somewhere private" is enough.

Useful things to include: what an attacker can do, how you reproduced it, the affected version or commit, and the platform. A proof of concept helps more than a description.

What to expect: this is a spare-time project maintained by one person, so the honest commitment is an acknowledgement within about a week and a fix, or an explanation of why it will not be fixed, once the issue is understood. Please give the fix a reasonable window before disclosing publicly; you'll be credited when it lands unless you'd rather not be.

**Never paste an API key, a key fragment, or a real device backup into a report, an issue or a pull request.** If you have leaked a key, revoke it immediately — at [openrouter.ai/settings/keys](https://openrouter.ai/settings/keys) for OpenRouter, at [console.anthropic.com/settings/keys](https://console.anthropic.com/settings/keys) for Anthropic, at [aistudio.google.com/apikey](https://aistudio.google.com/apikey) for Google. A key stays valid until you do.

## In scope

- Anything that exposes a stored API key (OpenRouter, Anthropic or Google) to another app, to a log, to a crash report, to an exported file or to the network beyond the intended request — including sending it to a provider other than the one it belongs to.
- Anything that lets a third party read or modify the local database or the plan images without the user's action.
- Injection or code-execution paths through the AI import: a hostile plan photo, a hostile pasted text, or a hostile model response walking through the parser.
- A crafted backup file that, once picked for a restore, writes anywhere outside the app's own image folder, or changes the database without the user's confirmation, instead of being rejected.
- A vulnerable dependency that is actually reachable from this app's code.

## Out of scope

- Physical access to an unlocked device, and rooted or jailbroken devices — the platform secure storage cannot defend against an attacker who already owns the OS.
- The fact that the AI import sends your images or text to the selected provider and model: that is the documented purpose of the feature, the provider is named in the UI, and it only ever happens after an explicit user action.
- Charges on your own provider account caused by your own use.
- Reports produced by an automated scanner with no demonstrated impact on this app.

## How the app handles secrets, for reference

API keys are written only to `flutter_secure_storage` (iOS Keychain / Android Keystore) by `SecureSettingsRepository`, one entry per provider (`ai.openrouter.apiKey`, `ai.anthropic.apiKey`, `ai.google.apiKey`). A key is never written to ObjectBox, never included in an export or a backup, never logged, and never leaves the device except as the authentication header (`Authorization` for OpenRouter, `x-api-key` for Anthropic, `x-goog-api-key` for Google) of a request to *that same provider*, triggered by the user. The repository ships no key of its own, and `android/key.properties`, which holds the Android signing credentials on the maintainer's machine, is git-ignored and must never be committed.

## Local backups, for reference

*Impostazioni → Backup* writes a `.tacca` file with every plan, the whole workout history and the original photos of imported plans, and hands it to the system share sheet: where it goes is the user's choice. The file is **not encrypted** — treat it like the photos and notes it contains — and it holds **no settings and no API keys**, which stay in the platform secure storage of the phone they were entered on. Restoring a backup only happens after the user picks a file and confirms a dialog that states what will be replaced; the file is validated in full before anything changes, and no path or file name from it is ever used on disk.
