# Modifications

Modified by ZhuoMneg on 2026-10-20, based on FlClash v0.9.1 by chen08209 and its
contributors. This repository and its releases are modified builds, maintained
separately from upstream. The original copyright notices, GPL-3.0 license, and
third-party notices are retained.

- White pages with distinct neutral cards, original rounded shapes, and icon.
- Navigation for overview, proxies, profiles, routing, realtime requests, tools,
  and settings; connections are available from Tools.
- Searchable request history and reuse of the current profile's routing editor.
- Desktop page transitions and original navigation settings, without liquid glass.
- Stable build parameters prevent the development PRE banner in release packages.
- Cloud checks, Windows builds, stable upstream merging, and same-repository
  release checks using job-scoped GitHub tokens.
- Homepage shortcuts for DMIT protocol, Proxy exit, and Emby exit, with saved
  group bindings and searchable choices using the existing switching logic.

Release notes identify the exact source commit for each published binary. Clone
release source with `--recursive` to include the pinned core submodule; build
commands and dependencies are in `.agents/commands.md`.
