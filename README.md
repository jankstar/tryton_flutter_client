# Tryton_Flutter_Client

A Flutter client for the [Tryton ERP system](https://www.tryton.org/), providing a native cross-platform interface that communicates with a Tryton server using the same JSON-RPC 2.0 protocol as the official [SAO web client](https://foss.heptapod.net/tryton/sao).

## Features

### Authentication & Session
- Login with database selection, MFA support, and device cookie ("stay logged in")
- Server URL and last-used database persisted across app restarts
- Automatic session renewal on 401 — compact re-login dialog (username + password only), original request retried transparently
- Persistent session: app reconnects on next start without requiring a full login

### Menu & Navigation
- Full Tryton menu tree loaded from the server with expand/collapse
- SVG icons from `ir.ui.icon` with Material Design fallback for LOCAL_ICONS
- Action domain filtering via PYSON evaluation (`ir.action.act_window.pyson_domain`)
- User info chip (top right): name, currency, avatar initials, dropdown with Preferences / Help / Sign out

### List Views (Tree)
- Server-driven columns from `fields_view_get` with correct order and labels
- Hierarchical tree views with lazy expand/collapse (`field_childs`)
- Auto-detection of self-referential models when `field_childs` is not set
- Explicit search button (no request on every keystroke — like SAO)
- SAO-style toolbar: Switch (⇄), New, Reload, Duplicate, Delete, Attachment, Action, Relate, Print, Email, Close
- Buttons enabled only when a record is selected (except Reload, New, Close)
- Record navigation context for Prev/Next in form view
- Many2One name resolution with session-level batch cache (`listEquals` comparison to prevent redundant reloads)

### Form Views
- Server-driven layout from XML arch (`fields_view_get`): grid, groups, notebooks, tabs
- PYSON states evaluation for `invisible`, `readonly`, `required` per field and per notebook page
- Required fields shown with red asterisk `*`
- SAO-style toolbar: Prev/Next record, New, Save, Reload, Duplicate, Delete, View Logs, Attachment (badge), Note, Action, Relate, Print, Email, Close
- Translated model name from `ir.model` shown in AppBar
- Record position indicator (e.g. `3 / 47`)
- Binary fields (e.g. avatar) excluded from read to avoid non-JSON responses

### Field Types
- `char`, `text`, `integer`, `float`, `numeric` — text input; on_change RPC triggered on focus loss only (not on every keystroke, like SAO)
- `selection` — dropdown; on_change triggered immediately
- `date`, `datetime` — date/time pickers
- `boolean` — checkbox
- `many2one` — autocomplete search, open-in-form button, clear button, async rec_name loading
- `one2many`, `many2many` — inline embedded tree with Add, Switch, Undelete, Delete; strikethrough for pending deletions (committed on parent save)

### Performance
- `on_change` RPC only on field blur (focus loss), not on every keystroke
- `listEquals` for collection parameters in `didUpdateWidget` — prevents spurious reloads
- Session-level caches: Many2One names, model display names, icons
- Binary fields skipped in `read()` to avoid non-JSON server responses

### Internationalisation
- 11 languages: English, German, French, Spanish, Portuguese, Polish, Danish, Dutch, Swedish, Finnish, Russian
- Language selector on the login screen; persisted via `shared_preferences`
- All UI strings via Flutter `AppLocalizations` (ARB files in `lib/l10n/`)

## Platforms

Targets all Flutter platforms. Tested on **macOS**. iOS, Android, Web, Linux, and Windows are also configured.

## Architecture

Clean Architecture in three layers:

```
lib/
├── core/
│   ├── icons/          # SVG icon cache + TrytonIcon widget
│   ├── l10n/           # LocaleProvider, BuildContext.l10n extension
│   ├── pyson/          # PYSON expression evaluator (Eval, Not, Bool, Equal, In, …)
│   ├── rpc/            # JSON-RPC 2.0 client (dio), ReAuthService, exception types
│   ├── serialization/  # Tryton ↔ Dart type conversion (DateTime, Decimal, Bytes)
│   ├── session/        # Session management, device cookie, persistence
│   └── xml/            # fields_view_get parsing, form/tree XML parser
├── features/
│   ├── actions/        # Action executor (act_window, report, wizard)
│   ├── auth/           # Login, re-login dialog, session provider, user preferences
│   ├── model/          # ModelService CRUD, FieldDefinition, TrytonRecord, TrytonToolbar
│   ├── tabs/           # Menu browser screen, user chip
│   └── views/          # DynamicFormScreen, ListViewScreen, EmbeddedTreeWidget,
│                       # navigation context (Prev/Next)
├── l10n/               # ARB localisation files (11 languages)
└── shared/
    └── widgets/        # FieldWidget, ToolbarDropdownButton, _TextInputField
```

**State management:** Riverpod  
**Navigation:** GoRouter  
**HTTP:** dio + CookieJar  
**SVG rendering:** flutter_svg  
**Localisation:** flutter_localizations + gen_l10n

## Protocol

Communicates with the Tryton server via JSON-RPC 2.0:

```
POST /{database}/rpc/
{ "id": 1, "method": "model.party.party.search_read", "params": [..., context] }
```

Special Tryton types handled by `TrytonSerializer`:

| Tryton type | JSON encoding |
|-------------|---------------|
| `datetime`  | `{"__class__": "datetime", "year": ..., ...}` |
| `date`      | `{"__class__": "date", ...}` |
| `Decimal`   | `{"__class__": "Decimal", "decimal": "123.45"}` |
| `bytes`     | `{"__class__": "bytes", "base64": "..."}` |

Error types handled: `UserError`, `UserWarning`, `ConcurrencyException`, `LoginException`, 503 retry with backoff, 401 automatic re-authentication.

### Session Authentication (like SAO)

| Layer | Mechanism | Storage |
|-------|-----------|---------|
| HTTP session cookie | Short-lived, per-request | Browser / CookieJar |
| Device cookie | Long-lived, passwordless login | `shared_preferences` |
| Session data | `database`, `login`, `user_id` | `shared_preferences` |

On 401: `ReAuthService` pauses the failed request, shows a compact re-login dialog, and retries automatically after success — identical to SAO's `Session.renew`.

## Getting Started

### Prerequisites

- Flutter SDK ≥ 3.19 (Dart SDK ≥ 3.12)
- A running Tryton server (8.x)
- macOS entitlement `com.apple.security.network.client` is already set

### Install dependencies

```bash
flutter pub get
```

### Generate localisations

```bash
flutter gen-l10n
```

### Run on macOS

```bash
flutter run -d macos
```

### Run on other platforms

```bash
flutter run -d ios        # requires Xcode
flutter run -d android    # requires Android SDK
flutter run -d chrome     # web
```

### Build

```bash
flutter build macos
flutter build apk
flutter build ios
```

## Configuration

On first launch, enter the Tryton server URL (e.g. `http://localhost:8000`), select the database, and log in. Server URL and database are persisted and pre-filled on subsequent starts. Only username and password need to be re-entered.

## Key Dependencies

| Package | Purpose |
|---------|---------|
| `dio` + `dio_cookie_manager` | HTTP client with cookie-based session |
| `flutter_riverpod` | State management |
| `go_router` | Declarative navigation |
| `xml` | XML arch parsing |
| `flutter_svg` | SVG icon rendering |
| `shared_preferences` | Session and locale persistence |
| `flutter_localizations` | 11-language UI |
| `intl` | Date/number formatting |
| `url_launcher` | Help link |
| `google_fonts` | Lato typeface |

## Tryton Compatibility

Tested with Tryton **8.x**. The protocol implementation follows the [SAO web client](https://foss.heptapod.net/tryton/sao) version **8.0.0** as reference.

## License

GPL-3.0 — same as Tryton. See [LICENSE](LICENSE) and [COPYRIGHT](COPYRIGHT).

## Third-Party Fonts

### Lato

**Designer:** Łukasz Dziedzic / tyPoland  
**Source:** [Google Fonts — Lato](https://fonts.google.com/specimen/Lato)  
**License:** [SIL Open Font License 1.1](https://openfontlicense.org/)

> Copyright (c) 2010–2014 by tyPoland Lukasz Dziedzic (team@latofonts.com)
> with Reserved Font Name "Lato".
>
> This Font Software is licensed under the SIL Open Font License, Version 1.1.
> This license is available with a FAQ at https://openfontlicense.org/

Lato covers Latin, Latin Extended, and Cyrillic character sets, supporting all
11 application languages: English, German, French, Spanish, Portuguese, Polish,
Danish, Dutch, Swedish, Finnish, and Russian.
