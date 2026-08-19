# Lineage Rollback and Recovery

## User rollback

1. Close every Excel window.
2. Run the signed uninstall entry point from the installed release package.
3. Verify that the receipt-owned XLL, exact `OPENn` registration, and Lineage Trusted Location were removed.
4. Install the previously verified release through its signed bootstrap.
5. Open a disposable workbook and run the release smoke checklist.

The uninstaller must refuse to remove files, registry values, or trusted-location data that no longer match the installation receipt.

## Failed upgrade

The installer snapshots files and registry values before mutation and rolls back started steps in reverse order. If rollback reports a concurrent change, stop and inspect the receipt, XLL hash, `OPENn` values, and Trusted Location rather than overwriting the newer state.

## Workbook recovery

Lineage does not use an installer rollback to alter workbooks. Clean/Prepare outputs are separate copies; discard a failed output copy and retain the source workbook unchanged.
