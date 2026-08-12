# Changelog

All notable changes to Examine Interaction are documented in this file

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions use semantic versioning

## [Unreleased]

## [0.3.0] - 2026-08-12

### Added

- Added TweakXL mesh presentation profiles, allowing mod authors to provide localized names and descriptions, rotation offsets, and scale multipliers for registered meshes

### Changed

- Preview models now render on the foreground weapon plane to prevent them from clipping through world geometry
- Improved initial preview framing by using tighter visible-component bounds, preventing some props from starting excessively zoomed out

### Fixed

- Corrected the default preview orientation for posters and photographs so their front faces are presented to the player

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
