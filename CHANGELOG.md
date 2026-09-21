# Changelog

All notable changes to **D365 F&O NuGet Sync** are documented here.
This project follows [Semantic Versioning](https://semver.org/).

## [1.0.0] — 2026-09-21
### Added
- One-click sync of the 5 core D365 F&O build-reference NuGet packages from the LCS
  Shared Asset Library to an Azure DevOps Artifacts feed.
- Smart compare — reads the feed first and pushes only what's missing or newer; up to
  3 parallel uploads.
- **Paste the browser feed URL** — auto-derives the NuGet v3 index URL from an Azure
  DevOps feed URL copied straight from the browser (also handles org/project-scoped
  feeds, query strings, bare `pkgs.dev.azure.com` URLs, and legacy `*.visualstudio.com`).
- Ships as a zip — double-click `Sync-D365FONuGet.bat` (works where `.exe` is blocked),
  or run the `.exe` / `.ps1`.
- Self-update — the `.exe` checks GitHub on startup and can upgrade itself in place.

### Security
- Your PAT is not persisted between runs. It's prompted as a SecureString and, during
  upload, written to a temporary local NuGet config that is deleted immediately after.

## Planned
- **v2.0.0 — PPAC support.** As the LCS Shared Asset Library is retired in favor of the
  **Power Platform Admin Center (PPAC)**, a future major version will source/upgrade the
  packages from the new PPAC location, keeping the same one-click sync-to-ADO experience.
- Optional hardening for larger-audience use: lock down the temporary credential file
  (ACL) and clean stale copies on startup, an on-disk run log for auditing, and
  `NO_COLOR` / redirected-output support.
