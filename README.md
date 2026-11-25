# .github

My .github repo for all my tools.

## Reusable Workflows

### Godot Windows MSI releases

[`godot-windows-msi.yml`](.github/workflows/godot-windows-msi.yml) builds a standard
GDScript Godot 4 game on disposable GitHub-hosted Windows runners. It downloads
the official engine and export templates, verifies their SHA512 checksums,
runs the project's headless test harness, exports and smoke-tests the executable,
builds an x64 MSI with WiX 4.0.6, verifies installed payload hashes and uninstalls.
Validation logs are retained even on failure. No software runs on your desktop.

```yaml
name: Build game
on:
  push:
    branches: [main]
    tags: ['v*']
  pull_request:
permissions:
  contents: write
jobs:
  windows:
    uses: jpeckham/.github/.github/workflows/godot-windows-msi.yml@<COMMIT>
    with:
      library_ref: <SAME-COMMIT>
      godot_version: '4.4.1'
      product_name: My Godot Game
      executable: MyGame.exe
      artifact_prefix: my-game
      upgrade_code: '<GENERATE-A-UNIQUE-GUID-ONCE>'
      publish_release: true
```

Use the same tested commit for the workflow reference and `library_ref`.
Provide a `Windows Desktop` export preset, or set `export_preset`.
Optional `project_path`, `test_script`, and `manufacturer` customize the project.
The SceneTree test script must exit nonzero on failures and print
`RESULT: N checks, 0 failures` on success (N must be positive).
The standard GDScript engine is supported; C# projects need additional tooling.

Branch/PR runs upload development MSI artifacts (`0.0.<run-number>`).
Only a successful `vMAJOR.MINOR.PATCH` tag build can publish a GitHub Release;
set `publish_release: false` to disable publishing. MSI limits are major/minor
0–255 and patch 0–65535. Keep the upgrade GUID and product name stable across
versions and choose a different GUID for every game. A new installer removes
older versions and rejects downgrades. Saves outside the installation directory
are not part of the installer. Packages currently require administrator rights
and are unsigned; code signing requires separate certificate configuration.

MSI creation uses the [official WiX CLI](https://docs.firegiant.com/wix/using-wix/).
Install/remove and major-upgrade checks run only on hosted runners. The upgrade
fixture installs version 0.0.0, upgrades to the candidate, verifies every payload
hash and removal of an obsolete file, rejects a downgrade, then uninstalls.
Candidate versions must be greater than 0.0.0. This covers the major-upgrade
mechanism; testing migration from a particular published release is separate.
Visible playthroughs, hardware operation, rollback after an interrupted install,
and code signing remain separate release gates.

### itch.io HTML5 Continuous Delivery

Use `.github/workflows/continuous-delivery-itch-html5.yml` from another game
repository to test, deploy, tag, and create a GitHub Release for an itch.io
HTML5 game.

Example caller workflow:

```yaml
jobs:
  itch-html5:
    uses: jpeckham/.github/.github/workflows/continuous-delivery-itch-html5.yml@main
    with:
      main_branch: main
      node_version: "24"
      game_dir: game
      test_command: npm test
      version_file: version.json
      artifact_name_prefix: my-game
      itch_target: my-itch-user/my-game:html5
    secrets:
      BUTLER_API_KEY: ${{ secrets.BUTLER_API_KEY }}
```

Required caller files:

- `version.json` with integer `major` and `minor` fields.
- An HTML5 game directory containing `index.html`.
- A repository secret named `BUTLER_API_KEY`.

The workflow computes the next `v<major>.<minor>.<patch>` tag, uploads the game
to itch.io with butler, zips the HTML5 artifact, publishes it as a workflow
artifact, and creates a GitHub Release with generated change notes.
