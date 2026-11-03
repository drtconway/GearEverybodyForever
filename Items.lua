local _, GE = ...

local GetItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local GetItemInfoInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
local GetItemStats = C_Item and C_Item.GetItemStats or GetItemStats

-- Bump whenever parsing changes so cached item stats get rebuilt.
GE.PARSER_VERSION = 2

-- GetItemStats keys (minus any "_SHORT") we trust. Everything else comes from the tooltip's
-- "Equip:" lines, which keeps us from counting the same bonus twice.
local BASE_STATS = {
  ITEM_MOD_STRENGTH = "STR",
  ITEM_MOD_AGILITY = "AGI",
  ITEM_MOD_STAMINA = "STA",
  ITEM_MOD_INTELLECT = "INT",
  ITEM_MOD_SPIRIT = "SPI",
  RESISTANCE0_NAME = "ARMOR",
}

-- Forever reports these as item stats (Classic Era only has them as "Equip:" text). Each is
-- used only if the tooltip didn't already give that bonus, so it is never counted twice.
local SPELL_STATS = {
  ITEM_MOD_SPELL_DAMAGE_DONE = "SPELLDAMAGE",
  ITEM_MOD_SPELL_HEALING_DONE = "HEALING",
  ITEM_MOD_SPELL_PENETRATION = "SPELLPEN",
  ITEM_MOD_MANA_REGENERATION = "MP5",
}

local SCHOOLS = {
  fire = "FIRE_DMG", frost = "FROST_DMG", shadow = "SHADOW_DMG",
  arcane = "ARCANE_DMG", nature = "NATURE_DMG", holy = "HOLY_DMG",
}

-- Matched against the lowercased text after "Equip: ". First match wins, so order matters.
-- These are enUS strings.
local EQUIP_PATTERNS = {
  { "^increases damage and healing done by magical spells and effects by up to (%d+)", "SPELLPOWER" },
  { "^increases healing done by up to (%d+) and damage done by up to (%d+)", "HEALING", "SPELLDAMAGE" },
  { "^increases healing done by spells and effects by up to (%d+)", "HEALING" },
  { "^increases damage done by (%a+) spells and effects by up to (%d+)", "SCHOOL" },
  { "^improves your chance to get a critical strike with spells by (%d+)%%", "SPELLCRIT" },
  { "^improves your chance to hit with spells by (%d+)%%", "SPELLHIT" },
  { "^improves your chance to get a critical strike by (%d+)%%", "CRIT" },
  { "^improves your chance to hit by (%d+)%%", "HIT" },
  { "^%+(%d+) ranged attack power", "RAP" },
  { "^increases ranged attack power by (%d+)", "RAP" },
  { "^%+(%d+) attack power in cat", "FERAL_AP" },
  { "^increases attack power by (%d+) in cat", "FERAL_AP" },
  { "^%+(%d+) attack power", "AP" },
  { "^increases attack power by (%d+)", "AP" },
  { "^restores (%d+) mana per 5 sec", "MP5" },
  { "^restores (%d+) mana every 5 sec", "MP5" },
  { "^restores (%d+) health per 5 sec", "HP5" },
  { "^restores (%d+) health every 5 sec", "HP5" },
  { "^increased defense %+(%d+)", "DEFENSE" },
  { "^increases your chance to dodge an attack by (%d+)%%", "DODGE" },
  { "^increases your chance to parry an attack by (%d+)%%", "PARRY" },
  { "^increases your chance to block attacks with a shield by (%d+)%%", "BLOCK" },
  { "^increases the block value of your shield by (%d+)", "BLOCKVALUE" },
  { "^decreases the magical resistances of your spell targets by (%d+)", "SPELLPEN" },
  { "^increased [%a%-%s]+ %+(%d+)", "WEAPONSKILL" },
}

