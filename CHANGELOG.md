# Changelog

All notable changes to **D365 F&O NuGet Sync** are documented here.
This project follows [Keep a Changelog](https://keepachangelog.com/) and [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Planned - v2.0.0 (PPAC)
- The LCS Shared Asset Library is being retired in favor of the **Power Platform Admin Center (PPAC)**. A future major version will source and upgrade the packages from PPAC instead of LCS, keeping the same one-click sync-to-ADO experience.

## [1.0.0] - 2026-09-21

First release. Syncs the D365 Finance & Operations build packages from the **LCS Shared Asset Library** to an Azure DevOps Artifacts feed.

### Added
- One-click sync of the 5 core D365 F&O build-reference NuGet packages from the LCS Shared Asset Library to an Azure DevOps Artifacts feed.
- Smart compare: reads the feed first and pushes only what is missing or newer; up to 3 parallel uploads.
- Paste the browser feed URL: auto-derives the NuGet v3 index URL from an Azure DevOps feed URL copied from the browser (also handles org/project-scoped feeds, query strings, bare `pkgs.dev.azure.com` URLs, and legacy `*.visualstudio.com`).
- Ships as a zip: double-click `Sync-D365FONuGet.bat` (works where `.exe` is blocked), or run the `.exe` / `.ps1`.
- Self-update: the `.exe` checks GitHub on startup and can upgrade itself in place.
- Writes a run log (`Sync-D365FONuGet.log`) next to the tool, with per-package results and full error detail for troubleshooting.
- Plain-English messages for common push failures (deleted version, already-exists, auth/permission), with the full detail kept in the log.

### Security
- Your PAT is not persisted between runs. It is prompted as a SecureString and, during upload, written to a temporary local NuGet config that is deleted immediately after.
