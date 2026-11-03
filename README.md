# GearEverybody Forever

A World of Warcraft: Forever addon that remembers the gear on all your characters and tells you
when an item could be an upgrade for one of them. Port of
[GearEverybody](https://github.com/drtconway/GearEverybody) for Classic Era.

> **Work in progress:** the port to Forever isn't finished yet. See [CLAUDE.md](CLAUDE.md).

## Install

In WowUp, choose *Get Addons → Install from URL* and enter
`https://github.com/drtconway/GearEverybodyForever`. Or download the zip from the
[releases page](https://github.com/drtconway/GearEverybodyForever/releases) and unzip it into your
`_forever_\Interface\AddOns` folder.

## What it does

- **Tracks every character** you log in on: class, level, faction, equipped gear, and the gear in
  their bags and bank. The bank is recorded each time you open it.
- **Tooltip:** hover any piece of gear (in bags, loot windows, the auction house, chat links) to see
  which characters it would help:

  ```
  Upgrade for:
    Thrall 42 Enhancement         +18% Hands
    Jaina 60 Frost                 +4% Ring
    Grom 38 Arms/Fury        empty Chest (lvl 40)
  ```

  Soulbound and Bind on Pickup items are only checked against the character you're playing.
- **Loot alert:** when a new piece of gear lands in your bags (loot, mail, the auction house) and
  it's an upgrade for someone, a chat message says who it's for.
- **Mule report** (`/ge report`): checks every item in every character's bags and bank and lists
  what could be sent to whom.

## How upgrades are judged

1. **Can they use it?** Checks weapon skills and armor types for the class, mail/plate at level 40,
   "Classes:" restrictions, and the required level. Items up to 5 levels above a character are
   shown with the level they'd need.
2. **Best armor type only** (on by default): a level 40+ hunter won't be offered leather and a
   level 40+ warrior won't be offered mail. Turn this off with `/ge strict`.
3. **Score:** each character has a spec (`/ge spec`) with stat weights. The item's score is
   compared with what the character has in that slot. Rings and trinkets are compared with the
   weaker of the two. A two-hander is compared with main hand + off hand combined. The percentage
   shown is the improvement for that slot.

Default specs: Warrior Arms/Fury, Paladin Retribution, Hunter, Rogue, Priest Healer, Shaman
Enhancement, Mage Frost, Warlock Shadow, Druid Feral (Cat). Change them per character, e.g.
`/ge spec Thrall resto`.

## Commands

| Command | |
|---|---|
| `/ge report` | Upgrades sitting in any character's bags or bank |
| `/ge chars` | List tracked characters |
| `/ge show <name>` | A character's equipped gear, bags and bank |
| `/ge spec [name] [spec]` | View or set the spec used for scoring |
| `/ge ignore <name>` | Stop suggesting upgrades for a character (bank alts) |
| `/ge forget <name>` | Delete a character's data |
| `/ge stats <item>` | Shift-click an item to see the stats read from it and each character's verdict |
| `/ge alert` | Toggle the loot alert |
| `/ge strict` | Toggle best-armor-type-only |
| `/ge realms` | Include characters on other realms and the other faction |
| `/ge levels <n>` | How many levels ahead to look (default 5) |
| `/ge min <pct>` | Smallest upgrade worth showing (default 1%) |

## Things to know

- Log in on each character once (and open their bank once) so the addon knows about them.
- Equip bonuses are read from English tooltip text, so the addon is enUS-only for now.
- Not counted: enchants, set bonuses, "Use:" and "Chance on hit:" effects, resistances, and the
  hit cap. Trinkets that only have a Use effect will rarely show as upgrades.
- Swapping a two-hander for a one-hander plus an off-hand isn't judged, since it takes two items.
- Stat weights are rough, leveling-friendly values in [Data.lua](Data.lua) (`GE.SPECS`). Edit them
  to taste.

## Releasing

Work happens on `dev`; `main` is protected and only changes through pull requests. To release:

1. Open a pull request from `dev` to `main` on GitHub and merge it.
2. Tag the merged `main`:
   `git switch main && git pull && git tag -a v0.1.0 -m "GearEverybody Forever 0.1.0" && git push origin v0.1.0`,
   then `git switch dev` to carry on.

Pushing the tag does the rest:

- **The workflow:** `.github/workflows/release.yml` runs the BigWigs packager.
- **The zip:** the packager builds `GearEverybodyForever-<tag>.zip`, leaving out what `.pkgmeta`
  lists and any dotfiles.
- **The version:** it replaces `@project-version@` in the `.toc` with the tag.
- **The release:** it publishes a GitHub release with the zip and a `release.json` for WowUp.
