# Contributing to dr-kit

## Prerequisites

- macOS 14.4+
- Swift 6.2+ (Xcode 16.3+)
- FFmpeg (`brew install ffmpeg`)

## Build & Test

```bash
# Build
swift build

# Test
swift test

# Build release
swift build -c release
```

## Conventional Commits

All commits must follow [Conventional Commits](https://www.conventionalcommits.org/).

### Format

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

### Types

| Type | Purpose |
|------|---------|
| `feat` | New feature |
| `fix` | Bug fix |
| `docs` | Documentation only |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `test` | Adding or updating tests |
| `chore` | Maintenance (dependencies, tooling) |
| `ci` | CI/CD changes |
| `perf` | Performance improvement |

### Breaking Changes

Append `!` after the type or include `BREAKING CHANGE:` in the footer:

```
feat!: change TrackResult property names

BREAKING CHANGE: peakDB renamed to peakDecibels for clarity.
```

### Examples

```bash
git commit -m "feat: add async/await analyze API"
git commit -m "fix: handle files shorter than 3 seconds"
git commit -m "test: add stereo DR computation test"
git commit -m "docs: document sqrt(2) calibration factor"
```

## Testing Conventions

- Always use Swift Testing (`import Testing`) — never XCTest
- Use `@Suite` for test grouping, `@Test` for test functions
- Use `#expect()` for assertions, `#require()` for preconditions

## Pull Request Process

1. Branch from `main`
2. Use conventional commit messages
3. Ensure `swift test` passes
4. Open a PR against `main`
