# Unsigned Preview Installation

The Lineage unsigned preview is for trusted testers who accept that the native Excel add-in is **not code-signed**. Windows cannot verify its publisher. It is not a production release and cannot replace an existing signed production installation.

Download these matching-version assets only from `leonduyanlin/lineage-plugin`:

- `Lineage-Native-<version>.zip`
- `Lineage-Unsigned-Preview-Bootstrap-<version>.ps1`
- `Lineage-Unsigned-Preview-<version>.json`
- `SHA256SUMS.txt`
- `Lineage-<version>.spdx.json`

Before installation:

1. Close every Excel window. The installer never terminates Excel for you.
2. Confirm that all asset names carry the same version.
3. Compare the ZIP and bootstrap SHA-256 values with `SHA256SUMS.txt` from the official release page. GitHub provenance verification is additional evidence when an attestation is published; it is not a Windows publisher signature.
4. In Windows file Properties, unblock only the downloaded preview bootstrap after completing the hash check.
5. Run PowerShell 7 from the download directory:

```powershell
pwsh -NoProfile -File .\Lineage-Unsigned-Preview-Bootstrap-<version>.ps1 `
  -ZipPath .\Lineage-Native-<version>.zip `
  -ChecksumsPath .\SHA256SUMS.txt `
  -Action Install `
  -AcceptUnsignedPreviewRisk
```

The bootstrap checks the archive hash, rejects non-flat or duplicate archive entries, verifies the package’s exact internal manifest, confirms the `UnsignedPreview` channel marker, and only then unblocks the verified temporary payload. It deletes the temporary extraction after installation.

To uninstall, close Excel and run the same command with `-Action Uninstall`. Keep `-AcceptUnsignedPreviewRisk`; the bootstrap itself remains unsigned.

Channel protection is enforced inside the packaged installer as well as the bootstrap:

- unsigned preview can install over an earlier unsigned preview;
- unsigned preview refuses to replace signed production or a legacy receipt;
- signed production may replace an unsigned preview after its publisher verification succeeds.

Checksums detect corruption and GitHub attestations can establish repository provenance. Neither gives Windows a trusted publisher identity. Use the signed-production channel when low-friction installation or organizational trust policy is required.
