# Modifications

Modified by ZhuoMneg on 2026-10-24, based on FlClash v0.9.2 by chen08209 and its
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

## Dashboard simplification

- Remove the redundant route-shortcuts card and its editor. Existing saved
  shortcut data remains readable, but the retired card is no longer offered.
- Reflow the default dashboard around a wider profile card without leaving an
  empty slot; keep the original proxy-group picker.
- Move connections, request history and DNS queries into the Network activity
  navigation page, retaining their full search, filtering and detail views.
  Remove the corresponding dashboard feed and summary from all layouts.

## Official 0.9.2 integration

- Merge official v0.9.2, including mihomo v1.19.33, DNS cache clearing, optional
  general overrides, editor and platform lifecycle fixes. Preserve the original
  application icon and the existing customized desktop appearance.
- Keep published custom configuration migrations and append official steps.
- Refresh request and DNS views independently, suspend hidden presentation, and
  remember the selected network activity tab with request history as its default.
- Bound update lookups, support cancellation and retry, and continue checking
  this repository's public releases without client credentials.
- Show backup dates before optional notes finish downloading; load and cache
  notes in bounded parallel batches without delaying restoration.

## Windows network tunnel

- Add profile-scoped private tunnel import, independent WireGuard and extension
  switches, persistent settings, a combined disable action and traffic status.
- Integrate the pinned TLS endpoint directory and physical-interface UDP bridge
  into FlClashCore without an additional tunnel executable or startup script.
- Preserve subscription chains and DIRECT rules, reject unsafe dialer paths,
  restore the original profile when disabled and omit RPC arguments from logs.
- Size dock spacing from the actual navigation count and reveal the selected
  destination in short windows so added labels remain visible.
- Validate effective filtered dialer groups and empty fallbacks before applying
  tunnel routing, and preserve multi-expression exclusion filters.
- Recreate the UDP bridge after an unexpected receive failure, and reject invalid
  private imports before saving them.

## Official 0.9.3 integration

- Merge official v0.9.3 and its pinned Prism UI, core, editor and platform changes.
- Keep the white desktop surfaces, rounded navigation, request tools, routing,
  exclusions, versioned backups and profile-scoped Windows network tunnel.
- Publish an installer and SHA256SUMS in this repository for the official verified
  updater, retaining the portable ZIP and credential-free update checks.
