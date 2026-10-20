# Update channel

Source and Windows releases live in the same public repository. Cloud builds use
`UPDATE_REPOSITORY=$GITHUB_REPOSITORY`, so the existing startup check and Settings
auto-check switch read this repository's Releases. The application contains no
GitHub credentials.

Only the publish job has `contents: write`. It uses GitHub's job-scoped
`GITHUB_TOKEN` to create a release in the same repository. There is no cross-repo
delivery, stored deploy key, or account token. The release tag targets the exact
source commit that produced the package; its notes link the corresponding source
and recursive clone command. SHA256SUMS.txt and build-info.json identify the package.

`RELEASE_ENABLED` starts as `false` while the first custom UI is being finished.
An explicit main workflow dispatch with `publish=true` can publish the first
verified package. Set `RELEASE_ENABLED=true` when enabling subsequent main releases
and automatic promotion of checked upstream candidates. A failed merge, check,
build, non-fast-forward main update, or package validation stops publication.

Run validation with:

```sh
python3 -m unittest discover -s tool/update-channel -p 'test_*.py'
flutter test test/common/request_test.dart --dart-define=UPDATE_REPOSITORY=ZhuoMneg/FlClash
```
