# Changelog

All notable changes to **D365 F&O NuGet Sync** are documented here.
This project follows [Semantic Versioning](https://semver.org/).

## [1.0.1] — 2026-09-21
### Added
- **Paste the browser feed URL.** The tool now auto-derives the NuGet v3 index URL
  (`.../_packaging/{feed}/nuget/v3/index.json`) from an Azure DevOps feed URL copied
  straight from the browser address bar. It also handles org- and project-scoped feeds,
  URLs with query strings, bare `pkgs.dev.azure.com` URLs, and legacy
  `*.visualstudio.com` URLs. When it converts, it prints `Converted to: …` so you can see
  exactly what was used.

## [1.0.0] — 2026-09-21
### Added
- Initial release. One-click sync of the 5 core D365 F&O build-reference NuGet packages
  from the LCS Shared Asset Library to an Azure DevOps Artifacts feed.
- Smart compare — reads the feed first and pushes only what's missing or newer; up to
  3 parallel uploads.
- PAT prompted as a SecureString and never saved; feed settings remembered per-user.
- Ships as a zip — double-click `Sync-D365FONuGet.bat` (works where `.exe` is blocked),
  or run the `.exe` / `.ps1`.
- Self-update — the `.exe` checks GitHub on startup and can upgrade itself in place.

## Planned
- **v2.0.0 — PPAC support.** The LCS Shared Asset Library is being retired as Microsoft
  moves to the **Power Platform Admin Center (PPAC)**. A future major version will source
  (and/or upgrade) the packages from the new PPAC location, keeping the same one-click
  sync-to-ADO experience.
