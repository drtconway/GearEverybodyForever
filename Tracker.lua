local _, GE = ...

local GetContainerNumSlots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots

local function GetContainerItem(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if info then
      return info.hyperlink, info.isBound
    end
    return nil
  end
  return GetContainerItemLink(bag, slot)
end

local BAGS = {}
for bag = 0, NUM_BAG_SLOTS do
  BAGS[#BAGS + 1] = bag
end

local BANK = { BANK_CONTAINER }
for bag = NUM_BAG_SLOTS + 1, NUM_BAG_SLOTS + NUM_BANKBAGSLOTS do
  BANK[#BANK + 1] = bag
end
local IS_BANK_BAG = {}
for _, bag in ipairs(BANK) do
  IS_BANK_BAG[bag] = true
end

function GE:InitTracker()
  local events = {
    "PLAYER_LOGIN", "PLAYER_LEVEL_UP", "PLAYER_EQUIPMENT_CHANGED",
    "BAG_UPDATE", "BAG_UPDATE_DELAYED",
    "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED",
    "GET_ITEM_INFO_RECEIVED",
  }
  for _, event in ipairs(events) do
    self.eventFrame:RegisterEvent(event)
  end
end

function GE:PLAYER_LOGIN()
  self.realm = GetRealmName()
  self.name = UnitName("player")
  self.db.chars[self.realm] = self.db.chars[self.realm] or {}
  local c = self.db.chars[self.realm][self.name] or { equipped = {}, bags = {}, bank = {} }
  self.db.chars[self.realm][self.name] = c
  self.char = c

  local _, class = UnitClass("player")
  c.class = class
  c.level = UnitLevel("player")
  c.faction = UnitFactionGroup("player")

  self:ScanEquipment()
  self:ScanBags()
  self:Prewarm()
  -- Everything in your bags at login counts as already seen; alert only on new arrivals.
  C_Timer.After(5, function()
    self:Rescan()
    self.alertsReady = true
  end)
end

function GE:PLAYER_LEVEL_UP(level)
  if self.char then
    self.char.level = level
  end
end

function GE:PLAYER_EQUIPMENT_CHANGED()
  self:Schedule("equip", 0.5, self.ScanEquipment)
end

function GE:BAG_UPDATE(bag)
  if self.bankOpen and IS_BANK_BAG[bag] then
    self.bankDirty = true
  end
end

function GE:BAG_UPDATE_DELAYED()
  self:Schedule("bags", 0.5, function()
    self:ScanBags()
    if self.bankDirty and self.bankOpen then
      self:ScanBank()
    end
  end)
end

function GE:PLAYERBANKSLOTS_CHANGED()
  if self.bankOpen then
    self:Schedule("bank", 0.5, self.ScanBank)
  end
end

function GE:BANKFRAME_OPENED()
  self.bankOpen = true
  self:ScanBank()
  self:Schedule("bank", 1, self.ScanBank)
end

function GE:BANKFRAME_CLOSED()
  self.bankOpen = false
end

function GE:GET_ITEM_INFO_RECEIVED(itemID)
  if self.pendingItems[itemID] then
    self.pendingItems[itemID] = nil
    self:Schedule("rescan", 1, self.Rescan)
  end
end

function GE:Rescan()
  self:ScanEquipment()
  self:ScanBags()
  if self.bankOpen then
    self:ScanBank()
  end
end

function GE:ScanEquipment()
  local c = self.char
  if not c then
    return
  end
  c.lastSeen = time()
  c.equipped = {}
  for _, slot in ipairs(self.SLOTS) do
    local link = GetInventoryItemLink("player", slot)
    if link then
      c.equipped[slot] = link
      self.seen[link] = true
      self:GetItem(link)
    end
  end
end

-- Returns the gear (only) found in the given containers as { l = link, b = isBound }.
function GE:ScanContainers(bags, alert)
  local list = {}
  for _, bag in ipairs(bags) do
    for slot = 1, GetContainerNumSlots(bag) or 0 do
      local link, bound = GetContainerItem(bag, slot)
      if self:IsGear(link) then
        list[#list + 1] = { l = link, b = bound or nil }
        self:GetItem(link)
        if alert then
          self:CheckNewItem(link, bound)
        else
          self.seen[link] = true
        end
      end
    end
  end
  return list
end

function GE:ScanBags()
  if not self.char then
    return
  end
  self.char.lastSeen = time()
  self.char.bags = self:ScanContainers(BAGS, true)
end

function GE:ScanBank()
  if not self.char or not self.bankOpen then
    return
  end
  self.bankDirty = false
  self.char.bank = self:ScanContainers(BANK, false)
  self.char.bankScanned = time()
end

-- Ask the client to load every item we know about so alts' gear can be scored.
function GE:Prewarm()
  for _, entry in ipairs(self:GetChars()) do
    local c = entry.char
    for _, link in pairs(c.equipped or {}) do
      self:GetItem(link)
    end
    for _, where in ipairs({ "bags", "bank" }) do
      for _, item in ipairs(c[where] or {}) do
        self:GetItem(item.l)
      end
    end
  end
end

-- Chat alert when a piece of gear shows up in your bags that would help one of your characters.
function GE:CheckNewItem(link, bound)
  if self.seen[link] then
    return
  end
  if not self.alertsReady then
    self.seen[link] = true
    return
  end
  if not self:GetItem(link) then
    return -- not loaded yet; the rescan after it loads will try again
  end
  self.seen[link] = true
  if not self.settings.alert then
    return
  end

  local results = self:FindUpgrades(link, self.realm, self.char.faction, bound and self.char or nil)
  if #results == 0 then
    return
  end
  local parts = {}
  for i, r in ipairs(results) do
    if i > 5 then
      parts[#parts + 1] = ("and %d more"):format(#results - 5)
      break
    end
    parts[#parts + 1] = self:FormatCharLabel(r, true) .. " " .. self:FormatUpgrade(r)
  end
  self:Print(link, "could be an upgrade for", table.concat(parts, ", "))
end
