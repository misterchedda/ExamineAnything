# Changelog

All notable changes to Examine Interaction are documented in this file

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions use semantic versioning

## [Unreleased]

## [0.2.0] - 2026-08-12

### Added

- Added full controller support with a separate configurable controller Examine binding, defaulting to L3
- Added a TweakXL compatibility API that lets other mods register exact paths or path prefixes for custom meshes and entities

### Changed

- World-prop previews now account for nearby level geometry and adjust their distance and scale to reduce clipping
- Examine prompts and interaction hints now update when switching between keyboard and controller input

### Fixed

- Fixed controller zoom, input glyphs, lootable Examine choices, and the Exit Examine hint
- Prevented the default G Examine binding from also toggling the player's vanilla walking mode

## [0.1.0] - 2026-08-10

### Added

- Initial release
