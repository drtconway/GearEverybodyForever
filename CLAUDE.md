# GearEverybody Forever

Port of GearEverybody (Classic Era addon, repo github.com/drtconway/GearEverybody, local copy at
`C:\Program Files (x86)\World of Warcraft\_classic_era_\Interface\AddOns\GearEverybody`) to
**World of Warcraft: Forever**. The code was copied unchanged from GearEverybody commit `7c78baa`.
Only the .toc (interface `16001`, title) and the README were changed. It has **not been run in Forever yet**.

The addon tracks every character's class, level, faction, equipped gear and the gear in their bags
and bank. It then shows who an item could be an upgrade for, in three places: the tooltip
("Upgrade for:"), a chat alert when new gear arrives in your bags, and `/ge report`, which looks
through all bags and banks. See README.md for the feature and command list.

## What Forever is (as far as we know)

- Separate install folder `_forever_`, interface number `16001` (detect with `select(4, GetBuildInfo())` in 16000-19999).
- Gameplay is vanilla-like (keyring, Questie, vanilla classes), but it runs on a **modern (retail-based) game client**.
- This comes from reading how installed addons handle it, mainly Syndicator
  (`_forever_\Interface\AddOns\Syndicator`, look for `IsForever`). It is not from documentation.
  `Core\Constants.lua`, `Tracking\BagCache.lua` and `Search\CheckItem.lua` (around line 1537) are the useful parts.

## TODO, in priority order

1. **Bank scanning (will likely error at load).** `Tracker.lua` builds `BANK` from `BANK_CONTAINER`
   and `NUM_BAG_SLOTS + 1 .. NUM_BAG_SLOTS + NUM_BANKBAGSLOTS`, which is Classic Era's bank layout.
   Forever uses character bank tabs instead: `Enum.BagIndex.CharacterBankTab_1` .. `_9`, with tab info from
   `C_Bank.FetchPurchasedBankTabData(Enum.BankType.Character)`. `PLAYERBANKSLOTS_CHANGED` passes a
   tab index. Copy Syndicator's approach. The bag list may also include `Enum.BagIndex.ReagentBag`.
   That's harmless because only gear is stored.
2. **Spell stats.** `Items.lua` only takes STR/AGI/STA/INT/SPI/armor/DPS from `GetItemStats`. Everything
   else comes from English "Equip: ..." tooltip lines. On Forever, Syndicator reads these as item stats
   instead: `ITEM_MOD_SPELL_DAMAGE_DONE`, `ITEM_MOD_SPELL_HEALING_DONE`, `ITEM_MOD_SPELL_PENETRATION`, `ITEM_MOD_MANA_REGENERATION`
   (check the exact key names, with or without `_SHORT`, by dumping `GetItemStats` in game).
   Find out whether the tooltips still have "Equip: Increases damage and healing..." text. If they don't,
   map these keys to SPELLPOWER / HEALING / SPELLPEN / MP5. Don't count a bonus from both sources.
   Also check whether crit and hit are still "Equip: Improves your chance..." text or have become stats.
   Bump `GE.PARSER_VERSION` after any parser change.
3. **Class rules.** `Data.lua` (`CLASS_WEAPONS`, `CLASS_ARMOR` with mail/plate at 40, `DUAL_WIELD_LEVEL`,
   `SPECS` weights) assumes vanilla rules. Ask the user whether Forever changes proficiencies, talents or specs.
   The installed TalentsForeverBook addon suggests the talents may differ.
4. Check the remaining modern-client assumptions in game. They should be fine: the tooltip hook uses the `TooltipDataProcessor`
   path, `C_Container.GetContainerItemInfo` provides `isBound`, the window uses `BasicFrameTemplateWithInset`
   and `ScrollingMessageFrame`, and slots/subclass IDs come from `GetItemInfoInstant`.

How to check it in game: `/ge stats <shift-click item>` prints the parsed stats and each character's verdict.
Try a spell-damage item, a healing item and a weapon. Visit the bank, then run `/ge show <name>`.

## Working notes

- There's no Lua on this machine. Use the VS Code diagnostics (getDiagnostics) to catch syntax errors.
  `.luarc.json` turns off undefined-global warnings for WoW API names.
- Tooltip patterns are enUS-only.
- Keep identifiers (`GE` namespace, `GearEverybodyDB`, `/ge`, frame names) the same as the Classic Era
  repo. The two games never load each other's addons, so nothing clashes, and matching names make
  it easier to port fixes in either direction.
- Git identity is set globally on this machine. Commit or push only when the user asks.
