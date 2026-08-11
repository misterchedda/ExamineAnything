# Releasing Examine Interaction

`VERSION` is the single source of truth for the project version. It must contain one semantic version in `MAJOR.MINOR.PATCH` form. CMake reads it directly and generates the RED4ext plugin version constants during configuration.

Every release version must have exactly one matching `CHANGELOG.md` section:

```markdown
## [0.2.0] - 2026-08-10

### Added

- Describe a user-visible change.
```

Use only the Keep a Changelog category headings `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed`, and `Security`. The release parser returns the section body without its version heading so the same text can become both the GitHub release notes and the Nexus Mods changelog.

Validate and inspect the current release metadata with:

```powershell
pwsh -File scripts/release/Get-ReleaseMetadata.ps1 -OutputFormat Json
```

The future GitHub Actions workflow can publish step outputs with:

```powershell
pwsh -File scripts/release/Get-ReleaseMetadata.ps1 -OutputFormat GitHub
```

For a native build, CMake uses `RED4EXT_SDK_ROOT` in this order:

1. The `-DRED4EXT_SDK_ROOT=C:/path/to/RED4ext.SDK` CMake cache value.
2. The `RED4EXT_SDK_ROOT` environment variable.
3. An automatic fetch of the repository's pinned RED4ext.SDK revision.

An explicit local SDK build can be configured with:

```powershell
cmake -S native/ExamineInteractionNative -B native/ExamineInteractionNative/build -A x64 -DRED4EXT_SDK_ROOT=C:/path/to/RED4ext.SDK
```
