# Modifications

Modified by ZhuoMneg on 2026-10-20, based on FlClash v0.9.1 by chen08209 and its
contributors. This repository and its releases are modified builds, maintained
separately from upstream. The original copyright notices, GPL-3.0 license, and
third-party notices are retained.

- Official v0.9.1 colors, card shapes, desktop/mobile layouts, icon, and theme options.
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
