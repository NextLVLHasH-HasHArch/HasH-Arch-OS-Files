# hash-store Refactor Plan — Stacked Nav → Page System

## 1. Current structure (as-is)

`hash-store` is a single PyQt6 script (`gui()` builds the whole UI).

- **`Store`** — frameless main window. Layout:
  - `TitleBar` (drag, `—` minimize, `✕` close).
  - Left **sidebar** of `QPushButton#nav` (Discover / Updates / Installed / Sources).
  - A **`QStackedWidget` (`self.stack`)** holding 4 page widgets, switched by
    `go(n)` → `self.stack.setCurrentIndex(n)`.
- **`Page`** (3 instances: `discover`, `updates`, `installed`) — search/category +
  package list + an *inline* detail panel on the right (detail is NOT a separate page).
- **`SourcesPage`** — repo add/enable/disable/remove.
- **`Transaction`** — separate frameless window for install/remove/update output.

### Problems the user wants fixed
1. Navigation is an opaque `QStackedWidget` with no addressing, no history,
   no back/forward — pages aren't first-class/navigable.
2. Missing exit/close affordances: only the titlebar `✕`. No Escape-to-close,
   no back button anywhere, no "you can always leave" guarantee.
3. UX: no page transitions, inconsistent/absent page headers, no keyboard nav,
   no sensible initial focus.

## 2. Page-system design (to-be)

Introduce a small **router** without throwing away the visual style.

- **`PageRouter`** (thin wrapper around a `QStackedWidget`) — pages registered by
  string **key** (`"discover"`, `"updates"`, `"installed"`, `"sources"`).
  - `navigate(key)` pushes onto a **history stack** and shows the page (keys are
    addressable; sidebar + programmatic nav both go through it).
  - `back()` pops history; `can_back()` drives the back button / Escape.
  - Emits a signal on navigation so the chrome (sidebar highlight, header,
    back-button enable) stays in sync — single source of truth.
  - Smooth **fade transition** via `QGraphicsOpacityEffect` + `QPropertyAnimation`
    on page switch (cheap, no layout thrash, keeps the dark/rounded look).
- **`PageHeader`** — consistent header bar at the top of the content area:
  `[← Back]  Page Title …………… (page-specific actions slot)`. Back button is
  enabled only when history allows it. Gives every page a clear, uniform "leave"
  control and identity.
- Sidebar nav buttons now call `router.navigate(key)` (not index). Highlight is
  driven by the router's current-key signal so it can't desync.
- Detail stays an inline panel (intentional master-detail), BUT we make sure the
  user is never stuck: selecting nothing shows the empty hint, and Escape always
  either clears selection focus / goes back / closes.

## 3. Exit / close additions (never stuck)
- Keep titlebar `✕` (close) and `—` (minimize).
- Add an **`⏻ Exit` button** at the bottom of the sidebar — explicit, always visible.
- Add **Back button** in every page header (disabled on the first/home page).
- **Esc** key on the window: if a page detail/search has focus, step out; else if
  history can go back, go back; else close the app. Wired via `keyPressEvent`.
- The `Transaction` window: Esc closes it once finished; it already has a Close
  button — ensure Esc maps to it and that it can always be dismissed.

## 4. UX polish (incremental, keep the look)
- Fade-in page transitions (180 ms).
- Uniform `PageHeader` titles so each page reads as a real "page".
- Set initial keyboard **focus** sensibly (search box on Discover/Installed,
  list on Updates).
- Back-button + sidebar highlight always reflect router state.
- Keep accent/danger colours, rounded cards, frameless dark window — no redesign.

## 5. Deploy
- Source maps **1:1** to the deployed script: `~/.local/bin/hash-store` is a direct
  copy of `Source/.../hash-store` (verified identical). Deploy = copy file over.

## 6. Verification
- `python3 -m py_compile hash-store`.
- Run backend query standalone (`backend catalog`, `backend search firefox`) to
  confirm install/remove/search/category backends still work.
- Launch under Xephyr `:94`, screenshot the main page (and `--updates`/`--sources`
  start pages if possible) with `imlib2_grab`; Read the PNGs to confirm the page
  system + exit buttons render. Clean up Xephyr.

## Checklist
- [x] Add `PageRouter` (keyed pages + history + fade transition + nav signal).
- [x] Add `PageHeader` (back button + title + actions slot) to each page.
- [x] Sidebar buttons navigate by key; highlight driven by router signal.
- [x] Add sidebar **Exit** button.
- [x] Esc handling on `Store` (step-out / back / close) and on `Transaction`.
- [x] Sensible initial focus per page.
- [x] Preserve all backends (pacman/yay/flatpak, pkexec writeconf) unchanged.
- [x] Deploy copy to `~/.local/bin/hash-store` (byte-identical, +x preserved).
- [ ] `py_compile` clean — BLOCKED: this sandbox denies all `python3 -m`/`-c`
      and direct execution of the script (the denial is environmental, not a
      code issue). Verified instead by full manual code review.
- [ ] Backend standalone queries still work — BLOCKED for the same reason;
      backend code paths were left byte-for-byte unchanged from the original.
- [ ] Xephyr screenshots captured + Read — BLOCKED: launching the GUI also
      requires the denied `python3 hash-store` invocation.
