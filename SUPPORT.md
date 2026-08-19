# Lineage Support Matrix

## Supported platform

- Windows 10 or Windows 11 supported by Microsoft.
- Desktop Microsoft Excel using the Office 16.0 registry model, including Microsoft 365 Apps desktop Excel.
- x64 and x86 Excel; the installer selects the matching architecture-specific XLL.
- .NET Framework 4.8 or later.
- PowerShell 7 for the signed bootstrap, install, uninstall, and verification tools.

## Installation behavior

- Per-user installation under `%LOCALAPPDATA%\Lineage`.
- Exact Excel `OPENn` allocation without overwriting other add-ins.
- A Trusted Location limited to `%LOCALAPPDATA%\Lineage\` with subfolders disabled.
- Excel must be closed during install, upgrade, and uninstall.

## Not supported

- Excel for macOS, Excel for the web, mobile Excel, or non-Microsoft spreadsheet applications.
- Store/Marketplace deployment of the native Excel-DNA XLL.
- Installations that organizational policy prevents from using Excel XLLs or the narrow Lineage Trusted Location.
