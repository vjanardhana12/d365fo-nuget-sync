# D365 F&O NuGet Sync

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207%2B-blue)](https://learn.microsoft.com/powershell/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Latest release](https://img.shields.io/github/v/release/vjanardhana12/d365fo-nuget-sync)](https://github.com/vjanardhana12/d365fo-nuget-sync/releases/latest)

**Copy your Dynamics 365 Finance & Operations NuGet packages from LCS into your Azure DevOps Artifacts feed - in one click.**

It checks your feed first and uploads only what is **missing or newer**, so you never wait on a big upload just to get a "version already exists" error.

---

## Get it (easiest way - works on any Windows PC)

1. Download **`Sync-D365FONuGet.zip`** from the [latest release](https://github.com/vjanardhana12/d365fo-nuget-sync/releases/latest).
2. Right-click the zip, choose **Properties**, tick **Unblock**, click **OK**, then extract it.
3. Double-click **`Sync-D365FONuGet.bat`**.

That is it - no install, no PowerShell setup. The `.bat` just starts the tool for you.

> **Why the `.bat`?** Many workplaces block downloading or running `.exe` files. The `.bat` and `.ps1` inside the zip are plain text, so they get through - and the `.bat` launches everything with one double-click.
>
> **Other ways to run** (same zip): double-click **`Sync-D365FONuGet.exe`**, or run **`Sync-D365FONuGet.ps1`** in PowerShell.

---

## See it in action

**1. It remembers your feed settings and checks your feed:**

![Banner and saved configuration](docs/screenshot-1-config.png)

**2. It compares your feed with your local packages and shows what it will do - then asks before pushing:**

![Compare table: SKIP / PUSH / MISSING](docs/screenshot-2-compare.png)

**3. Done - only the packages that were missing or newer get uploaded:**

![Success summary](docs/screenshot-3-success.png)

---

## First run - you enter 4 things

| Prompt | Example |
|---|---|
| **ADO Feed URL** | `https://pkgs.dev.azure.com/myorg/_packaging/MyFeed/nuget/v3/index.json` (or just paste the feed page URL from your browser - it converts automatically) |
| **Feed Name** | any short label, e.g. `MyFeed` |
| **Email** | your Azure DevOps login |
| **PAT** | Personal Access Token with **Packaging (Read & Write)** scope - [create one](https://dev.azure.com/_usersSettings/tokens) |

The first three are remembered for next time (saved per-user). **Your PAT is not stored between runs** - you type it each run. (During upload it is written to a temporary local file that is deleted immediately afterward.)

---

## Example: upgrade your feed to a new platform version

1. In **LCS > Shared Asset Library**, download the D365 F&O NuGet packages for the version you want. You get **`.nupkg`** files (keep them as `.nupkg` - do not rename or unzip them).
2. Put those `.nupkg` files in the **same folder** as the tool (or point the tool to your Downloads folder when it asks).
3. Double-click **`Sync-D365FONuGet.bat`**.
4. It shows the compare table, asks **"Continue with push? (Y/n)"**, and uploads only what is missing or newer.

Re-run it whenever a new platform version drops.

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
| **ADO PAT** | Scope: **Packaging (Read & Write)**. |
| **LCS access** | Only to download the packages - browser access is enough. No AAD app or API setup. |
| **Internet** | To fetch `nuget.exe` once (~6 MB) and reach your feed. |

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `Cannot reach feed` | The URL must end in `/nuget/v3/index.json`; check your PAT is valid. |
| `401 Unauthorized` | PAT expired or wrong scope - make a new one with **Packaging (Read & Write)**. |
| Push rejected (`409 Conflict`) | That exact version is already in the feed - Azure Artifacts will not overwrite it. |
| Windows blocks the `.exe` | Double-click **`Sync-D365FONuGet.bat`** instead - same tool, no exe needed. |

---

## Good to know

- **Runs on** Windows PowerShell 5.1 or PowerShell 7+.
- **Auto-update:** the `.exe` checks GitHub on startup and offers to upgrade itself when a newer release exists.
- **LCS is being retired:** these packages live on the **LCS Shared Asset Library** today; Microsoft is moving to the **Power Platform Admin Center (PPAC)**. A future v2.0.0 will support PPAC.

## What's new

See the [Releases page](https://github.com/vjanardhana12/d365fo-nuget-sync/releases) or [CHANGELOG.md](CHANGELOG.md) for what changed in each version.

---

MIT licensed - free for personal and commercial use. Created by **Vinod Kumar K J**.
