# fx-widget

`fx-widget` is a native macOS exchange-rate board built with Swift, SwiftUI, WidgetKit, App Intents, and Foundation. The widget is the primary product surface; the host app currently exists mainly to install and register the widget extension.

This README assumes that macOS is set to English. Currency and number formatting still follow the user's locale and region. In particular, the default reference currency follows the regional currency when the provider supports it; the UI language does not force the reference currency. For example, macOS can use English while the region remains Korea and the default reference currency remains KRW.

Contributors should read `AGENTS.md` and the documents under `docs/` before changing product behavior. `docs/DECISIONS.md` is the source of truth when specifications conflict.

## Current status

The current pre-release implementation includes:

- native macOS app and WidgetKit extension;
- macOS 15 or later deployment target;
- Medium, Large, and Extra Large widget families;
- fixed capacities of 3, 10, and 20 currencies respectively;
- one-column Medium and Large layouts and a vertically filled two-column Extra Large layout;
- default membership derived from the bundled validated 2025 final BIS FX-turnover ranking;
- regional default reference currency with USD fallback;
- localized representative-region and currency-unit labels, shown by default;
- locale-aware adaptive rate formatting and absolute daily change;
- provider-basis date and last-successful-refresh time in the footer;
- interactive manual refresh through an App Intent;
- per-widget configuration: reference currency, per-row quote currency slots, row count, currency
  name toggle, and UI language;
- a per-widget UI language covering names, labels, and dates while numeric separators keep following
  the system region;
- a keyless Frankfurter v2 development/reference adapter; and
- widget-extension-owned atomic rate and metadata persistence without an App Group.

Frankfurter currently supplies runtime exchange-rate data, but it has not been selected as the final production provider. It is a daily reference-rate integration, not a real-time market feed. The widget intentionally does not show provider or app version text.

The default English-language row shape is similar to:

```text
Exchange Rates · KRW  South Korea · Won                    ↻
🇺🇸 USD United States · Dollar          1,415.22    ▼ 0.05
🇪🇺 EUR European Union · Euro           1,634.79    ▼ 0.85
🇯🇵 JPY Japan · Yen                         8.89    ▼ 0.01
As of Aug 14, 2026        Updated Aug 15, 2026 at 5:53 AM
```

Rate display is deliberately shallow for a glanceable board: two fraction digits at or above 1, up
to four below that, and compact scientific notation under 0.0001 rather than a row of leading zeros.
A nonzero value never renders as zero.

Rates use this direction:

```text
1 selected currency = X reference currency
```

For example, with KRW as the reference currency, `USD 1,415.22` means `1 USD = 1,415.22 KRW`. The values above are illustrative and must not be treated as fixed rates.

## Configuration

Control-click a widget and select `Edit fx-widget`:

```text
Language               System / English / Deutsch / Español / Français /
                       Italiano / 日本語 / 한국어 / Português (Brasil) /
                       简体中文 / 繁體中文
Currency Name          on
Reference Currency     KRW
Quote Currency Count   Auto (the family capacity) or 1…20
Quote Currency 1…N     one slot per row, 3 / 10 / 20 by family
```

Slot N is row N. Setting it pins that currency to that row; leaving it empty fills the row from
Default Order for the active reference currency, so changing the reference recalculates every
unpinned row while pinned rows stay put. Pinning a currency that Default Order did not contain
displaces one default entry; pinning one already on the board only moves it.

`Quote Currency Count` reduces the number of rendered rows but never exceeds the family capacity.

Every parameter is a scalar backed by a dynamic options list. `AppEntity`, `[AppEntity]`, and
`AppEnum` parameters were measured to render and accept edits in the macOS widget editor while never
being committed, so they are not used; see D-039. Two consequences are visible to users:

- the currency pickers have no free-text search, because search requires `AppEntity`. Entries read
  `USD  United States · Dollar` with the ISO code first, and the menu supports type-ahead on the code;
- the editor cannot show or hide controls in response to a value you just chose. Slot count follows
  the widget family, which is fixed when the editor opens.

