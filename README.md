# LFG Filter

Adds class and role filtering to the TBC Anniversary Looking For Group browser.

![LFG Filter Panel](screenshot.png)

### ElvUI Support

![LFG Filter with ElvUI](screenshot_elvui.png)

## Features

- **Find Players** - Filter solo players by class and/or role (for group leaders building a group)
- **Find Groups** - Filter groups by open role slots: Tank, Healer, or DPS needed (for solo players looking for a group)
- **Max Level (70) Only** - Filter to only show max level players (Find Players)
- **Auto-refresh** - Automatically removes stale and delisted entries every 10 seconds
- **ElvUI / TukUI support** - Automatically skins the panel when ElvUI or TukUI is installed
- Native Blizzard dialog frame styling
- Filters apply instantly on toggle
- Filters persist through manual refresh
- Filter preferences saved between sessions
- Only shows on the Group Browser tab, not Create Listing

## Installation

### WoWUp
Add the GitHub repo URL in WoWUp: `https://github.com/0xTuesdays/LFGFilter`

### Manual
1. Download `LFGFilter-x.x.x.zip` from [Releases](https://github.com/0xTuesdays/LFGFilter/releases)
2. Extract the `LFGFilter` folder into `World of Warcraft/_anniversary_/Interface/AddOns/`
3. Restart the game or `/reload`

## Slash Commands

| Command | Description |
|---------|-------------|
| `/lfgf` | Show available commands |
| `/lfgf show` | Show filter panel |
| `/lfgf hide` | Hide filter panel |
| `/lfgf reset` | Clear all filters |
| `/lfgf debug` | Print debug info |
