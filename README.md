# .github

My .github repo for all my tools.

## Reusable Workflows

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