local function EscapePattern(s)
  return (s:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"))
end

local EQUIP_PREFIX = (ITEM_SPELL_TRIGGER_ONEQUIP or "Equip:"):lower() .. " "
local CLASSES_PATTERN = "^" .. EscapePattern(ITEM_CLASSES_ALLOWED or "Classes: %s"):gsub("%%%%s", "(.+)") .. "$"
local BLOCK_PATTERN = "^" .. EscapePattern((SHIELD_BLOCK_TEMPLATE or "%d Block"):lower()):gsub("%%%%d", "(%%d+)") .. "$"

local LOCALIZED_CLASSES = {}
for token, name in pairs(LOCALIZED_CLASS_NAMES_MALE or {}) do
  LOCALIZED_CLASSES[name] = token
end
for token, name in pairs(LOCALIZED_CLASS_NAMES_FEMALE or {}) do
  LOCALIZED_CLASSES[name] = token
end

local scanTip = CreateFrame("GameTooltip", "GearEverybodyScanTooltip", nil, "GameTooltipTemplate")

-- The item's tooltip text, minus the name line.
local function TooltipLines(itemString)
  local lines = {}
  if C_TooltipInfo then
    local data = C_TooltipInfo.GetHyperlink(itemString)
    for i, line in ipairs(data and data.lines or {}) do
      if i > 1 and line.leftText then
        lines[#lines + 1] = line.leftText
      end
    end
    return lines
  end
  scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
  scanTip:ClearLines()
  scanTip:SetHyperlink(itemString)
  for i = 2, scanTip:NumLines() do
    local fs = _G["GearEverybodyScanTooltipTextLeft" .. i]
    local text = fs and fs:GetText()
    if text then
      lines[#lines + 1] = text
    end
  end
  scanTip:Hide()
  return lines
end

local function Add(stats, key, value)
  if value then
    stats[key] = (stats[key] or 0) + value
  end
end

local function ParseEquipLine(text, stats)
  for _, p in ipairs(EQUIP_PATTERNS) do
    local a, b = text:match(p[1])
    if a then
      if p[2] == "SCHOOL" then
        if SCHOOLS[a] then
          Add(stats, SCHOOLS[a], tonumber(b))
        end
      else
        Add(stats, p[2], tonumber(a))
        if p[3] then
          Add(stats, p[3], tonumber(b))
        end
      end
      return
    end
  end
end

local function ParseClasses(text)
  local classes
  for _, name in ipairs({ strsplit(",", text) }) do
    local token = LOCALIZED_CLASSES[strtrim(name)]
    if token then
      classes = classes or {}
      classes[token] = true
    end
  end
  return classes
end

-- Reads equip bonuses, shield block and class restrictions from the item's tooltip.
local function ScanTooltip(itemString, stats)
  local classes
  for _, text in ipairs(TooltipLines(itemString)) do
    local lower = text:lower()
    if lower:sub(1, #EQUIP_PREFIX) == EQUIP_PREFIX then
      ParseEquipLine(lower:sub(#EQUIP_PREFIX + 1), stats)
    else
      local block = lower:match(BLOCK_PATTERN)
      if block then
        Add(stats, "BLOCKVALUE", tonumber(block))
      end
      local allowed = text:match(CLASSES_PATTERN)
      if allowed then
        classes = ParseClasses(allowed)
      end
    end
  end
  return classes
end

local function SplitItemString(link)
  local str = link and link:match("item:([%-%d:]+)")
  if not str then
    return nil
  end
  return { strsplit(":", str) }
end

-- Cache key: item ID plus random suffix ("of the Bear") and bonus IDs (which the modern
-- client can use for suffixes); ignores enchants and instance IDs.
function GE:ItemKey(link)
  local fields = SplitItemString(link)
  if not fields then
    return nil
  end
  local key = fields[1]
  local suffix = tonumber(fields[7]) or 0
  if suffix < 0 then
    key = key .. ":" .. suffix .. ":" .. (tonumber(fields[8]) or 0)
  elseif suffix > 0 then
    key = key .. ":" .. suffix
  end
  local numBonus = tonumber(fields[13]) or 0
  if numBonus > 0 then
    key = key .. ":b" .. table.concat(fields, ":", 14, math.min(13 + numBonus, #fields))
  end
  return key
end

-- Item string with the enchant and gems stripped, so the tooltip shows the item's own stats.
local function ScanString(link)
  local fields = SplitItemString(link)
  for i = 2, 6 do
    fields[i] = ""
  end
  return "item:" .. table.concat(fields, ":")
end

function GE:IsGear(link)
  if not link then
    return false
  end
  local itemID, _, _, equipLoc = GetItemInfoInstant(link)
  return itemID ~= nil and self.EQUIPPABLE[equipLoc] == true
end

-- Returns nil if the item isn't gear or isn't loaded yet (a load is requested and
-- GET_ITEM_INFO_RECEIVED will trigger a rescan).
function GE:ParseItem(link)
  local itemID, _, _, equipLoc, _, classID, subclassID = GetItemInfoInstant(link)
  if not itemID or not self.EQUIPPABLE[equipLoc] then
    return nil
  end
  local name, _, _, _, reqLevel = GetItemInfo(link)
  if not name then
    self.pendingItems[itemID] = true
    if C_Item and C_Item.RequestLoadItemDataByID then
      C_Item.RequestLoadItemDataByID(itemID)
    end
    return nil
  end

  local stats, spellStats = {}, {}
  for statKey, value in pairs(GetItemStats(link) or {}) do
    statKey = statKey:gsub("_SHORT$", "")
    if BASE_STATS[statKey] then
      Add(stats, BASE_STATS[statKey], value)
    elseif SPELL_STATS[statKey] then
      spellStats[statKey] = value
    elseif statKey == "ITEM_MOD_DAMAGE_PER_SECOND" then
      stats.DPS = value
    end
  end
  local classes = ScanTooltip(ScanString(link), stats)
  for statKey, value in pairs(spellStats) do
    local stat = SPELL_STATS[statKey]
    -- SPELLPOWER ("damage and healing") covers both SPELLDAMAGE and HEALING.
    local covered = stats[stat] or (stats.SPELLPOWER and (stat == "SPELLDAMAGE" or stat == "HEALING"))
    if not covered then
      stats[stat] = value
    end
  end

  return {
    s = stats,
    t = equipLoc,
    c = classID,
    sc = subclassID,
    lv = math.max(reqLevel or 1, 1),
    cl = classes,
  }
end

function GE:GetItem(link)
  local key = self:ItemKey(link)
  if not key then
    return nil
  end
  local rec = self.db.items[key]
  if not rec then
    rec = self:ParseItem(link)
    self.db.items[key] = rec
  end
  return rec
end