The `Language` setting governs the widget's own content. The editor itself always follows the system
language, because it is system UI.

## Requirements

- macOS 15 or later
- Xcode 26, or another Xcode toolchain capable of building this Swift 6 project
- internet access for Frankfurter data

After installing Xcode, accept Apple's license before the first command-line build:

```sh
sudo xcodebuild -license
```

## Open and test the project

Open `FXWidget.xcodeproj` in Xcode. The project contains the host app, widget extension, shared `FXCore` target, and tests.

Run the core test suite from Terminal with:

```sh
swift test
```

Run the Xcode test scheme with:

```sh
xcodebuild \
  -project FXWidget.xcodeproj \
  -scheme FXWidget \
  -destination 'platform=macOS' \
  -derivedDataPath DerivedData \
  test
```

## Build an identity-less Release app

The checked-in configuration uses ad-hoc signing for the app and embedded widget extension:

- no Apple Development Team;
- no personal signing certificate;
- no provisioning profile;
- no Team identifier; and
- no App Group entitlement.

Build a universal `arm64` and `x86_64` Release app with:

```sh
xcodebuild \
  -project FXWidget.xcodeproj \
  -scheme FXWidget \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath DerivedData \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  clean build
```

The result is:

```text
DerivedData/Build/Products/Release/FXWidget.app
```

The checked-in bundle identifier prefix is `com.example`. To choose another identity-less prefix, copy the example before building:

```sh
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

Then edit only `FX_BUNDLE_ID_PREFIX` in the ignored `Config/Local.xcconfig`. Choose the prefix before placing widgets and keep it stable. Changing bundle identifiers later makes macOS treat the build as a different app and widget extension.

The persisted widget identifiers are also compatibility boundaries:

```text
Widget kind:       FXBoardWidgetV1
Configuration:     FXBoardConfigurationIntent
```

Do not rename either identifier to invalidate development caches. macOS stores them with every placed widget; changing them leaves existing placements without a matching descriptor and can produce a blank widget or a permanent placeholder.

## Install the local build

The complete app bundle must be installed in an Applications directory and launched once before adding the widget.

Do not merge a new build into an existing `FXWidget.app`. A bundle merge can leave stale Debug binaries or an old extension in place. In Finder, move the existing `FXWidget.app` to Trash or to a backup location first. Then copy the clean Release bundle:

```sh
mkdir -p "$HOME/Applications"
ditto \
  DerivedData/Build/Products/Release/FXWidget.app \
  "$HOME/Applications/FXWidget.app"
