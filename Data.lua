local _, GE = ...

local function Set(...)
  local t = {}
  for i = 1, select("#", ...) do
    t[select(i, ...)] = true
  end
  return t
end

-- Equipment slots we track (shirt, tabard and ammo are ignored).
GE.SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }

GE.SLOT_NAMES = {
  [1] = "Head", [2] = "Neck", [3] = "Shoulder", [5] = "Chest", [6] = "Waist",
  [7] = "Legs", [8] = "Feet", [9] = "Wrist", [10] = "Hands", [11] = "Ring",
  [12] = "Ring", [13] = "Trinket", [14] = "Trinket", [15] = "Back",
  [16] = "Main Hand", [17] = "Off Hand", [18] = "Ranged",
}

-- Equip locations that go in a fixed slot, or the weaker of a pair of slots.
GE.INVTYPE_SLOTS = {
  INVTYPE_HEAD = { 1 },
  INVTYPE_NECK = { 2 },
  INVTYPE_SHOULDER = { 3 },
  INVTYPE_CHEST = { 5 },
  INVTYPE_ROBE = { 5 },
  INVTYPE_WAIST = { 6 },
  INVTYPE_LEGS = { 7 },
  INVTYPE_FEET = { 8 },
  INVTYPE_WRIST = { 9 },
  INVTYPE_HAND = { 10 },
  INVTYPE_FINGER = { 11, 12 },
  INVTYPE_TRINKET = { 13, 14 },
  INVTYPE_CLOAK = { 15 },
  INVTYPE_RANGED = { 18 },
  INVTYPE_RANGEDRIGHT = { 18 },
  INVTYPE_THROWN = { 18 },
  INVTYPE_RELIC = { 18 },
}

-- Main hand / off hand equip locations, which need two-hander and dual wield handling.
GE.HAND_INVTYPES = Set("INVTYPE_WEAPON", "INVTYPE_2HWEAPON", "INVTYPE_WEAPONMAINHAND",
  "INVTYPE_WEAPONOFFHAND", "INVTYPE_SHIELD", "INVTYPE_HOLDABLE")

GE.EQUIPPABLE = {}
for invType in pairs(GE.INVTYPE_SLOTS) do
  GE.EQUIPPABLE[invType] = true
end
for invType in pairs(GE.HAND_INVTYPES) do
  GE.EQUIPPABLE[invType] = true
end

-- Slots where cloth/leather/mail/plate matters for the strictArmor setting.
GE.ARMOR_TYPED = Set("INVTYPE_HEAD", "INVTYPE_SHOULDER", "INVTYPE_CHEST", "INVTYPE_ROBE",
  "INVTYPE_WAIST", "INVTYPE_LEGS", "INVTYPE_FEET", "INVTYPE_WRIST", "INVTYPE_HAND")

-- Weapon subclass IDs: 0 1H axe, 1 2H axe, 2 bow, 3 gun, 4 1H mace, 5 2H mace, 6 polearm,
-- 7 1H sword, 8 2H sword, 10 staff, 13 fist, 15 dagger, 16 thrown, 18 crossbow, 19 wand
GE.CLASS_WEAPONS = {
  WARRIOR = Set(0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18),
  PALADIN = Set(0, 1, 4, 5, 6, 7, 8),
  HUNTER  = Set(0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18),
  ROGUE   = Set(2, 3, 4, 7, 13, 15, 16, 18),
  PRIEST  = Set(4, 10, 15, 19),
  SHAMAN  = Set(0, 1, 4, 5, 10, 13, 15),
  MAGE    = Set(7, 10, 15, 19),
  WARLOCK = Set(7, 10, 15, 19),
  DRUID   = Set(4, 5, 10, 13, 15),
}

-- Armor subclass ID -> level the class can first wear it.
-- 0 misc (rings, necks, trinkets, held in off-hand) is open to everyone.
-- 1 cloth, 2 leather, 3 mail, 4 plate, 6 shield, 7 libram, 8 idol, 9 totem
GE.CLASS_ARMOR = {
  WARRIOR = { [1] = 1, [2] = 1, [3] = 1, [4] = 40, [6] = 1 },
  PALADIN = { [1] = 1, [2] = 1, [3] = 1, [4] = 40, [6] = 1, [7] = 1 },
  HUNTER  = { [1] = 1, [2] = 1, [3] = 40 },
  ROGUE   = { [1] = 1, [2] = 1 },
  PRIEST  = { [1] = 1 },
  SHAMAN  = { [1] = 1, [2] = 1, [3] = 40, [6] = 1, [9] = 1 },
  MAGE    = { [1] = 1 },
  WARLOCK = { [1] = 1 },
  DRUID   = { [1] = 1, [2] = 1, [8] = 1 },
}

