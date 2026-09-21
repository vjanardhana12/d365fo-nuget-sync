# D365 F&O NuGet Sync

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207%2B-blue)](https://learn.microsoft.com/powershell/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

**One double-click to sync Microsoft Dynamics 365 Finance & Operations NuGet packages from LCS to your Azure DevOps Artifacts feed.**

It reads your feed first, so it only pushes packages that are **missing or newer** — no wasted uploads, no `409 Conflict` on versions Azure Artifacts already has.

---

## Quick start

1. Download **`Sync-D365FONuGet.zip`** from the [latest release](https://github.com/vjanardhana12/d365fo-nuget-sync/releases/latest).
2. **Right-click the zip → Properties → tick “Unblock” → OK**, then extract it.
3. Double-click **`Sync-D365FONuGet.exe`**.

The zip contains everything you need:

| File | Purpose |
|---|---|
| `Sync-D365FONuGet.exe` | The tool. Just run it. Auto-updates on startup. |
| `Sync-D365FONuGet.ps1` | Same tool as source — run it if your machine blocks `.exe`, or to audit the code. |
| `README.md` / `LICENSE` | This file + MIT license. |

> **Prefer the script?** Open Windows PowerShell 5.1 (or PowerShell 7+), `cd` to the folder, and run `.\Sync-D365FONuGet.ps1`.

> **SmartScreen note:** an unsigned indie `.exe` may prompt *“Make sure you trust…”* on first launch. Click **More info → Run anyway**, or just run the `.ps1` — every line is auditable in this repo.

---

## What you'll be asked (first run)

| Prompt | Example |
|---|---|
| **ADO Feed URL** | `https://pkgs.dev.azure.com/myorg/_packaging/MyFeed/nuget/v3/index.json` |
| **Feed Name** | any short label, e.g. `MyFeed` |
| **Email** | your ADO login |
| **PAT** | Personal Access Token with **Packaging (Read & Write)** scope |

The first three are saved per-user to `%LOCALAPPDATA%\d365fo-nuget-sync\.push-config`. **The PAT is never saved** — it's prompted as a SecureString each run.

---

## What it does

1. Reads your ADO feed and lists the versions it already has.
2. Reads any `.nupkg` files you've placed next to the tool.
3. Shows a table: feed vs local, and the action for each package.
4. If any are missing, opens the LCS Shared Asset Library so you can download them, then waits for you to drop them in the folder.
5. Pushes only what's missing or newer (up to 3 in parallel).

```
   Package                         InFeed         Local           Action
   ──────────────────────────────  ─────────────  ──────────────  ──────────────
   Platform.DevALM.BuildXpp        7.0.7858.27    7.0.7858.27     SKIP (same)
   Platform.CompilerPackage        7.0.7858.27    7.0.7858.27     SKIP (same)
   Application1.DevALM.BuildXpp    10.0.2345.218  10.0.2527.42    PUSH (newer)
   Application2.DevALM.BuildXpp    10.0.2345.218  10.0.2527.42    PUSH (newer)
   ApplicationSuite.DevALM.BXpp    10.0.2345.218  10.0.2527.42    PUSH (newer)
```

---

## The 5 packages it manages

The standard D365 F&O build references from the LCS Shared Asset Library:

- `Microsoft.Dynamics.AX.Platform.DevALM.BuildXpp`
- `Microsoft.Dynamics.AX.Platform.CompilerPackage`
- `Microsoft.Dynamics.AX.Application1.DevALM.BuildXpp`
- `Microsoft.Dynamics.AX.Application2.DevALM.BuildXpp`
- `Microsoft.Dynamics.AX.ApplicationSuite.DevALM.BuildXpp`

---

## Prerequisites

| Requirement | Notes |
|---|---|
| **Windows PowerShell 5.1** (or 7+) | The `.exe` needs no PowerShell knowledge. The `.ps1` runs on 5.1 and 7+. |
| **ADO PAT** | Scope: **Packaging (Read & Write)**. [Create one →](https://dev.azure.com/_usersSettings/tokens) |
| **LCS access** | Only to download the packages — browser access is enough. No AAD app or API setup. |
| **Internet** | To fetch `nuget.exe` once (~6 MB) and reach your feed. |

---

## Handy switches

```powershell
.\Sync-D365FONuGet.ps1 -Force            # re-push even if the same version exists
.\Sync-D365FONuGet.ps1 -MaxParallel 5    # more parallel uploads
# CI / unattended (missing packages cause failure instead of prompting):
$env:ADO_PAT = '<pat>'
.\Sync-D365FONuGet.ps1 -FeedUrl '...' -FeedName MyFeed -Email me@x.com -NonInteractive
```

---

## Troubleshooting

| Issue | Fix |
|---|---|
| `Cannot reach feed` | URL must end in `/nuget/v3/index.json`; check the PAT is valid with Packaging scope. |
| `401 Unauthorized` | PAT expired or wrong scope — regenerate with **Packaging (Read & Write)**. |
| `409 Conflict` / push rejected | That exact version is already in the feed. Azure Artifacts won't overwrite — bump the version in LCS. |
| `.exe` won't run / is blocked | Run `Sync-D365FONuGet.ps1` from the same zip instead. |
| `nuget.exe` download fails (proxy) | Set `$env:HTTPS_PROXY`, or drop `nuget.exe` into `%LOCALAPPDATA%\d365fo-nuget-push-tool\`. |

---

## Notes

- **LCS → PPAC:** As of 2026, these packages still live on the **LCS Shared Asset Library**. Microsoft is migrating LCS to the **Power Platform Admin Center (PPAC)**; this tool will be updated when that lands — same workflow.
- **Auto-update:** the `.exe` checks GitHub on startup and offers to upgrade itself when a newer release exists. The `.ps1` is updated manually (re-download).
- **Why not fully auto-download from LCS?** The LCS API needs an Azure AD app registration (often blocked for non-admins) and is being deprecated for PPAC. The browser-based download step works for everyone with LCS access and survives the transition.

---

MIT licensed — see [LICENSE](LICENSE). Free for personal and commercial use.

*Created by **Vinod Kumar K J** — feedback welcome.*
