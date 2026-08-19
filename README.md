# Lineage Excel Add-in

Lineage is a native Excel add-in for tracing model relationships, auditing formulas, building and formatting financial models, and preparing workbooks for distribution.

## Unsigned Preview 1.5.0

This repository currently distributes an **unsigned preview for trusted testers**. Windows cannot verify its publisher. It is not the signed-production channel.

Download the five matching files from [`preview/1.5.0`](preview/1.5.0):

- `Lineage-Native-1.5.0.zip`
- `Lineage-Unsigned-Preview-Bootstrap-1.5.0.ps1`
- `Lineage-Unsigned-Preview-1.5.0.json`
- `SHA256SUMS.txt`
- `Lineage-1.5.0.spdx.json`

Read [INSTALL.md](INSTALL.md) before running anything. Close Excel, verify the published SHA-256 values, unblock only the preview bootstrap, and explicitly acknowledge the unsigned-preview risk during installation.

## Trust model

- The ZIP, all package files, preview bootstrap, notice, and SPDX SBOM are bound by `SHA256SUMS.txt`.
- The bootstrap verifies the ZIP snapshot and exact internal package manifest before extracting or launching code.
- Preview installation cannot replace an existing signed-production installation.
- Checksums establish integrity against this repository; they do not provide a Windows trusted-publisher signature.

The Lineage application source is maintained separately in a private repository. This public repository contains only distribution assets and user-facing documentation.

See [SUPPORT.md](SUPPORT.md), [ROLLBACK.md](ROLLBACK.md), and [SECURITY.md](SECURITY.md) for operational guidance.
