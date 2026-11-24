# Copy your game settings into ArcaneMP

ArcaneMP keeps its own settings, separate from the normal game:

| | Folder under `%LOCALAPPDATA%\Hogwarts Legacy\` |
|---|---|
| Normal game, Steam | `Saved\` |
| ArcaneMP (Forge launcher and ArcaneMP launcher) | `ArcaneMP\Saved\` |

The Epic Games version of the normal game uses `%LOCALAPPDATA%\HogwartsLegacy\Saved\` instead (no space). The script
looks in both and says which one it copied. If both exist it takes the one changed last; run
`tools\copy-game-settings.ps1 -Source Steam` (or `Epic`) to choose.

Some servers lock the in-game settings menu and say they use your Hogwarts Legacy settings. They use the
ArcaneMP copy, so a change made in the normal game does not reach the server.

## Use

Both files are in `arcanemp-crowd-fix.zip` on Releases (v1.1 and later; Epic Games installs from v1.2), next to the crowd fix.

1. Start Hogwarts Legacy **without** ArcaneMP, set graphics, camera, sound and HUD the way you want, quit.
2. Double-click `copy-settings.bat`.
3. Join the server as usual.

Undo: close the game, double-click `restore-settings.bat`. It puts back the settings from before the last copy.

## What it does

- Copies `Saved\Config\WindowsNoEditor\GameUserSettings.ini` and `Saved\SaveGames\<id>\SavedUserOptions.sav`
  into the same places under `ArcaneMP\`. The `<id>` folder can be named differently there (an Epic account id
  against a Steam one): the script uses the one ArcaneMP already has. The `.sav` holds a second copy of the same settings, and the game
  reads it over the `.ini`, so both are copied.
- Switches frame generation off in both copies (DLSS, FSR and XeSS frame generation crash ArcaneMP 1.15.1, see
  [../frame-generation/](../frame-generation/)). The normal game keeps its own frame generation setting.
- Does not touch `Engine.ini`, so the crowd fix (`r.SkeletalMeshLODBias`) stays.
- Backs up the ArcaneMP files first, to `%LOCALAPPDATA%\Hogwarts Legacy\ArcaneMP-settings-backups\<date-time>\`.
- Refuses to run while the game is open, and writes nothing if the `.sav` does not have the layout it expects.

The FPS cap, ray tracing and every other setting come over exactly as the normal game has them. If you play
the normal game uncapped with frame generation, set an FPS cap there before copying.
