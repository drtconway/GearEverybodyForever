local _, GE = ...

function GE:GetChars()
  local list = {}
  for realm, chars in pairs(self.db.chars) do
    for name, c in pairs(chars) do
      list[#list + 1] = { realm = realm, name = name, char = c }
    end
  end
  table.sort(list, function(a, b)
    if a.realm ~= b.realm then
      return a.realm < b.realm
    end
    return a.name < b.name
  end)
  return list
end

-- Can an item held on realm/faction reach this character by mail?
function GE:IsEligible(entry, realm, faction)
  local c = entry.char
  if c.ignore or not c.class or not self.SPECS[c.class] then
    return false
  end
  if self.settings.allRealms then
    return true
  end
  return entry.realm == realm and c.faction == faction
end

function GE:GetSpec(c)
  local specs = self.SPECS[c.class]
  for _, spec in ipairs(specs) do
    if spec.key == c.spec then
      return spec
    end
  end
  return specs[1]
end

function GE:BestArmor(class, level)
  local best = 1
  for subclass = 2, 4 do
    local gate = self.CLASS_ARMOR[class][subclass]
    if gate and gate <= level then
      best = subclass
    end
  end
  return best
end

function GE:CanDualWield(c)
  local level = self.DUAL_WIELD_LEVEL[c.class]
  return level ~= nil and c.level >= level
end

-- Returns whether the character can use the item, and the level they can first use it at.
function GE:CanUse(rec, c)
  if rec.cl and not rec.cl[c.class] then
    return false
  end
  local reqLevel = rec.lv
  if rec.c == 2 then
    if not self.CLASS_WEAPONS[c.class][rec.sc] then
      return false
    end
  elseif rec.c == 4 then
    local gate = rec.sc == 0 and 1 or self.CLASS_ARMOR[c.class][rec.sc]
    if not gate then
      return false
    end
    reqLevel = math.max(reqLevel, gate)
    if self.settings.strictArmor and self.ARMOR_TYPED[rec.t] and rec.sc >= 1 and rec.sc <= 4
        and rec.sc ~= self:BestArmor(c.class, math.max(c.level, reqLevel)) then
      return false
    end
  else
    return false
  end
  return true, reqLevel
end

function GE:Score(rec, w, slot)
  local total = 0
  for stat, value in pairs(rec.s) do
    local weight
    if stat == "SPELLPOWER" then
      weight = (w.SPELLDAMAGE or 0) + (w.HEALING or 0)
    elseif stat == "DPS" then
      if slot == 18 then
        weight = w.RANGED_DPS or 0
      elseif slot == 17 then
        weight = (w.MELEE_DPS or 0) * 0.5
      else
        weight = w.MELEE_DPS or 0
      end
    else
      weight = w[stat] or 0
    end
    total = total + value * weight
  end
  return total
end

-- Score of what the character has in a slot: 0 if empty, nil if the item isn't loaded.
function GE:SlotScore(c, slot, w)
  local link = c.equipped[slot]
  if not link then
    return 0
  end
  local rec = self:GetItem(link)
  if not rec then
    return nil
  end
  return self:Score(rec, w, slot), rec
end

-- Best upgrade this item offers the character, or nil.
-- Result: { slot, slotName, pct (math.huge for an empty slot), reqLevel (only if above their level) }
function GE:Evaluate(rec, key, c)
  local ok, reqLevel = self:CanUse(rec, c)
  if not ok or reqLevel > c.level + self.settings.levelWindow then
    return nil
  end
  for _, link in pairs(c.equipped) do
    if self:ItemKey(link) == key then
      return nil -- already wearing one
    end
  end

  local w = self:GetSpec(c).w
  local best
  local function Consider(slot, new, old)
    if not old or new <= old then
      return
    end
    local pct = old > 0 and (new - old) / old * 100 or math.huge
    if pct >= self.settings.minPct and (not best or pct > best.pct) then
      best = { slot = slot, pct = pct }
    end
  end

  local t = rec.t
  local fixed = self.INVTYPE_SLOTS[t]
  if fixed then
    -- Rings and trinkets replace whichever of the pair is weaker.
    local slot, old
    for _, s in ipairs(fixed) do
      local score = self:SlotScore(c, s, w)
      if score == nil then
        return nil
      end
      if not old or score < old then
        slot, old = s, score
      end
    end
    Consider(slot, self:Score(rec, w, slot), old)
  else
    local mh, mhRec = self:SlotScore(c, 16, w)
    local oh = self:SlotScore(c, 17, w)
    if mh == nil or oh == nil then
      return nil
    end
    local wieldsTwoHander = mhRec and mhRec.t == "INVTYPE_2HWEAPON"
    if t == "INVTYPE_2HWEAPON" then
      Consider(16, self:Score(rec, w, 16), mh + oh)
    elseif t == "INVTYPE_WEAPON" or t == "INVTYPE_WEAPONMAINHAND" then
      Consider(16, self:Score(rec, w, 16), mh)
      if t == "INVTYPE_WEAPON" and not wieldsTwoHander and self:CanDualWield(c) then
        Consider(17, self:Score(rec, w, 17), oh)
      end
    elseif not wieldsTwoHander then
      -- Off-hand weapon, shield or held item. Swapping a two-hander for 1H + off-hand
      -- needs two items, so we don't try to judge that.
      if t ~= "INVTYPE_WEAPONOFFHAND" or self:CanDualWield(c) then
        Consider(17, self:Score(rec, w, 17), oh)
      end
    end
  end

  if best then
    best.slotName = (best.slot == 16 and t == "INVTYPE_2HWEAPON") and "Two-Hand" or self.SLOT_NAMES[best.slot]
    best.reqLevel = reqLevel > c.level and reqLevel or nil
  end
  return best
end

-- Every eligible character this item could upgrade, best first.
-- realm/faction say where the item is; onlyChar restricts to one character (soulbound items).
function GE:FindUpgrades(link, realm, faction, onlyChar)
  local results = {}
  local rec = self:GetItem(link)
  if not rec then
    return results
  end
  local key = self:ItemKey(link)
  for _, entry in ipairs(self:GetChars()) do
    if (not onlyChar or entry.char == onlyChar) and self:IsEligible(entry, realm, faction) then
      local r = self:Evaluate(rec, key, entry.char)
      if r then
        r.name, r.realm, r.char = entry.name, entry.realm, entry.char
        results[#results + 1] = r
      end
    end
  end
  table.sort(results, function(a, b)
    return a.pct > b.pct
  end)
  return results
end

function GE:ClassColor(class, text)
  local color = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class]
  if color and color.colorStr then
    return "|c" .. color.colorStr .. text .. "|r"
  end
  return text
end

function GE:DisplayName(entry)
  if entry.realm ~= self.realm then
    return entry.name .. "-" .. entry.realm
  end
  return entry.name
end

-- entry is anything with name, realm and char (a GetChars entry or an upgrade result).
function GE:FormatCharLabel(entry, short)
  local label = self:ClassColor(entry.char.class, self:DisplayName(entry))
  if short then
    return label
  end
  return ("%s |cff9d9d9d%d %s|r"):format(label, entry.char.level or 0, self:GetSpec(entry.char).name)
end

function GE:FormatUpgrade(r)
  local text
  if r.pct == math.huge then
    text = "|cff00ff00empty|r " .. r.slotName
  else
    text = ("|cff00ff00+%d%%|r %s"):format(math.floor(r.pct + 0.5), r.slotName)
  end
  if r.reqLevel then
    text = text .. (" |cffff9900(lvl %d)|r"):format(r.reqLevel)
  end
  return text
end