open "$HOME/Applications/FXWidget.app"
```

Keep only one active copy of the app while testing widgets. An app in Xcode DerivedData or another temporary build directory can be registered as a competing widget extension and cause macOS to load the wrong build. The installed Applications copy should be the one launched for desktop validation.

## Allow a downloaded build on macOS

An ad-hoc build is neither Developer ID signed nor notarized. When opening a downloaded build, macOS may block it because it cannot verify the developer.

With macOS set to English:

1. Attempt to open `FXWidget.app` once.
2. Open `System Settings`.
3. Select `Privacy & Security`.
4. Scroll to the `Security` section.
5. Select `Open Anyway` for `FXWidget.app`.
6. Confirm by selecting `Open`.

This approval does not add a developer identity or expose the builder's personal name.

## Add the widget

After launching the installed app once:

1. Control-click or right-click an empty area of the desktop.
2. Select `Edit Widgets…`.
3. Search for `fx-widget` or select it in the widget gallery.
4. Choose one of the three supported widget previews.
5. Add it to the desktop.
6. Select `Done`.

Supported WidgetKit families and fixed layouts are:

```text
Medium       3 currencies  × 1 column
Large       10 currencies  × 1 column
Extra Large 10 rows        × 2 columns (20 currencies)
```

Extra Large fills the first column from top to bottom before filling the second column. Widgets do not scroll. `+N` is reserved for an existing over-capacity configuration and is not part of the normal default layout.

To edit an existing widget, Control-click or right-click it and select `Edit fx-widget`. See
[Configuration](#configuration).

## Default Order and currency catalog

Default Order comes from the latest validated final BIS Triennial Survey dataset, `OTC foreign exchange turnover by currency` (D11.3). The bundled baseline is the 2025 final survey.

BIS supplies priority and order only. For each widget family, the app:

1. excludes the active reference currency;
2. excludes currencies unsupported by the active provider; and
3. continues down the BIS ranking until the family's capacity is filled.

The complete currency catalog is not limited to the default membership. It is derived from the intersection of modern Foundation/ISO currency data and currencies supported by Frankfurter. A separate BIS SDMX source can check official structured data for a newer validated final ranking at a low frequency; it does not supply exchange rates.

## Data, caching, and refresh behavior

- Frankfurter values are treated as date-only provider data; the app never invents a time of day.
- Current data uses the latest date shared by every required raw rate leg.
- Change uses the latest earlier shared date.
- A partial response for a currency the provider does publish fails the entire refresh atomically.
- A currency the active provider does not publish at all renders as a dash while every other row
  still resolves from one shared basis date. Such a currency stays selectable: that is one provider's
  gap, and another provider may quote it.
- The last successful snapshot remains visible after a refresh failure.
- A request key that has never succeeded retries on a backoff rather than freezing.
- Cache, refresh state, failures, and in-flight work are keyed by provider, reference currency, and the sorted unique selected currencies.
- Automatic provider-call eligibility is provider-specific. WidgetKit still controls when a timeline actually runs.
- Manual refresh requests fresh data but does not turn a daily feed into a real-time feed.

Runtime state belongs to the widget extension's own Application Support container. The host app and extension do not share an App Group cache.

## Troubleshooting

### The widget remains a redacted placeholder

- Confirm that the complete app is installed in `$HOME/Applications` or `/Applications`.
- Launch that installed copy once.
- Confirm that another Debug, DerivedData, or temporary copy is not registered as a competing extension.
- Rebuild and install the entire `.app`; do not copy only the `.appex`.
- Keep the bundle identifier prefix, `FXBoardWidgetV1` kind, and `FXBoardConfigurationIntent` configuration type stable across builds.

### The widget is blank after replacing the app

Confirm that the old app bundle was removed before installing the new one. Merging app bundles can retain stale signed files. Also confirm that the installed build uses the same bundle identifiers and widget kind as the placed widget instances.

### A configuration edit does not apply

First confirm the running extension is the installed copy and not a translocated one:

```sh
ps -axo pid,command | grep FXWidgetExtension | grep -v grep
```

A path under `/private/var/folders/.../AppTranslocation/` means macOS is running a quarantined copy
from a randomized read-only location, which breaks App Intents resolution and leaves the widget in a
placeholder state. Remove the quarantine attribute and reinstall:

```sh
xattr -cr "$HOME/Applications/FXWidget.app"
```

Also note that the provider catalog is cached for seven days, so a currency added or withdrawn by the
provider can take that long to appear or disappear from the pickers.

## Versioning

Repository release tags use `vMAJOR.MINOR.PATCH`, preferably as annotated tags. Use `v0.x.y` before 1.0 and tag meaningful runnable checkpoints rather than every commit.

`CFBundleShortVersionString` should match a release tag. `CFBundleVersion` is a separate increasing build number. Version text does not appear in the primary widget.

## Further documentation

- [`AGENTS.md`](AGENTS.md): repository invariants and coding rules
- [`docs/DECISIONS.md`](docs/DECISIONS.md): binding product and architecture decisions
- [`docs/FUTURE_WORK.md`](docs/FUTURE_WORK.md): pending work
- [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md): current milestone status
- [`docs/PROVIDER_EVALUATION.md`](docs/PROVIDER_EVALUATION.md): provider evaluation and production gate
- [`docs/TESTING.md`](docs/TESTING.md): required test coverage and visual checks
