# Modifications

Modified by ZhuoMneg on 2026-10-20, based on FlClash v0.9.1 by chen08209 and its
contributors. This repository and its releases are modified builds, maintained
separately from upstream. The original copyright notices, GPL-3.0 license, and
third-party notices are retained.

- White surfaces with the original dashboard shapes, glass effects, and icon.
- Navigation for overview, proxies, profiles, routing, realtime requests, tools,
  and settings; connections are available from Tools.
- Searchable request history and reuse of the current profile's routing editor.
- Desktop page transitions and standard liquid glass as the new-config default.
- Cloud checks, Windows builds, stable upstream merging, and same-repository
  release checks using job-scoped GitHub tokens.

The homepage route shortcuts are still under development. A preview is not a
released implementation. Release notes identify the exact source commit for each
published binary. Clone release source with `--recursive` to include the pinned
core submodule; build commands and dependencies are in `.agents/commands.md`.
