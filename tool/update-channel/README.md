# Update channel

The private source repository builds Windows packages in GitHub Actions. Its
`UPDATE_REPOSITORY` variable points clients at the public binary release repository.
Existing startup checks and the Settings auto-check switch use that address; no
GitHub credential is embedded in the application.

The public repository contains `receive.yml` as `.github/workflows/publish.yml`,
`update_channel.py`, the license, and a README. A repository-scoped write deploy key
is stored only in the private repository's `UPDATE_DEPLOY_KEY` Actions secret.
The private publisher sends the ZIP, checksum, and version manifest on a temporary
`deliveries/` branch. The public workflow validates them, creates a release using
its own repository token, then deletes the delivery branch. Release tags target
public `main`, not the temporary package commit. Neither repository uses a stored
account token for delivery.

`RELEASE_ENABLED` starts as `false` while the first custom UI is being finished.
An explicit main workflow dispatch with `publish=true` can publish the first
verified package. Set `RELEASE_ENABLED=true` when enabling subsequent main releases
and automatic promotion of checked upstream candidates. A failed merge, check,
build, non-fast-forward main update, or package validation stops publication.

The delivery transport rejects packages at 100 MiB; it does not publish an update
if GitHub's single-file limit would be exceeded. The public helper and receiver
must be updated together with their copies here when the delivery format changes.

Run validation with:

```sh
python3 -m unittest discover -s tool/update-channel -p 'test_*.py'
flutter test test/common/request_test.dart --dart-define=UPDATE_REPOSITORY=ZhuoMneg/FlClash-updates
```
