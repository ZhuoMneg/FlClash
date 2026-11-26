# Modifications

This build is based on FlClash v0.9.5 by chen08209 and contributors. It carries
Windows WireGuard tunnel support from the custom v0.9.4 branch. Tunnel credentials
are excluded from new backups; restoring a backup without tunnel credentials
preserves the tunnel configured on the current device.

The personal Windows workflow builds installer and portable artifacts using the
upstream packager. It runs manually or on the feature branch and does not publish
releases. The Windows installer retains the custom Chinese messages and checks
that the app and core have exited before replacing or removing files.

Original copyright and license notices remain in place.
