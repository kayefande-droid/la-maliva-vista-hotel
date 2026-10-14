# PWA Menu Fix — stuck drawer / chatbot / scroll-lock after navigation

Reported symptom: "PWA website options get stuck" — after opening the menu
or chatbot and then navigating/returning, the page can become unresponsive
(scroll locked, elements untappable).

## Root causes

1. **BFCache state leak** — when the browser (or PWA window) restores the
   page from the Back/Forward cache after a back gesture, JavaScript state
   comes back with it. If the drawer was open when the user left
   (`body.style.overflow = 'hidden'`), the restored page is scroll-locked
   even though the drawer may no longer be visible.
2. **No visibilitychange cleanup** — switching away and back to the PWA
   could carry the same sticky `overflow='hidden'`.
3. **Chatbot open-state check** — `display === ''` was treated as "closed",
   but after a BFCache restore the inline style can be `''` while the box
   was actually open, flipping the toggle logic.

## Fixes applied (templates/base.html)

- Global rescue on `pageshow` (BFCache `persisted` or not) and
  `visibilitychange` → force-clear `body.style.overflow`, close the drawer
  and hide the chatbot so the shell always returns to a clean state.
- Chatbot toggle now reads a real state variable instead of trusting
  `display`, avoiding the stale-state flip-flop.

## Verification

Headless browser checks (Plan agent): fresh load, open/close drawer,
BFCache-style restore, chatbot toggling — all pass with no residual
`overflow='hidden'` and both widgets reachable after restore.
