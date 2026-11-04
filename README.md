# Mik's Scrolling Battle Text

Mik's Scrolling Battle Text (MSBT) 5.4.78 for the World of Warcraft 3.3.5a client, with the loot total fixed.

MSBT scrolls combat, loot and notification text around your character. `/msbt` opens the options.

## What this copy changes

The loot alert's total, the `(13)` in `+3 [Copper Ore] (13)`, now comes from your bags after the loot has landed in them.

The alert used to work the total out as soon as the loot message arrived, but the bag change is a separate packet that can come before or after it. So the total could come out wrong whenever you looted an item you already had, and more so when you looted the same item twice in quick succession or something took the items out of your bags at the same moment, such as a reagent bank deposit.

The alert now waits for the bag count to change, which is normally a fraction of a second, for at most one second. The total never shows less than the amount just looted. It reads your bags only, so items in a bank or reagent bank aren't counted.

## Install

Copy both folders into `Interface/AddOns`, replacing any older MSBT:

- `MikScrollingBattleText`
- `MSBTOptions`

## Test

```
luajit tests/loot_count_test.lua
```

## Credits

MSBT is by Mikord. This repo is based on the 3.3.5a copy at [sirus-addons/MikScrollingBattleText](https://github.com/sirus-addons/MikScrollingBattleText). The source doesn't state a licence, so this repo doesn't add one.
