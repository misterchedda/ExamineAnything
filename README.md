# Examine Anything

A mod for Cyberpunk 2077 that adds an Examine interaction.

<img src="https://staticdelivery.nexusmods.com/mods/3333/images/32335/32335-1786368317-2005595885.gif"/>

Vist the Nexusmods page for more details: [nexusmods.com/games/cyberpunk2077/mods/32335](https://www.nexusmods.com/cyberpunk2077/mods/32335)

## Repo layout

- `source/archive` contains archive resources
- `source/resources` contains redscript, ArchiveXL, and TweakXL resources
- `native/ExamineInteractionNative` contains the RED4ext native plugin and its redscript bindings
- `scripts/release` contains release stuff

Release notes are in `CHANGELOG.md`

## Native build

The native plugin requires Windows, CMake 3.25 or newer, and Visual Studio 2022 with C++ desktop development tools.

```powershell
cmake -S native/ExamineInteractionNative -B native/ExamineInteractionNative/build -A x64
cmake --build native/ExamineInteractionNative/build --config Release --target ExamineInteractionNative
```

CMake fetches the pinned RED4ext.SDK and [RedLib](https://github.com/psiberx/cp2077-red-lib) revisions automatically. An existing RED4ext.SDK checkout can instead be supplied with `-DRED4EXT_SDK_ROOT=C:/path/to/RED4ext.SDK` or the `RED4EXT_SDK_ROOT` environment variable.

## Packaging

Build the native plugin and create the complete game-root ZIP and SHA-256 file with:

```powershell
pwsh -File scripts/release/Build-Package.ps1
```

Versioned artifacts are written to `dist`. The script restores the pinned WolvenKit.CLI tool, packs the archive resources, and validates the final ZIP layout.

## License

See `LICENSE` and `native/ExamineInteractionNative/THIRD_PARTY_NOTICES.txt`

## Credits
Big thanks to [psiberx](http://github.com/psiberx/) - Codeware, RedLib, RedHotTools, and the core mods as always (ArchiveXL, TweakXL) have been fundamental to the development of this mod. Big thanks to the [RED4Ext](https://github.com/wopss/RED4ext.SDK) maintainers and contributors as well.
