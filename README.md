# Tryton Flutter Client

A native cross-platform client for the [Tryton ERP system](https://www.tryton.org/), written in Flutter. It talks to a Tryton server (**trytond 8.0**) with the same protocol as the official clients and ports their client logic to Dart. The **Tryton desktop client 8.0 (Python/GTK)** is the primary reference for behaviour and features; the **SAO web client** is used as a supplementary reference for asynchronous flows and the mobile/responsive layout.

> **Status:** feature-complete against the internal specification; manual acceptance testing on macOS, iOS and Android is in progress. Not yet released.

## Features

**Connection & session**
- Server URL, database list (`common.db.list`), version check
- Multi-step login (password, MFA/other `LoginException` steps), device cookie as brute-force protection
- Session token (`Authorization: Session …`) stored in the OS keychain/keystore (`flutter_secure_storage`) – reconnect after restart without logging in; the password is never stored
- Automatic re-login on 401 with transparent retry; logout invalidates the session on the server
- Connection profiles (server, database, user)
- User preferences dialog; language, company and employee switching with context reload

**Main window**
- Menu tree from the server (module icons via `ir.ui.icon`), menu search / global search, favourites
- Tabs on desktop, navigation stack on mobile; warning on unsaved changes
- Record menu (title dropdown) with all toolbar functions and keyboard shortcuts as in the Python client

**Data layer** (port of the Python client `model/*`)
- Model / Group / Record / Field with lazy loading, `on_change` / `on_change_with`, validation, `_timestamp` concurrency check (conflict dialog), x2many write commands
- PYSON evaluator/encoder, domain inversion, domain parser (Tryton search syntax)
- Client-side metadata and RPC caches (`X-Tryton-Cache`)

**Views**
- Form: XML grid layout (`col`, `colspan`, `expand`, groups, notebooks, expanders, paned), floating labels, `states`, buttons, links with counters, images, translation dialog
- All field widgets: char, text, integer, float, numeric, date, datetime, time, timedelta, boolean, selection, multiselection, many2one, reference, one2many, many2many, binary/image/document preview, rich text, URL/e-mail/phone, progress bar, colour, password
- One2many/many2many: embedded list = full tree view, toolbar as in the Python client, popup forms, `add_remove`, `size`, `sequence`, `product`, `pre_validate`
- Tree/list: paging, sorting, tree expand/collapse, editable rows, sums, column widths and optional columns, context menu, copy/paste, drag & drop on `sequence`, `visual`
- list-form (mobile cards), graph (bar/line/pie with `graph_open`), calendar (month/week/day, drag & drop), board

**Actions, wizards, reports**
- `act_window`, wizards, reports (open, share, print), URLs, keywords (`tree_open`, `form_relate`, `graph_open`), client actions
- Deep links `tryton://…` (macOS, iOS, Android)

**Additional windows**
- Attachments (incl. preview side panel), notes, logs, revisions
- CSV export (predefined exports, export URL) and CSV import
- E-mail with templates, reports and attachments
- Code scanner (`scan_code`): camera on mobile/macOS, keyboard/hand scanner input on desktop

**Notifications**
- Bus long polling (`client:` / `notification:` channels), notifications with badge, chat on records

**Internationalisation**
- 11 UI languages: English, German, French, Spanish, Portuguese, Polish, Danish, Dutch, Swedish, Finnish, Russian
- Server translations via the language in the context; date, number and duration formats from the user's language

## Platforms

| Platform | Status |
|---|---|
| macOS (≥ 12) | primary development platform |
| iOS (≥ 15), Android | supported, acceptance tests in progress |
| Windows, Linux, Web | configured, not tested |

## Getting started

Prerequisites: Flutter SDK with Dart ≥ 3.12, a Tryton 8.0 server.

```bash
flutter pub get
flutter gen-l10n          # after changing lib/l10n/app_*.arb
flutter run -d macos      # or: -d ios, -d android
```

On first start enter the server URL (e.g. `http://localhost:8000`), choose the database and log in.

Build:

```bash
flutter build macos
flutter build ios
flutter build apk
```

## Tests

```bash
flutter analyze
flutter test                                   # unit and widget tests

# integration tests against a test server
# (http://127.0.0.1:8000, database "tryton", user "admin")
TRYTON_PASSWORD=… flutter test --run-skipped -t integration
```

Integration tests only read data, or create records with the prefix `CLAUDE-TEST` and delete them again.

## Architecture

Riverpod for state, Dio for HTTP, GoRouter for top-level routes.

```
lib/
├── core/
│   ├── domain/         # domain parser, domain inversion, date text
│   ├── icons/          # Tryton icons (bundled tryton-* and ir.ui.icon)
│   ├── l10n/           # locale provider
│   ├── model/          # Model, Group, Record, Field (data layer)
│   ├── pyson/          # PYSON evaluator, encoder, environment
│   ├── rpc/            # RPC client, cache, errors, re-login, bus
│   ├── screen/         # Screen, graph and calendar logic, Tryton URLs
│   ├── serialization/  # Tryton JSON types (datetime, Decimal, bytes, …)
│   ├── session/        # session, secure session store, profiles
│   ├── theme/          # light/dark theme
│   ├── wizard/         # wizard runtime
│   └── xml/            # view XML parsing
├── features/
│   ├── actions/        # action service, deep links, URL opener
│   ├── auth/           # login, re-login, preferences, start sequence
│   ├── model/          # model services, metadata, concurrency
│   ├── notifications/  # notifications
│   ├── shell/          # app shell, tabs
│   ├── tabs/           # menu sidebar, user chip
│   └── views/          # form, tree, list-form, graph, calendar, board,
│                       # widgets, dialogs (search, CSV, e-mail, scanner, …)
├── l10n/               # ARB files (11 languages)
└── shared/             # dialogs, error handling, utils, widgets
```

## Protocol

JSON-RPC in Tryton's 1.0 style – the body contains exactly `id`, `method` and `params` (no `jsonrpc` field); the context is always the last parameter:

```
POST /{database}/rpc/
Authorization: Session base64(login:user_id:token)

{"id": 1, "method": "model.party.party.search_read", "params": [[], 0, 10, null, ["name"], {…context}]}
```

Tryton types are encoded with `__class__` (`datetime` in UTC, `date`, `time`, `timedelta`, `Decimal`, `bytes`). Handled errors: `UserError`, `UserWarning`, `ConcurrencyException`, `LoginException`, 401 (re-login), 503 (retry).

## Tryton compatibility

Developed and tested against **trytond 8.0**. Reference implementations: Tryton desktop client 8.0 (primary) and SAO.

## License

GPL-3.0-or-later, like Tryton. Large parts of the client logic are ports of the Tryton desktop client and SAO (both GPL-3.0-or-later).

Third-party components:
- Tryton UI icons (`assets/icons/tryton/`) – Apache License 2.0
- Lato font (`assets/fonts/`) – SIL Open Font License 1.1
- Flutter/Dart packages – BSD-3-Clause, MIT, Apache-2.0, MPL-2.0

Full copyright and license details: [COPYRIGHT](COPYRIGHT), license text: [LICENSE](LICENSE).
