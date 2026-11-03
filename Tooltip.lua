local _, GE = ...

-- Tooltip lines that mean only the current character can use the item.
local BOUND_LINES = {}
for _, text in ipairs({ ITEM_SOULBOUND, ITEM_BIND_ON_PICKUP, ITEM_BIND_QUEST }) do
  BOUND_LINES[text] = true
end

local function IsBoundTooltip(tooltip)
  local name = tooltip:GetName()
  if not name then
    return false
  end
  for i = 2, math.min(tooltip:NumLines(), 8) do
    local fs = _G[name .. "TextLeft" .. i]
    local text = fs and fs:GetText()
    if text and BOUND_LINES[text] then
      return true
    end
  end
  return false
end

function GE:AddTooltipLines(tooltip)
  if not self.char then
    return
  end
  local _, link = tooltip:GetItem()
  if not self:IsGear(link) then
    return
  end
  local onlyChar = IsBoundTooltip(tooltip) and self.char or nil
  local results = self:FindUpgrades(link, self.realm, self.char.faction, onlyChar)
  if #results == 0 then
    return
  end

  tooltip:AddLine("Upgrade for:", 0.2, 0.8, 1)
  for i, r in ipairs(results) do
    if i > self.settings.maxLines then
      tooltip:AddLine(("  ...and %d more"):format(#results - i + 1), 0.6, 0.6, 0.6)
      break
    end
    tooltip:AddDoubleLine("  " .. self:FormatCharLabel(r), self:FormatUpgrade(r))
  end
  tooltip:Show()
end

function GE:InitTooltips()
  if TooltipDataProcessor and C_TooltipInfo and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
      if tooltip == GameTooltip or tooltip == ItemRefTooltip then
        self:AddTooltipLines(tooltip)
      end
    end)
  else
    for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
      local ready = true
      tooltip:HookScript("OnTooltipSetItem", function()
        if ready then
          ready = false
          self:AddTooltipLines(tooltip)
        end
      end)
      tooltip:HookScript("OnTooltipCleared", function()
        ready = true
      end)
    end
  end
end
