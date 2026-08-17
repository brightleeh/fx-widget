---
name: widget-editor-measurement
description: Measure what the real macOS widget editor does with a WidgetKit/App Intents configuration, on an installed build. Use when a configuration parameter is not saved, when parameter visibility does not follow what the code declares, when the editor shows the wrong slots for a widget family, when a placed widget's stored configuration must be read back, or when a D-039 finding needs re-checking on a new macOS release.
---

# Measuring the macOS widget editor

## The rule this exists for

A configuration API that compiles tells you nothing about whether the editor commits it. Every
finding in D-039 is a case where the code was correct, the build succeeded, the control rendered,
the user edited it — and the value was discarded on Done. `AppEnum`, `AppEntity`, `[AppEntity]`,
`Switch(\.$parameter)` and `When(...)` all pass every check short of an installed measurement.

So: **no claim about editor behaviour without a reading from an installed build.** `swift test`
and `xcodebuild` are not evidence here. Neither is Apple's documentation, which describes iOS
behaviour that macOS does not always share.

## When not to use this

Domain logic, formatting, ordering, cache, provider adapters — all of that is covered by `swift test`
and needs none of this. This is only for the boundary where the system, not our code, decides.

## Protocol

Run it in order. Skipping the uninstall or the re-add step is how you measure a stale extension.

### 1. State the question as a single variable

Write down what you expect and what would falsify it, before building. If two things changed, the
reading yields no rule (AGENTS.md, "Change one variable at a time").

### 2. Make each branch distinguishable

The measurement only works if the outcomes cannot be confused. The Extra Large family defect was
found by giving each `Case` a **different number of slots** and reading back which count appeared —
identical branches would have shown nothing.

Use whatever marker the surface can display: distinct slot counts, distinct parameter titles,
distinct option lists. Prefer a marker visible in the editor over one that needs a log.

### 3. Log at error level

`log show` excludes info and debug by default. Emit probe output through
`Logger(subsystem: "com.example.local.FXWidget", category: "…")` at `.error` so the entry survives,
and pass `--info` anyway.

Existing categories: `options`, `configuration`, `timeline`, `requestKey`.

### 4. Build Release and install

```sh
xcodebuild \
  -project FXWidget.xcodeproj \
  -scheme FXWidget \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath DerivedData \
  clean build

rm -rf ~/Applications/FXWidget.app
cp -R DerivedData/Build/Products/Release/FXWidget.app ~/Applications/
open ~/Applications/FXWidget.app
```

The `rm -rf` is not tidiness. Two copies of the app register two extensions, and the editor may
talk to the one you did not just build. Confirm exactly one is registered:

```sh
pluginkit -m -p com.apple.widgetkit-extension | grep -i fxwidget
```

More than one line means the reading is worthless until the extras are removed.

### 5. Re-add the widget

An already-placed widget keeps the descriptor it was placed with. Remove it from the desktop and
add a fresh one from the gallery, then open the editor and commit with **Done** — not Escape, not
clicking away. A value that is only typed is not a value that was saved.

### 6. Read

```sh
log show --info --last 30m \
  --predicate 'subsystem == "com.example.local.FXWidget"' \
  --style compact
```

zsh mangles the quoted predicate in some contexts. If the output is empty but the widget clearly
ran, put the command in a shell script and run that instead of debugging the quoting.

An empty result is ambiguous — it means either "no such event" or "the probe never ran". Confirm
the probe fires at all before concluding anything from silence.

### 7. Read it back the other way, if the question is about persistence

`WidgetCenter.getCurrentConfigurations()` gives `WidgetInfo`; `family` and `kind` need nothing
extra, but committed values need `widgetConfigurationIntent(of:)`, which needs the intent type
compiled into the reading target. `WidgetInfo.configuration` — the legacy `INIntent` bridge — is
`nil` for App Intents widgets; do not use it as a shortcut.

That call also keeps returning removed widgets, so never treat its count as what is on screen.

### 8. Remove the probe, then record

Delete the probe code — a marker left in the source is a defect that compiles. Then add the finding
to `docs/DECISIONS.md` under D-039 in the shape already used there:

- the macOS version it was measured on;
- the table of what was tried against what happened;
- what the result forces in the implementation;
- and, if it contradicts an earlier claim, say so explicitly rather than editing the old sentence away.

D-039 already corrects itself once, on the 3/10/20 slot claim that was generalized from two families
without measuring the third. That correction is the most useful paragraph in the decision.

## Reporting

Label the tier. "Builds" and "measured on an installed build" are different claims, and conflating
them is what produced the wrong slot-count rule in the first place.
