# Modifications

Modified by ZhuoMneg on 2026-10-20, based on FlClash v0.9.1 by chen08209 and its
contributors. This repository and its releases are modified builds, maintained
separately from upstream. The original copyright notices, GPL-3.0 license, and
third-party notices are retained.

- White light-mode page/window backgrounds, cool near-white outlined cards and
  subtle shadows following the approved preview. A bounded, rounded desktop dock
  uses outlined vector icons and labels; profile and proxy grids keep the preview's
  spacing. Original actions, mobile navigation, app icon and theme options remain.
- Navigation for overview, proxies, profiles, routing, realtime requests, tools,
  and settings; connections are available from Tools.
- Searchable request history and reuse of the current profile's routing editor.
- Original page transitions and Liquid Glass options are retained.
- Stable build parameters prevent the development PRE banner in release packages.
- Cloud checks, Windows builds, stable upstream merging, and same-repository
  release checks using job-scoped GitHub tokens.
- Homepage shortcuts for DMIT protocol, Proxy exit, and Emby exit, with saved
  group bindings and searchable choices using the existing switching logic.
- Searchable settings entries, asynchronous node-name exclusion, and versioned
  WebDAV backups with a history picker, inspired by
  [appshubcc/Bettbox v1.19.6](https://github.com/appshubcc/Bettbox/tree/v1.19.6)
  (GPL-3.0). These features use the existing FlClash navigation, configuration,
  and WebDAV transport; active nodes and group entries remain selectable, and
  older remote backups are retained.

Release notes identify the exact source commit for each published binary. Clone
release source with `--recursive` to include the pinned core submodule; build
commands and dependencies are in `.agents/commands.md`.

## Usability update — 2026-10-22

This update keeps the v0.9.1 stable baseline. Upstream v0.9.2-pre.1 is deferred
until the stable release so its UI, desktop and core changes can be verified
together with these customizations.

- Apply committed routing edits to the running core without leaving the routing
  tab; show the active profile, apply status and retry action.
- Keep customizable quick routes, favorites and recent nodes per profile.
- Edit desktop dashboard cards, their order and visibility; restore the default.
- Search settings by option and path, then reveal and highlight the result.
- Filter and pause request history; create a confirmed domain rule from a request,
  or explicitly check the domain with a fresh HTTPS request.
- Preview node exclusions in plain-text or regular-expression mode without list
  flicker during recomputation.
- Label, annotate and manually delete WebDAV backups; review restore scope,
  merge/replace strategy and account preservation together.
- Offer compact node cards and configurable pinned sidebar tools.
