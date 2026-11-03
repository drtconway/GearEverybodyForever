local _, GE = ...

local window

-- A movable window with a scrolling, hyperlink-aware text area (hover items for tooltips,
-- shift-click to link them in chat).
local function GetWindow()
  if window then
    return window
  end
  local f = CreateFrame("Frame", "GearEverybodyFrame", UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(620, 440)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  tinsert(UISpecialFrames, "GearEverybodyFrame")

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.title:SetPoint("TOP", 0, -5)

  local msg = CreateFrame("ScrollingMessageFrame", nil, f)
  msg:SetPoint("TOPLEFT", 14, -32)
  msg:SetPoint("BOTTOMRIGHT", -14, 12)
  msg:SetFontObject(ChatFontNormal)
  msg:SetJustifyH("LEFT")
  msg:SetFading(false)
  msg:SetMaxLines(2000)
  msg:SetHyperlinksEnabled(true)
  msg:EnableMouseWheel(true)
  msg:SetScript("OnMouseWheel", function(self, delta)
    for _ = 1, 3 do
      if delta > 0 then self:ScrollUp() else self:ScrollDown() end
    end
  end)
  msg:SetScript("OnHyperlinkEnter", function(self, link)
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    GameTooltip:SetHyperlink(link)
    GameTooltip:Show()
  end)
  msg:SetScript("OnHyperlinkLeave", function()
    GameTooltip:Hide()
  end)
  msg:SetScript("OnHyperlinkClick", function(_, link, text, button)
    SetItemRef(link, text, button)
  end)
  f.messages = msg

  window = f
  return f
end

function GE:ShowWindow(title, lines)
  local f = GetWindow()
  f.title:SetText("GearEverybody - " .. title)
  f.messages:Clear()
  for _, line in ipairs(lines) do
    f.messages:AddMessage(line == "" and " " or line)
  end
  f.messages:ScrollToTop()
  f:Show()
end

local function Ago(t)
  if not t then
    return "never"
  end
  local d = time() - t
  if d < 3600 then
    return math.floor(d / 60) .. "m ago"
  elseif d < 86400 then
    return math.floor(d / 3600) .. "h ago"
  end
  return math.floor(d / 86400) .. "d ago"
end

-- Every piece of gear sitting in any character's bags or bank that would upgrade someone.
function GE:ShowReport()
  local byTarget, order = {}, {}
  for _, holder in ipairs(self:GetChars()) do
    for _, where in ipairs({ "bags", "bank" }) do
      local listed = {}
      for _, item in ipairs(holder.char[where] or {}) do
        if not listed[item.l] then
          listed[item.l] = true
          local onlyChar = item.b and holder.char or nil
          for _, r in ipairs(self:FindUpgrades(item.l, holder.realm, holder.char.faction, onlyChar)) do
            local id = r.realm .. "/" .. r.name
            if not byTarget[id] then
              byTarget[id] = { target = r, items = {} }
              order[#order + 1] = id
            end
            local location = holder.char == r.char and ("own " .. where)
              or (self:DisplayName(holder) .. "'s " .. where)
            table.insert(byTarget[id].items, { link = item.l, r = r, location = location })
          end
        end
      end
    end
  end

  local lines = {}
  table.sort(order)
  for _, id in ipairs(order) do
    local group = byTarget[id]
    table.sort(group.items, function(a, b) return a.r.pct > b.r.pct end)
    lines[#lines + 1] = self:FormatCharLabel(group.target)
    for _, item in ipairs(group.items) do
      lines[#lines + 1] = ("    %s  %s  |cff9d9d9d- %s|r"):format(item.link, self:FormatUpgrade(item.r), item.location)
    end
    lines[#lines + 1] = ""
  end
  if #lines == 0 then
    lines[1] = "No upgrades found in any character's bags or bank."
  end
  lines[#lines + 1] = "|cff9d9d9dBank contents are recorded when you open the bank on each character.|r"
  self:ShowWindow("Upgrades in bags & banks", lines)
end

function GE:ShowCharacters()
  local lines = {}
  for _, entry in ipairs(self:GetChars()) do
    local c = entry.char
    local equipped = 0
    for _ in pairs(c.equipped or {}) do
      equipped = equipped + 1
    end
    local bank = c.bankScanned and #(c.bank or {}) or "?"
    local line = ("%s  |cff9d9d9d%s, equipped %d, bags %d, bank %s, updated %s|r"):format(
      self:FormatCharLabel(entry), c.faction or "?", equipped, #(c.bags or {}), bank, Ago(c.lastSeen))
    if c.ignore then
      line = line .. "  |cffff5555[ignored]|r"
    end
    lines[#lines + 1] = line
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "|cff9d9d9dCounts are gear only. Type /ge show <name> for details.|r"
  self:ShowWindow("Characters", lines)
end

function GE:ShowCharacter(entry)
  local c = entry.char
  local lines = { self:FormatCharLabel(entry), "", "|cffffd100Equipped|r" }
  for _, slot in ipairs(self.SLOTS) do
    if c.equipped[slot] then
      lines[#lines + 1] = ("    %s: %s"):format(self.SLOT_NAMES[slot], c.equipped[slot])
    end
  end
  for _, where in ipairs({ "bags", "bank" }) do
    lines[#lines + 1] = ""
    lines[#lines + 1] = "|cffffd100" .. (where == "bags" and "Bags" or "Bank") .. "|r"
    if where == "bank" and not c.bankScanned then
      lines[#lines + 1] = "    |cff9d9d9dNot recorded yet - open the bank on this character.|r"
    end
    for _, item in ipairs(c[where] or {}) do
      lines[#lines + 1] = "    " .. item.l .. (item.b and "  |cff9d9d9d(soulbound)|r" or "")
    end
  end
  self:ShowWindow(self:DisplayName(entry), lines)
end

-- "Name" or "Name-Realm"; prefers the current realm.
function GE:FindChar(text)
  local name, realm = text:match("^([^%-]+)%-(.+)$")
  name = (name or text):lower()
  local fallback
  for _, entry in ipairs(self:GetChars()) do
    if entry.name:lower() == name then
      if realm and entry.realm:lower():gsub("%s", "") == realm:lower():gsub("%s", "") then
        return entry
      elseif not realm and entry.realm == self.realm then
        return entry
      end
      fallback = fallback or entry
    end
  end
  return fallback
end

local function SpecKeys(class)
  local keys = {}
  for _, spec in ipairs(GE.SPECS[class]) do
    keys[#keys + 1] = spec.key .. " (" .. spec.name .. ")"
  end
  return table.concat(keys, ", ")
end

function GE:HandleSpec(args)
  local a, b = args:match("^(%S*)%s*(%S*)$")
  if a == "" then
    for _, entry in ipairs(self:GetChars()) do
      if entry.char.class then
        self:Print(self:FormatCharLabel(entry), "- options:", SpecKeys(entry.char.class))
      end
    end
    self:Print("Set with /ge spec <name> <spec>, or /ge spec <spec> for this character.")
    return
  end

  local entry, specKey
  if b ~= "" then
    entry, specKey = self:FindChar(a), b:lower()
  elseif self:FindChar(a) then
    -- "/ge spec Name": just list that character's options
    entry = self:FindChar(a)
  else
    entry, specKey = { name = self.name, realm = self.realm, char = self.char }, a:lower()
  end
  if not entry then
    self:Print("No character named", a)
    return
  end
  for _, spec in ipairs(self.SPECS[entry.char.class]) do
    if spec.key == specKey then
      entry.char.spec = spec.key
      self:Print(self:FormatCharLabel(entry))
      return
    end
  end
  self:Print(specKey and "Unknown spec." or self:FormatCharLabel(entry), "Options for",
    self:DisplayName(entry) .. ":", SpecKeys(entry.char.class))
end

-- /ge stats <item link>: show what the parser read from an item and how each character scores it.
function GE:ShowItemStats(link)
  if not self:IsGear(link) then
    self:Print("Usage: /ge stats <shift-click an item>")
    return
  end
  local rec = self:GetItem(link)
  if not rec then
    self:Print("Item not loaded yet, try again in a moment.")
    return
  end
  local parts = {}
  for stat, value in pairs(rec.s) do
    parts[#parts + 1] = stat .. "=" .. value
  end
  table.sort(parts)
  self:Print(link, rec.t, "class", rec.c, "subclass", rec.sc, "level", rec.lv)
  self:Print("Stats:", #parts > 0 and table.concat(parts, " ") or "none")
  local key = self:ItemKey(link)
  for _, entry in ipairs(self:GetChars()) do
    local c = entry.char
    if c.class then
      local ok = self:CanUse(rec, c)
      local r = ok and self:Evaluate(rec, key, c)
      self:Print("  ", self:FormatCharLabel(entry, true),
        not ok and "can't use" or r and self:FormatUpgrade(r) or "not an upgrade",
        ("(score %.1f)"):format(self:Score(rec, self:GetSpec(c).w, (self.INVTYPE_SLOTS[rec.t] or { 16 })[1])))
    end
  end
end

local function Toggle(setting, label)
  GE.settings[setting] = not GE.settings[setting]
  GE:Print(label, GE.settings[setting] and "on" or "off")
end

local HELP = {
  "/ge report - upgrades sitting in any character's bags or bank",
  "/ge chars - list tracked characters",
  "/ge show <name> - a character's equipped gear, bags and bank",
  "/ge spec [name] [spec] - view or set the spec used to score gear",
  "/ge ignore <name> - stop suggesting upgrades for a character (e.g. bank alts)",
  "/ge forget <name> - delete a character's data",
  "/ge stats <item> - show how an item was read and scored",
  "/ge alert - toggle the chat alert for new upgrades",
  "/ge strict - toggle only suggesting a character's best armor type",
  "/ge realms - toggle including other realms and factions",
  "/ge levels <n> - suggest items up to n levels above a character (now %d)",
  "/ge min <pct> - smallest upgrade to show, in percent (now %d)",
}

function GE:HandleSlash(msg)
  local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()

  if cmd == "report" then
    self:ShowReport()
  elseif cmd == "chars" then
    self:ShowCharacters()
  elseif cmd == "show" or cmd == "ignore" or cmd == "forget" then
    local entry = rest ~= "" and self:FindChar(rest) or nil
    if not entry then
      self:Print("No character named", rest)
    elseif cmd == "show" then
      self:ShowCharacter(entry)
    elseif cmd == "ignore" then
      entry.char.ignore = not entry.char.ignore or nil
      self:Print(self:DisplayName(entry), entry.char.ignore and "ignored" or "no longer ignored")
    elseif entry.char == self.char then
      self:Print("Can't forget the character you're logged in on.")
    else
      self.db.chars[entry.realm][entry.name] = nil
      self:Print("Forgot", self:DisplayName(entry))
    end
  elseif cmd == "spec" then
    self:HandleSpec(rest)
  elseif cmd == "stats" then
    self:ShowItemStats(rest:match("|Hitem:.-|h.-|h") and rest)
  elseif cmd == "alert" then
    Toggle("alert", "Upgrade alerts")
  elseif cmd == "strict" then
    Toggle("strictArmor", "Best armor type only")
  elseif cmd == "realms" then
    Toggle("allRealms", "All realms and factions")
  elseif (cmd == "levels" or cmd == "min") and tonumber(rest) then
    self.settings[cmd == "levels" and "levelWindow" or "minPct"] = tonumber(rest)
    self:Print(cmd == "levels" and "Level window" or "Minimum upgrade", tonumber(rest))
  else
    self:Print("commands:")
    for _, line in ipairs(HELP) do
      print("  " .. line:format(line:find("levels") and self.settings.levelWindow or self.settings.minPct))
    end
  end
end

function GE:InitSlashCommands()
  SLASH_GEAREVERYBODY1 = "/ge"
  SLASH_GEAREVERYBODY2 = "/geareverybody"
  SlashCmdList.GEAREVERYBODY = function(msg)
    self:HandleSlash(msg)
  end
end