GE.DUAL_WIELD_LEVEL = { WARRIOR = 20, HUNTER = 20, ROGUE = 1 }

--[[ Stat weights per spec; the first spec of each class is the default.
  Base stats: STR AGI STA INT SPI ARMOR
  Physical:   AP RAP FERAL_AP CRIT HIT WEAPONSKILL (CRIT/HIT are per 1%)
  Weapon:     MELEE_DPS RANGED_DPS (off-hand weapon DPS counts half)
  Spell:      SPELLDAMAGE HEALING SPELLCRIT SPELLHIT MP5 SPELLPEN
              FIRE_DMG FROST_DMG SHADOW_DMG ARCANE_DMG NATURE_DMG HOLY_DMG (single school items)
              "+damage and healing" items count toward both SPELLDAMAGE and HEALING.
  Tank:       DEFENSE DODGE PARRY BLOCK BLOCKVALUE
  Weights are relative to the spec's main stat at 1.0. They are rough, leveling-friendly values.
]]
GE.SPECS = {
  WARRIOR = {
    { key = "dps", name = "Arms/Fury", w = {
      STR = 1, AGI = 0.75, STA = 0.3, ARMOR = 0.005, AP = 0.5, CRIT = 14, HIT = 16,
      WEAPONSKILL = 3, MELEE_DPS = 7, RANGED_DPS = 0.5 } },
    { key = "tank", name = "Protection", w = {
      STA = 1, ARMOR = 0.06, DEFENSE = 1.5, DODGE = 12, PARRY = 10, BLOCK = 6, BLOCKVALUE = 0.4,
      STR = 0.5, AGI = 0.6, AP = 0.25, HIT = 6, CRIT = 3, WEAPONSKILL = 1, MELEE_DPS = 3,
      RANGED_DPS = 0.3 } },
  },
  PALADIN = {
    { key = "ret", name = "Retribution", w = {
      STR = 1, AGI = 0.6, STA = 0.3, INT = 0.3, SPI = 0.05, ARMOR = 0.005, AP = 0.5, CRIT = 12,
      HIT = 12, WEAPONSKILL = 2, MELEE_DPS = 7, SPELLDAMAGE = 0.2, HOLY_DMG = 0.2, MP5 = 0.6 } },
    { key = "holy", name = "Holy", w = {
      HEALING = 1, INT = 0.8, SPI = 0.1, STA = 0.2, MP5 = 2, SPELLCRIT = 10 } },
    { key = "prot", name = "Protection", w = {
      STA = 1, ARMOR = 0.05, DEFENSE = 1.3, DODGE = 10, PARRY = 9, BLOCK = 7, BLOCKVALUE = 0.6,
      SPELLDAMAGE = 0.6, HOLY_DMG = 0.6, INT = 0.35, STR = 0.4, AGI = 0.4, HIT = 5, MP5 = 1,
      MELEE_DPS = 2 } },
  },
  HUNTER = {
    { key = "dps", name = "Ranged DPS", w = {
      AGI = 1, STA = 0.3, INT = 0.35, SPI = 0.05, STR = 0.05, ARMOR = 0.005, RAP = 0.4, AP = 0.4,
      CRIT = 15, HIT = 15, MP5 = 1, RANGED_DPS = 5.5, MELEE_DPS = 0.3 } },
  },
  ROGUE = {
    { key = "dps", name = "Melee DPS", w = {
      AGI = 1, STR = 0.5, STA = 0.3, ARMOR = 0.005, AP = 0.5, CRIT = 15, HIT = 17,
      WEAPONSKILL = 3, MELEE_DPS = 7, RANGED_DPS = 0.3 } },
  },
  PRIEST = {
    { key = "holy", name = "Healer", w = {
      HEALING = 1, INT = 0.6, SPI = 0.5, STA = 0.2, MP5 = 2, SPELLCRIT = 8, RANGED_DPS = 0.5 } },
    { key = "shadow", name = "Shadow", w = {
      SPELLDAMAGE = 1, SHADOW_DMG = 1, SPELLHIT = 12, SPELLCRIT = 1, INT = 0.4, SPI = 0.5,
      STA = 0.4, MP5 = 1.5, SPELLPEN = 0.3, RANGED_DPS = 1.5 } },
  },
  SHAMAN = {
    { key = "enh", name = "Enhancement", w = {
      STR = 1, AGI = 0.7, STA = 0.3, INT = 0.3, ARMOR = 0.005, AP = 0.5, CRIT = 12, HIT = 12,
      WEAPONSKILL = 2, MELEE_DPS = 8, SPELLDAMAGE = 0.15, NATURE_DMG = 0.15, MP5 = 0.8 } },
    { key = "ele", name = "Elemental", w = {
      SPELLDAMAGE = 1, NATURE_DMG = 1, FIRE_DMG = 0.4, FROST_DMG = 0.2, SPELLCRIT = 10,
      SPELLHIT = 12, INT = 0.45, SPI = 0.1, STA = 0.3, MP5 = 1.5, SPELLPEN = 0.2 } },
    { key = "resto", name = "Restoration", w = {
      HEALING = 1, INT = 0.6, SPI = 0.15, STA = 0.2, MP5 = 2.2, SPELLCRIT = 8 } },
  },
  MAGE = {
    { key = "frost", name = "Frost", w = {
      SPELLDAMAGE = 1, FROST_DMG = 1, FIRE_DMG = 0.3, ARCANE_DMG = 0.15, SPELLHIT = 12,
      SPELLCRIT = 8, INT = 0.5, SPI = 0.15, STA = 0.3, MP5 = 1.2, SPELLPEN = 0.3,
      RANGED_DPS = 1.5 } },
    { key = "fire", name = "Fire", w = {
      SPELLDAMAGE = 1, FIRE_DMG = 1, FROST_DMG = 0.2, ARCANE_DMG = 0.15, SPELLHIT = 13,
      SPELLCRIT = 11, INT = 0.45, SPI = 0.1, STA = 0.3, MP5 = 1, SPELLPEN = 0.3,
      RANGED_DPS = 1.5 } },
  },
  WARLOCK = {
    { key = "shadow", name = "Shadow", w = {
      SPELLDAMAGE = 1, SHADOW_DMG = 1, FIRE_DMG = 0.3, SPELLHIT = 12, SPELLCRIT = 6, INT = 0.35,
      SPI = 0.2, STA = 0.5, MP5 = 0.8, SPELLPEN = 0.3, RANGED_DPS = 1.2 } },
    { key = "fire", name = "Fire", w = {
      SPELLDAMAGE = 1, FIRE_DMG = 1, SHADOW_DMG = 0.4, SPELLHIT = 12, SPELLCRIT = 10, INT = 0.35,
      SPI = 0.1, STA = 0.4, MP5 = 0.8, SPELLPEN = 0.3, RANGED_DPS = 1.2 } },
  },
  DRUID = {
    { key = "cat", name = "Feral (Cat)", w = {
      STR = 1, AGI = 1, STA = 0.35, INT = 0.1, ARMOR = 0.005, AP = 0.5, FERAL_AP = 0.5,
      CRIT = 14, HIT = 14 } },
    { key = "bear", name = "Feral (Bear)", w = {
      STA = 1, ARMOR = 0.08, AGI = 0.8, STR = 0.4, DEFENSE = 1.2, DODGE = 12, AP = 0.2,
      FERAL_AP = 0.2, HIT = 6, CRIT = 4 } },
    { key = "balance", name = "Balance", w = {
      SPELLDAMAGE = 1, NATURE_DMG = 0.9, ARCANE_DMG = 0.9, SPELLCRIT = 8, SPELLHIT = 12,
      INT = 0.5, SPI = 0.2, STA = 0.3, MP5 = 1.5, SPELLPEN = 0.2 } },
    { key = "resto", name = "Restoration", w = {
      HEALING = 1, INT = 0.6, SPI = 0.5, STA = 0.2, MP5 = 2, SPELLCRIT = 6 } },
  },
}
