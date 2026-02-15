# Release Process

## Overview

`dr-kit` uses [release-please](https://github.com/googleapis/release-please) for automated versioning and releases. When commits following [Conventional Commits](https://www.conventionalcommits.org/) are pushed to `main`, release-please creates a pull request that updates `CHANGELOG.md`. Merging that PR triggers a GitHub Release.

## Repository Setup

In your GitHub repository settings:

1. Go to **Settings → Actions → General**
2. Under "Workflow permissions", enable **"Allow GitHub Actions to create and approve pull requests"**

## How the Pipeline Works

```
Push to main (conventional commits)
        │
        ▼
   CI workflow runs
   (build + test)
        │
        ▼ (on success)
   Release workflow triggers
        │
        ▼
   release-please creates/updates PR
   (updates CHANGELOG.md)
        │
        ▼ (PR merged)
   release-please creates GitHub Release
```

## Configuration Files

| File | Purpose |
|------|---------|
| `release-please-config.json` | Release-please behavior: release type, version bump rules |
| `.release-please-manifest.json` | Current version tracker |
| `.github/workflows/ci.yml` | CI pipeline: build + test |
| `.github/workflows/release.yml` | Release automation |

## Conventional Commits

| Commit Type | Version Bump | Example |
|-------------|-------------|---------|
| `feat:` | Minor (0.x.0) | `feat: add async analyze API` |
| `fix:` | Patch (0.0.x) | `fix: handle empty directory` |
| `feat!:` or `BREAKING CHANGE:` | Major (x.0.0) | `feat!: rename TrackResult fields` |
| `docs:`, `chore:`, `ci:`, `test:` | No bump | `docs: update README` |

## Troubleshooting

### release-please PR not created

- Verify conventional commit messages on `main`
- Check that CI completed successfully (release triggers on CI success)
- Ensure workflow permissions are configured (see Repository Setup)
