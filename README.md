# LayerSwapWhileDead

A companion addon for **LayerSwap** that allows players to request a layer swap while dead, with optional support for requesting swaps while in combat.

LayerSwapWhileDead extends the functionality of LayerSwap without modifying its original files.

## Features

- **Dead swapping:** Request a layer swap while dead or as a ghost.
- **Optional combat swapping:** Enable the ability to request a layer swap while in combat.
- **LayerSwap integration:** Communicates with LayerSwap using its existing addon whisper protocol.
- **Quick-swap button:** Adds an icon button to the LayerSwap minibar.
- **Customizable button position:** Choose between Top, Left, Right, or Bottom.
- **Settings panel:** Configure the addon through the in-game AddOns settings.
- **Automatic group handling:** Tracks the invitation and layer transfer process.

## Requirements

- World of Warcraft Forever.
- [LayerSwap](https://www.curseforge.com/wow/addons/layerswap).

LayerSwapWhileDead is a companion addon and requires LayerSwap to function.

## Installation

1. Download the latest release.
2. Extract the `LayerSwapWhileDead` folder.
3. Place it inside your World of Warcraft `Interface/AddOns` directory.
4. Make sure the original LayerSwap addon is installed and enabled.
5. Launch the game or reload the UI using `/reload`.

## Configuration

Open the settings using:

`/lswd`

You can also use the following commands:

| Command | Description |
|---|---|
| `/lswd` | Open addon settings |
| `/lswd combat on` | Enable combat swapping |
| `/lswd combat off` | Disable combat swapping |
| `/lswd status` | Display current combat swapping status |

Combat swapping is disabled by default. Dead swapping is always enabled.

### Button labels

- **Dead swap:** Combat swapping is disabled.
- **Force swap:** Combat swapping is enabled.

### Minibar button position

The quick-swap button can be positioned relative to the LayerSwap minibar:

- Top
- Left
- Right
- Bottom

## How it works

LayerSwapWhileDead performs its own player discovery and request lifecycle when the player is dead or has enabled combat swapping.

It communicates with compatible LayerSwap hosts through the existing `LayerSwap` addon message prefix and `r3` request protocol.

Normal layer swapping while alive and out of combat remains the responsibility of the original LayerSwap addon.

## Compatibility

This addon is specifically intended for **WoW Forever**. It is not intended to replace LayerSwap or function as a standalone layer-swapping addon.

## Bug Reports and Contributions

Bug reports, suggestions, and contributions are welcome.

If you encounter an issue, please include:
- WoW Forever client version.
- LayerSwap version.
- LayerSwapWhileDead version.
- Any relevant Lua errors or chat messages.

## License

This project is licensed under the **GNU General Public License v3.0 or later (GPL-3.0-or-later)**.

See the `LICENSE` file for the full license text.
