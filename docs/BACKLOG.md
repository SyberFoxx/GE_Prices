# Backlog — improvement plan

Prioritized roadmap for GE Prices. One work unit per item, each in its own
commit, with `flutter analyze` clean and `flutter test` green (see
[Quality & verification](../README.md#quality--verification)).

IDs are stable so commits and discussions can reference them, e.g.
`fix(api): timeout stalled requests (RB-1)`.

Legend: **P0** robustness / correctness, **P1** high-impact features,
**P2** quality, polish and platform.

> Scope guard: no new dependencies without approval, no backend, no accounts,
> and every monetized feature stays blocked until a Jagex commercial licence
> and clear Wiki terms are in place (see [Legal](../README.md#legal-notice)).

---

## P0 — Robustness & correctness

- [x] **RB-1 — Time out stalled API requests.** Wrap the Wiki HTTP calls in a
  timeout and classify a timeout honestly instead of showing a generic error.
- [x] **RB-2 — Disk cache of mapping / latest / 1h.** Persist the last good
  snapshot so the app can start offline with last-known prices plus an
  "offline / last updated" indicator, instead of an empty error screen.
- [x] **RB-3 — Memoize Market / Alch rankings.** `_buildMarketRows`,
  `_buildBuyLimitCapRows` and `_buildAlchemyRows` currently re-iterate and
  re-sort on every `build()` (including every search keystroke, because
  `IndexedStack` keeps all tabs alive).
- [x] **RB-4 — Fix "below" price alerts + notification plumbing.** Use the
  `low` price for "below" targets (the `high` only ever triggers too late),
  register a notification tap handler that opens the item, and keep a
  triggered-alert history (today a fired alert silently disappears).
- [x] **RB-5 — Pull-to-refresh on Market and Alch.** Only the Search tab has
  `RefreshIndicator` today.
- [x] **RB-6 — Bump the build number on release.** `pubspec.yaml` is still
  `1.0.0+1`; every published build needs a new `+N`.

## P1 — Features

- [ ] **FT-1 — Volume alerts + favorite alerts.** Alert on unusual volume
  (dump/pump) and allow a target on any favorite, not one item at a time.
- [x] **FT-2 — Triggered-alert history.** Show active and fired alerts with
  timestamps.
- [ ] **FT-3 — 24h % change + trend arrow** on list rows (the metric a flipper
  actually reads).
- [ ] **FT-4 — Sort / filter Market & Search by price, margin, volume and
  % change; search the item `examine` text and filter by category.**
- [ ] **FT-5 — Visible watchlist / favorites section** with prices and deltas
  (today favorites are hidden behind a Search filter).
- [ ] **FT-6 — Unified, persisted flip calculator** (quantity, capital, ROI,
  buy limit) — today the flip calculator is local-only and separate from the
  "buy-limit caps" math.
- [ ] **FT-7 — Batch alchemy calculator** (quantity × profit, total rune cost).
- [ ] **FT-8 — Notify when a 4h buy-limit window resets** (Workmanager + the
  existing tracker already have everything needed).
- [ ] **FT-9 — Recently viewed items.**
- [ ] **FT-10 — Home-screen widget.**

## P2 — Quality, polish & platform

- [ ] **QL-1 — English / Spanish localization** (`gen-l10n`).
- [ ] **QL-2 — Accessibility pass:** `Semantics`, dynamic text scale (fixed
  chart heights and tiles must not break), contrast.
- [ ] **QL-3 — Tests for `ge_tax.dart` and `limit_service.dart`.**
- [ ] **QL-4 — Exclude GE-tax-exempt items** (e.g. bonds) from the tax math.
- [ ] **QL-5 — iOS release polish and device testing.**

## Not planned (blocked / out of scope)

- Pro billing, ads, a paid backend, push from a server, accounts, Jagex login
  or real offer placement — blocked by the Jagex Fan Content Policy and the
  Wiki's CC BY-NC-SA 3.0 (NonCommercial) until a commercial licence is secured.
