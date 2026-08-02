# Releasing

The package is published as
[`@thinkvelta/claude-worktree-tools`](https://www.npmjs.com/package/@thinkvelta/claude-worktree-tools)
on the public npm registry. Only maintainers with access to the `@thinkvelta` scope can publish.

## One-time setup

```bash
npm login    # authenticate with your npm account
npm whoami   # confirm you're logged in
```

## Cut a release

1. Make sure `main` is clean and CI is green (`make ci`).
2. Bump the version — `npm version patch|minor|major` updates `package.json` and creates a git tag.
3. Verify the tarball contents before publishing:

   ```bash
   npm pack --dry-run   # should match the "files" field in package.json
   ```

4. Publish:

   ```bash
   npm publish
   ```

   `publishConfig.access` is set to `public` in `package.json`, so no `--access` flag is needed.

5. Push the bump commit and tag:

   ```bash
   git push --follow-tags
   ```

6. Confirm the new version resolves:

   ```bash
   npx @thinkvelta/claude-worktree-tools@latest --help
   ```

## Versioning guidance

- `patch` — bug fixes, skill wording tweaks, doc changes.
- `minor` — new skill, new CLI flag, new template file (backwards-compatible).
- `major` — breaking changes: renamed skills, changed default install paths, or manifest entries
  removed.

Test against a scratch repo with `./try-install.sh /tmp/scratch-repo` before publishing — the
installed output is what end users actually see.

## Before tagging

Regenerate the README demo if the setup script's output changed:

```bash
make demo    # rewrites the generated block in README.md
```

It refuses to write anything that still contains a real path or username, so a green run is also
the privacy check.
