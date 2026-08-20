# Changelog

All notable changes to Examine Interaction are documented in this file

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions use semantic versioning

## [Unreleased]

## [0.4.0] - 2026-08-20

### Added

- Added TweakXL entity presentation profiles with optional active appearance matching, localized name and description overrides, rotation correction, and preview scaling
- Added optional `zoomMin`, `zoomMax`, `pitchMin`, `pitchMax`, `yawMin`, and `yawMax` controls to mesh and entity profiles
- Added automatic preview text from every valid runtime scanning component and clue record on registered entities
- Added independent mouse and controller preview rotation sensitivity sliders to Mod Settings

### Changed

- World prop focus now follows the native aim state, supporting remapped aim inputs and toggle aim. So if you rebind RMB/LT for aim via the game's native keybinding settings, the Examine interaction for world props will follow the new binding instead of being stuck at RMB/LT

### Fixed

- Prevented repeated Examine input while a preview is opening or active from spawning overlapping popups which was causing a crash for some users

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
