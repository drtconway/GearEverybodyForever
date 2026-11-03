local addonName, GE = ...
_G.GearEverybody = GE

GE.PREFIX = "|cff33ccffGearEverybody|r"
GE.pendingItems = {}
GE.timers = {}
GE.seen = {}

local DEFAULTS = {
  alert = true,       -- chat message when you pick up an item that is an upgrade for someone
  strictArmor = true, -- only suggest a character's best armor type (no leather for a level 40+ hunter)
  levelWindow = 5,    -- also suggest items up to this many levels above a character
  minPct = 1,         -- smallest per-slot improvement worth mentioning
  allRealms = false,  -- include characters on other realms / factions
  maxLines = 8,       -- tooltip lines before collapsing into "...and N more"
}

function GE:Print(...)
  print(self.PREFIX, ...)
end

-- Runs fn(self) after delay; repeated requests with the same name collapse into one.
function GE:Schedule(name, delay, fn)
  if self.timers[name] then
    return
  end
  self.timers[name] = true
  C_Timer.After(delay, function()
    self.timers[name] = nil
    fn(self)
  end)
end

local frame = CreateFrame("Frame")
GE.eventFrame = frame
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, ...)
  if GE[event] then
    GE[event](GE, ...)
  end
end)

function GE:ADDON_LOADED(name)
  if name ~= addonName then
    return
  end
  frame:UnregisterEvent("ADDON_LOADED")

  GearEverybodyDB = GearEverybodyDB or {}
  local db = GearEverybodyDB
  db.chars = db.chars or {}
  db.items = db.items or {}
  db.settings = db.settings or {}
  for k, v in pairs(DEFAULTS) do
    if db.settings[k] == nil then
      db.settings[k] = v
    end
  end
  -- Parsed item stats are cached; throw them away when the parser changes.
  if db.parserVersion ~= self.PARSER_VERSION then
    wipe(db.items)
    db.parserVersion = self.PARSER_VERSION
  end

  self.db = db
  self.settings = db.settings

  self:InitTracker()
  self:InitTooltips()
  self:InitSlashCommands()
end
