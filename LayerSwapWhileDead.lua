
-- LayerSwapWhileDead for WoW Forever.
-- Independent request lifecycle; interoperates with LayerSwap through its r3 whisper protocol.

local ADDON = ...
local VERSION = C_AddOns.GetAddOnMetadata(ADDON, "Version") or "Unknown"
local PREFIX = "LayerSwap"
local PLAYER_RETRY_MEMORY, WHO_RETRY_INTERVAL = 1200, 5
local SEARCH_TIMEOUT, EXTERNAL_SEARCH_QUIET = 25, 30
local WHISPERS_PER_TICK, MAX_SEND_TICKS = 4, 20
local CLASSES = { 1, 2, 3, 4, 5, 7, 8, 9, 11 }

local frame = CreateFrame("Frame")
local launcher, miniLauncher, miniIcon
local pending, searchInFlight, ownSearch, lastOtherSearch, candidate, swapGroup
local hostOwner, hostTracking, changingHost
local lastWhoSearch = -WHO_RETRY_INTERVAL
local round, layer, layerZone, staleUntil = 0, nil, nil, 0
local ready = false

local function secret(value)
  return type(issecretvalue) == "function" and issecretvalue(value)
end

local function plainString(value)
  return not secret(value) and type(value) == "string" and value ~= ""
end

local function say(text)
  local line = "|cff77b9e8LayerSwapWhileDead:|r " .. text
  if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(line) else print(line) end
end

local function showMessage(text, quiet)
  if not quiet then say(text) end
end

local openOptions
local updateButton

local function updateMiniPosition()
  if not miniLauncher or not _G.LayerSwapMini then return end
  local position = LayerSwapWhileDeadDB and LayerSwapWhileDeadDB.miniPosition or "Right"
  miniLauncher:ClearAllPoints()
  if position == "Top" then
    miniLauncher:SetPoint("BOTTOM", _G.LayerSwapMini, "TOP", 0, 2)
  elseif position == "Bottom" then
    miniLauncher:SetPoint("TOP", _G.LayerSwapMini, "BOTTOM", 0, -2)
  elseif position == "Left" then
    miniLauncher:SetPoint("RIGHT", _G.LayerSwapMini, "LEFT", -2, 0)
  else
    miniLauncher:SetPoint("LEFT", _G.LayerSwapMini, "RIGHT", 2, 0)
  end
end

SLASH_LAYERSWAPWHILEDEAD1 = "/lswd"
SlashCmdList.LAYERSWAPWHILEDEAD = function(message)
  message = string.lower((message or ""):match("^%s*(.-)%s*$"))

  if message == "combat on" then
    LayerSwapWhileDeadDB = LayerSwapWhileDeadDB or {}
    LayerSwapWhileDeadDB.allowInCombat = true
    if updateButton then updateButton() end
    say("Combat swapping enabled. Dead swapping is always enabled.")
    if openOptions then openOptions() end

  elseif message == "combat off" then
    LayerSwapWhileDeadDB = LayerSwapWhileDeadDB or {}
    LayerSwapWhileDeadDB.allowInCombat = false
    if updateButton then updateButton() end
    say("Combat swapping disabled. Dead swapping remains enabled.")
    if openOptions then openOptions() end

  elseif message == "status" then
    local enabled = LayerSwapWhileDeadDB and LayerSwapWhileDeadDB.allowInCombat
    say("Combat swapping is " .. (enabled and "enabled" or "disabled") .. ". Dead swapping is enabled.")

  elseif message == "version" then
    say("Version " .. VERSION)

  else
    if openOptions then openOptions() else say("Settings are not ready yet.") end
  end
end

local function setupOptions()
  if _G.LayerSwapWhileDeadOptions then return end

  local panel = CreateFrame("Frame", "LayerSwapWhileDeadOptions", UIParent)
  panel.name = "LayerSwapWhileDead"

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
  title:SetText("LayerSwapWhileDead")

  local versionText = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  versionText:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, -18)
  versionText:SetJustifyH("RIGHT")
  versionText:SetText("v" .. VERSION)

  local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
  description:SetText("Layer swapping while dead is always available.")

  local checkbox = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
  checkbox:SetPoint("TOPLEFT", description, "BOTTOMLEFT", -4, -12)
  checkbox:SetSize(26, 26)

  local label = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  label:SetPoint("LEFT", checkbox, "RIGHT", 4, 0)
  label:SetText("Allow layer swap while in combat")
  checkbox:SetHitRectInsets(0, -label:GetStringWidth() - 8, 0, 0)

  local positionLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  positionLabel:SetPoint("TOPLEFT", checkbox, "BOTTOMLEFT", 4, -14)
  positionLabel:SetText("Minibar button position")

  local positionDropdown = CreateFrame("Frame", "LayerSwapWhileDeadPositionDropdown", panel, "UIDropDownMenuTemplate")
  positionDropdown:SetPoint("TOPLEFT", positionLabel, "BOTTOMLEFT", -16, -2)
  UIDropDownMenu_SetWidth(positionDropdown, 120)

  local positions = { "Top", "Left", "Right", "Bottom" }
  UIDropDownMenu_Initialize(positionDropdown, function(self, level)
    for _, position in ipairs(positions) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = position
      info.value = position
      info.func = function()
        LayerSwapWhileDeadDB = LayerSwapWhileDeadDB or {}
        LayerSwapWhileDeadDB.miniPosition = position
        UIDropDownMenu_SetSelectedValue(positionDropdown, position)
        updateMiniPosition()
      end
      info.checked = (LayerSwapWhileDeadDB and LayerSwapWhileDeadDB.miniPosition or "Right") == position
      UIDropDownMenu_AddButton(info, level)
    end
  end)

  checkbox:SetScript("OnClick", function(self)
    LayerSwapWhileDeadDB = LayerSwapWhileDeadDB or {}
    LayerSwapWhileDeadDB.allowInCombat = self:GetChecked() and true or false
    if updateButton then updateButton() end
    say("Combat swapping " .. (LayerSwapWhileDeadDB.allowInCombat and "enabled." or "disabled."))
  end)

  panel:SetScript("OnShow", function()
    LayerSwapWhileDeadDB = LayerSwapWhileDeadDB or {}
    checkbox:SetChecked(LayerSwapWhileDeadDB.allowInCombat == true)
    if type(LayerSwapWhileDeadDB.miniPosition) ~= "string" then
      LayerSwapWhileDeadDB.miniPosition = "Right"
    end
    UIDropDownMenu_SetSelectedValue(positionDropdown, LayerSwapWhileDeadDB.miniPosition)
    UIDropDownMenu_SetText(positionDropdown, LayerSwapWhileDeadDB.miniPosition)
    updateMiniPosition()
  end)

  local category
  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local ok, result = pcall(Settings.RegisterCanvasLayoutCategory, panel, "LayerSwapWhileDead")
    if ok and result then
      category = result
      pcall(Settings.RegisterAddOnCategory, category)
    end
  elseif InterfaceOptions_AddCategory then
    pcall(InterfaceOptions_AddCategory, panel)
  end

  openOptions = function()
    if InCombatLockdown and InCombatLockdown() then
      say("The settings window can only be opened out of combat.")
      return
    end
    if category and Settings and Settings.OpenToCategory then
      local ok = pcall(Settings.OpenToCategory, category:GetID())
      if ok then return end
    end
    if InterfaceOptionsFrame_OpenToCategory then
      pcall(InterfaceOptionsFrame_OpenToCategory, panel)
      pcall(InterfaceOptionsFrame_OpenToCategory, panel)
    else
      say("The Blizzard AddOns settings window is unavailable.")
    end
  end
end

local function swapButtonLabel()
  return LayerSwapWhileDeadDB and LayerSwapWhileDeadDB.allowInCombat and "Force swap" or "Dead swap"
end

updateButton = function()
  local text = pending and (pending.phase == "searching" and "Cancel search" or pending.phase == "waiting_for_invite" and "Stop waiting" or "Cancel requests") or (candidate and "Clear invite" or swapButtonLabel())
  if launcher then launcher:SetText(text); launcher:SetEnabled(ready) end
  if miniLauncher then
    miniLauncher:SetEnabled(ready)
    miniIcon:SetDesaturated(not ready)
    if pending then miniIcon:SetVertexColor(1, 0.45, 0.45)
    elseif candidate then miniIcon:SetVertexColor(1, 0.8, 0.4)
    else miniIcon:SetVertexColor(1, 1, 1) end
    if GameTooltip and GameTooltip:IsOwned(miniLauncher) then
      GameTooltip:SetText(text)
      GameTooltip:Show()
    end
  end
end

local function endRequest(text)
  if pending then pending.phase = "cancelled" end
  pending = nil
  if text then showMessage(text) end
  updateButton()
end

local function zoneInfo()
  if not (C_Map and type(C_Map.GetBestMapForUnit) == "function" and type(C_Map.GetMapInfo) == "function") then
    return nil, nil
  end
  local id = C_Map.GetBestMapForUnit("player")
  if secret(id) or type(id) ~= "number" or id <= 0 then return nil, nil end
  local zone = id
  local zoneType = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3
  for _ = 1, 6 do
    local info = C_Map.GetMapInfo(zone)
    if type(info) ~= "table" or secret(info.mapType) or type(info.mapType) ~= "number" then break end
    if info.mapType == zoneType then break end
    local parent = info.parentMapID
    if info.mapType < zoneType or secret(parent) or type(parent) ~= "number" or parent <= 0 then break end
    zone = parent
  end
  local info = C_Map.GetMapInfo(zone)
  local name = type(info) == "table" and info.name or nil
  if not plainString(name) then return nil, nil end
  return zone, name
end

local function observe(unit)
  if GetTime() < staleUntil then return end
  if type(UnitPlayerControlled) == "function" then
    local controlled = UnitPlayerControlled(unit)
    if secret(controlled) or controlled then return end
  end
  local guid = UnitGUID(unit)
  if not plainString(guid) then return end
  local kind, server, zoneUID = guid:match("^(%a+)%-%d+%-(%d+)%-%d+%-(%d+)%-")
  if (kind ~= "Creature" and kind ~= "Vehicle") or not server or not zoneUID then return end
  local zone = zoneInfo()
  if zone then layer, layerZone = server .. "-" .. zoneUID, zone end
end

local function scanLayer()
  observe("target")
  observe("mouseover")
  for i = 1, 40 do observe("nameplate" .. i) end
end

local function invalidateLayer()
  layer, layerZone = nil, nil
  staleUntil = GetTime() + 10
end

local function position(zone)
  if not (C_Map and type(C_Map.GetPlayerMapPosition) == "function") then return nil end
  local pos = C_Map.GetPlayerMapPosition(zone, "player")
  if secret(pos) or type(pos) ~= "table" then return nil end
  local x, y = pos.x, pos.y
  if type(pos.GetXY) == "function" then x, y = pos:GetXY() end
  if secret(x) or secret(y) or type(x) ~= "number" or type(y) ~= "number"
      or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
  return string.format("%.1f,%.1f", x * 100, y * 100)
end

local function shortName(name)
  if not plainString(name) then return nil end
  return name:match("^([^%-]+)")
end

local function groupLeader()
  if not IsInGroup() or (type(IsInRaid) == "function" and IsInRaid())
      or type(UnitExists) ~= "function" or type(UnitIsGroupLeader) ~= "function" then return nil end
  for i = 1, 4 do
    local unit = "party" .. i
    local okExists, exists = pcall(UnitExists, unit)
    if not okExists or secret(exists) then return nil end
    if exists then
      local okLeader, leader = pcall(UnitIsGroupLeader, unit)
      if not okLeader or secret(leader) then return nil end
      if leader then
        local okName, first, surname = pcall(UnitName, unit)
        if not okName or not plainString(first) then return nil end
        if plainString(surname) then
          local constants = Constants and Constants.CharacterNameSeparatorConsts
          local sep = constants and constants.CHARACTERNAME_SURNAME_SEPARATOR
          first = first .. (plainString(sep) and sep or " ") .. surname
        end
        return shortName(first)
      end
    end
  end
end

local function restoreHosting(p)
  if hostOwner ~= p then return end
  hostOwner = nil
  if type(LayerSwapDB) ~= "table" or LayerSwapDB.hosting ~= false then return end
  if IsInGroup() then
    say("Host was not restored because you are still in a group.")
    return
  end
  local command = SlashCmdList and SlashCmdList.LAYERSWAP
  if type(command) ~= "function" then
    say("Could not restore LayerSwap Host; turn it on manually.")
    return
  end
  changingHost = true
  local ok, err = pcall(command, "on")
  changingHost = false
  if not ok or LayerSwapDB.hosting ~= true then
    say("Could not restore LayerSwap Host; turn it on manually." .. (not ok and (" " .. tostring(err)) or ""))
    return
  end
  say("LayerSwap Host is on again.")
end

local function leaveAfterTransfer(s)
  if s.leaveScheduled or s.leaveRequested then return end
  s.leaveScheduled = true
  local now = GetTime()
  local left = s.joinedAt + 4 - now
  local wait = left > 0 and left or 4
  C_Timer.After(wait, function()
    s.leaveScheduled = false
    if swapGroup ~= s or not IsInGroup() then return end
    local border = s.borderAt and s.borderAt >= s.joinedAt - 1 and s.borderAt <= s.transferAt + 1
    if border or zoneInfo() ~= s.zone or groupLeader() ~= s.name then
      showMessage("Could not verify the host and transfer; leave the group manually.")
      return
    end
    local leave = (C_PartyInfo and C_PartyInfo.LeaveParty) or LeaveParty
    if type(leave) ~= "function" then
      showMessage("Automatic group leaving is unavailable; leave manually.")
      return
    end
    s.leaveRequested = true
    local ok, err = pcall(leave)
    if not ok then
      showMessage("Could not leave the group; leave manually.")
      say("Leaving the group failed: " .. tostring(err))
      return
    end
    showMessage("Layer transfer detected; leaving the host's group.")
    C_Timer.After(3, function()
      if swapGroup == s and IsInGroup() then
        showMessage("The game did not leave the group; leave manually.")
      end
    end)
  end)
end

local function restoreWho()
  if not C_FriendList or type(C_FriendList.SetWhoToUi) ~= "function" then return end
  for _, name in ipairs({ "LFGWhoListFrame", "WhoFrame" }) do
    local f = _G[name]
    if f and type(f.IsVisible) == "function" then
      local ok, visible = pcall(f.IsVisible, f)
      if not ok or secret(visible) then say("Could not check the player-search window."); return end
      if visible then return end
    end
  end
  local ok, err = pcall(C_FriendList.SetWhoToUi, false)
  if not ok then say("Could not restore player-search routing: " .. tostring(err)) end
end

local function hushWho(p)
  for _, name in ipairs({ "LFGWhoListFrame", "FriendsFrame" }) do
    local f = _G[name]
    if f and type(f.IsEventRegistered) == "function" and type(f.IsVisible) == "function"
        and type(f.UnregisterEvent) == "function" and type(f.RegisterEvent) == "function" then
      local okRegistered, registered = pcall(f.IsEventRegistered, f, "WHO_LIST_UPDATE")
      local okVisible, visible = pcall(f.IsVisible, f)
      if not okRegistered or not okVisible or secret(registered) or secret(visible) then
        return false, "Cannot inspect " .. name
      end
      if registered and not visible then
        local ok, err = pcall(f.UnregisterEvent, f, "WHO_LIST_UPDATE")
        if not ok then return false, "Cannot suppress " .. name .. ": " .. tostring(err) end
        p.muted[#p.muted + 1] = f
      end
    end
  end
  return true
end

local function releaseSearch(keepWhoRouting)
  if not searchInFlight then return end
  local p = searchInFlight
  searchInFlight = nil
  for _, f in ipairs(p.muted) do
    local ok, err = pcall(f.RegisterEvent, f, "WHO_LIST_UPDATE")
    if not ok then say("Could not restore a player-search window: " .. tostring(err)) end
  end
  if not keepWhoRouting then restoreWho() end
end

local function sendBurst(p)
  if pending ~= p then return end
  local zone = zoneInfo()
  if zone ~= p.zone or IsInGroup() or LayerSwapDB.hosting ~= false then
    endRequest("Stopped: your zone, group or hosting state changed.")
    return
  end
  p.phase = "contacting_players"
  p.rounds = p.rounds + 1
  local sent = 0
  while #p.queue > 0 and sent < WHISPERS_PER_TICK do
    local name = p.queue[1]
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, p.line, "WHISPER", name)
    if ok and not secret(result) and result == 3 then break end
    table.remove(p.queue, 1)
    if not ok or secret(result) or result ~= 0 then
      endRequest("The client refused an addon whisper. The request has been stopped to avoid spamming the chat system.")
      say("Check that addon communication is available and try again later.")
      return
    end
    LayerSwapWhileDeadDB.asked[name] = time()
    p.contacted[shortName(name)] = true
    p.sent = p.sent + 1
    sent = sent + 1
  end
  if #p.queue > 0 and p.rounds < MAX_SEND_TICKS then
    showMessage("Contacting eligible players (" .. p.sent .. " reached).", true)
    C_Timer.After(1, function() sendBurst(p) end)
  elseif #p.queue > 0 then
    endRequest("The client is rate-limiting addon messages. Wait a little before trying again.")
  else
    p.phase = "waiting_for_invite"
    showMessage("Request sent to " .. p.sent .. " players. Waiting for a LayerSwap invite.")
    C_Timer.After(60, function()
      if pending == p then endRequest("No invite arrived before the request expired. You can try again.") end
    end)
  end
end

local function searchResults()
  local p = searchInFlight
  if not p then return end
  releaseSearch()
  if pending ~= p then return end
  if zoneInfo() ~= p.zone or IsInGroup() then
    endRequest("Request cancelled because your zone or group status changed.")
    return
  end
  local ok, count = pcall(C_FriendList.GetNumWhoResults)
  if not ok or secret(count) or type(count) ~= "number" then
    endRequest("The player search returned unreadable results.")
    return
  end
  local me = shortName(UnitName("player"))
  if not me then endRequest("Your character name is unreadable."); return end
  local now, seen = time(), {}
  for name, at in pairs(LayerSwapWhileDeadDB.asked) do
    if type(at) ~= "number" or now - at >= PLAYER_RETRY_MEMORY then LayerSwapWhileDeadDB.asked[name] = nil end
  end
  for i = 1, math.min(count, 49) do
    local got, info = pcall(C_FriendList.GetWhoInfo, i)
    if not got then
      endRequest("The player search returned an unreadable entry. No further requests were sent.")
      say("Player search result failed: " .. tostring(info))
      return
    end
    local name = type(info) == "table" and not secret(info) and info.fullName or nil
    local short = shortName(name)
    if short and short ~= me and not seen[short] and not LayerSwapWhileDeadDB.asked[name] then
      seen[short] = true
      p.queue[#p.queue + 1] = name
    end
  end
  if #p.queue == 0 then
    endRequest("No eligible players appeared in the current zone search. You can retry after the player list refreshes.")
    return
  end
  sendBurst(p)
end

local function startRequest()
  if pending then endRequest("Request cancelled. Any invite already sent by another player may still arrive."); return end
  if candidate then
    candidate = nil
    showMessage("Invite tracking cleared. This does not cancel an invite already sent by the game.")
    updateButton()
    return
  end
  if not ready then showMessage("The requester could not initialize. See chat."); return end
  local isDead = type(UnitIsDeadOrGhost) == "function" and UnitIsDeadOrGhost("player")
  local inCombat = type(UnitAffectingCombat) == "function" and UnitAffectingCombat("player")
  if not isDead and not (LayerSwapWhileDeadDB and LayerSwapWhileDeadDB.allowInCombat and inCombat) then
    if inCombat then
      showMessage("Combat swapping is off. Enable it in /lswd settings if you want to request a swap now.")
    else
      showMessage("You are alive and out of combat. Use LayerSwap’s normal swap controls.")
    end
    return
  end
  local toc = select(4, GetBuildInfo())
  if type(toc) ~= "number" or toc < 16000 or toc >= 20000 then
    showMessage("This requester supports WoW Forever only.")
    return
  end
  local now = GetTime()
  if type(LayerSwapDB) ~= "table" then
    showMessage("LayerSwap's settings are unavailable.")
    return
  end
  if IsInGroup() then showMessage("Leave your group before requesting a swap."); return end
  if IsInInstance() then showMessage("Requests work in the open world, not an instance."); return end
  if type(UnitOnTaxi) == "function" and UnitOnTaxi("player") then showMessage("Land before requesting a swap."); return end
  if searchInFlight or (lastOtherSearch and now - lastOtherSearch < EXTERNAL_SEARCH_QUIET) then
    showMessage("The player list is in use or was searched recently. Wait for the search window to clear.")
    return
  end
  if now - lastWhoSearch < WHO_RETRY_INTERVAL then
    showMessage("Please wait a few seconds before starting another player search.")
    return
  end
  local zone, zoneName = zoneInfo()
  if not zone then showMessage("Your zone is unavailable."); return end
  if layerZone ~= zone then layer = nil end
  if not layer then scanLayer() end
  if not layer or layerZone ~= zone then
    showMessage("Target or mouse over a nearby NPC to read your layer.")
    return
  end
  local pos = position(zone)
  local line = "inv layer <LS " .. zone .. " not " .. layer .. " r3" .. (pos and (" " .. pos) or "") .. ">"
  local p = { phase = "searching", zone = zone, line = line, queue = {}, contacted = {}, heard = {}, muted = {}, sent = 0, rounds = 0 }
  local tag = plainString(WHO_TAG_ZONE) and WHO_TAG_ZONE or "z-"
  local query = tag .. '"' .. zoneName .. '"'
  local class = round > 0 and CLASSES[round] or nil
  round = (round + 1) % (#CLASSES + 1)
  local filters = { classIDs = class and { class } or {}, raceIDs = {}, uiMapIDs = { zone } }
  local origin = (Enum and Enum.SocialWhoOrigin and Enum.SocialWhoOrigin.Social) or 1
  pending, searchInFlight = p, p
  local quiet, why = hushWho(p)
  if not quiet then
    releaseSearch(true)
    endRequest("Could not suppress the player-search window. See chat.")
    say(why)
    return
  end
  if LayerSwapDB.hosting ~= false then
    local command = SlashCmdList and SlashCmdList.LAYERSWAP
    if type(command) ~= "function" then
      releaseSearch(true)
      endRequest("Could not turn LayerSwap Host off.")
      return
    end
    changingHost = true
    local ok, err = pcall(command, "off")
    changingHost = false
    if not ok or LayerSwapDB.hosting ~= false then
      releaseSearch(true)
      endRequest("Could not turn LayerSwap Host off.")
      if not ok then say("LayerSwap Host command failed: " .. tostring(err)) end
      return
    end
    if hostTracking then
      hostOwner = p
      say("LayerSwap Host is off until the swap group is left.")
    else
      say("LayerSwap Host is off; turn it on again manually.")
    end
  elseif hostOwner then
    hostOwner = p
  end
  if type(C_FriendList.SetWhoToUi) == "function" then
    local ok, err = pcall(C_FriendList.SetWhoToUi, true)
    if not ok then
      releaseSearch(true)
      endRequest("Could not route the player search. See chat.")
      say("Player-search routing failed: " .. tostring(err))
      return
    end
  end
  ownSearch = true
  local ok, err = pcall(C_FriendList.SendWho, query, origin, filters)
  if not ok then ok, err = pcall(C_FriendList.SendWho, query, origin) end
  ownSearch = false
  if not ok then
    releaseSearch()
    endRequest("Player search failed. See chat.")
    say("Player search failed: " .. tostring(err))
    return
  end
  lastWhoSearch = now
  showMessage("Looking for LayerSwap-capable players in this zone...")
  updateButton()
  C_Timer.After(SEARCH_TIMEOUT, function()
    if searchInFlight == p then
      releaseSearch()
      lastOtherSearch = GetTime()
      if pending == p then endRequest("Player search timed out. Try again.") end
    end
  end)
end

local function attachLauncher()
  local base = _G.LayerSwapPanel
  if not launcher and base then
    launcher = CreateFrame("Button", nil, base, "UIPanelButtonTemplate")
    launcher:SetSize(130, 20)
    launcher:SetPoint("TOPRIGHT", base, "BOTTOMRIGHT", 0, -2)
    launcher:SetScript("OnClick", startRequest)
    updateButton()
  end
  local mini = _G.LayerSwapMini
  if not miniLauncher and mini then
    miniLauncher = CreateFrame("Button", nil, mini, "UIPanelButtonTemplate")
    miniLauncher:SetSize(22, 22)
    updateMiniPosition()
    miniIcon = miniLauncher:CreateTexture(nil, "ARTWORK")
    miniIcon:SetPoint("TOPLEFT", miniLauncher, "TOPLEFT", 3, -3)
    miniIcon:SetPoint("BOTTOMRIGHT", miniLauncher, "BOTTOMRIGHT", -3, 3)
    -- WoW texture file ID for Shaman's Astral Call icon.
    miniIcon:SetTexture(136010)
    miniLauncher:SetScript("OnClick", startRequest)
    miniLauncher:SetScript("OnEnter", function(self)
      if not GameTooltip then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(pending and (pending.phase == "searching" and "Cancel search" or pending.phase == "waiting_for_invite" and "Stop waiting" or "Cancel requests") or (candidate and "Clear invite" or swapButtonLabel()))
      GameTooltip:Show()
    end)
    miniLauncher:SetScript("OnLeave", function()
      if GameTooltip then GameTooltip:Hide() end
    end)
    updateButton()
  end
end

for _, event in ipairs({ "ADDON_LOADED", "WHO_LIST_UPDATE",
    "CHAT_MSG_ADDON", "PARTY_INVITE_REQUEST", "GROUP_JOINED", "GROUP_LEFT", "ZONE_CHANGED_NEW_AREA", "SHARD_TRANSFER",
    "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED" }) do
  frame:RegisterEvent(event)
end

frame:SetScript("OnEvent", function(_, event, arg, text, channel, sender)
  if hostOwner and type(LayerSwapDB) == "table" and LayerSwapDB.hosting ~= false then hostOwner = nil end

  if event == "ADDON_LOADED" and arg == ADDON then
    LayerSwapWhileDeadDB = type(LayerSwapWhileDeadDB) == "table" and LayerSwapWhileDeadDB or {}
    if type(LayerSwapWhileDeadDB.asked) ~= "table" then LayerSwapWhileDeadDB.asked = {} end
    if type(LayerSwapWhileDeadDB.allowInCombat) ~= "boolean" then LayerSwapWhileDeadDB.allowInCombat = false end
    if LayerSwapWhileDeadDB.miniPosition ~= "Top" and LayerSwapWhileDeadDB.miniPosition ~= "Left"
        and LayerSwapWhileDeadDB.miniPosition ~= "Right" and LayerSwapWhileDeadDB.miniPosition ~= "Bottom" then
      LayerSwapWhileDeadDB.miniPosition = "Right"
    end
    setupOptions()
    if not (C_FriendList and type(C_FriendList.SendWho) == "function"
        and type(C_FriendList.GetNumWhoResults) == "function" and type(C_FriendList.GetWhoInfo) == "function"
        and C_ChatInfo and type(C_ChatInfo.SendAddonMessage) == "function" and type(hooksecurefunc) == "function") then
      say("Required player-search or addon-message APIs are unavailable.")
      return
    end
    local ok, err = pcall(hooksecurefunc, C_FriendList, "SendWho", function()
      if ownSearch then return end
      lastOtherSearch = GetTime()
      if searchInFlight then
        releaseSearch(true)
        endRequest("Another player search interrupted this request.")
      end
    end)
    if not ok then say("Cannot monitor player searches: " .. tostring(err)); return end
    if type(SlashCmdList.LAYERSWAP) == "function" then
      hostTracking = pcall(hooksecurefunc, SlashCmdList, "LAYERSWAP", function(msg)
        if changingHost or not plainString(msg) then return end
        local command = string.lower(msg):match("^%s*(.-)%s*$")
        if command == "host" or command == "on" or command == "off" then hostOwner = nil end
      end)
    end
    ready = true
    updateButton()

  elseif event == "WHO_LIST_UPDATE" then
    searchResults()

  elseif event == "CHAT_MSG_ADDON" then
    local p = pending or (candidate and candidate.request) or (swapGroup and swapGroup.request)
    if not p or secret(arg) or arg ~= PREFIX or secret(channel) or channel ~= "WHISPER"
        or not plainString(text) then return end
    local name = shortName(sender)
    if not name or not p.contacted[name] or p.heard[name] then return end
    local target, _, zone, host = text:match("^heard (.-)|([^|]*)|([^|]*)|([^|]*)$")
    local me = shortName(UnitName("player"))
    if me and shortName(target) == me and zone == tostring(p.zone) and host == "h" then
      p.heard[name] = true
      if pending == p then
        p.phase = "host_responded"
        showMessage("A LayerSwap host has acknowledged the request. Waiting for its invite.", p.heardNotified)
        p.heardNotified = true
      end
    end

  elseif event == "PARTY_INVITE_REQUEST" then
    local name = shortName(arg)
    if pending and name and pending.contacted[name] then
      local c = { phase = "invite_received", request = pending, name = name, at = GetTime(), zone = pending.zone }
      candidate = c
      endRequest("Invite received. Accept it to swap.")
      C_Timer.After(60, function()
        if candidate == c then
          candidate = nil
          showMessage("Invite tracking expired. If you accepted the invite, leave the group manually if needed.")
          updateButton()
        end
      end)
    elseif candidate and name ~= candidate.name then
      candidate = nil
      updateButton()
    end

  elseif event == "GROUP_JOINED" then
    if candidate and IsInGroup() and GetTime() - candidate.at <= 60 and zoneInfo() == candidate.zone then
      local s = candidate
      candidate, swapGroup = nil, s
      s.phase = "group_joined"
      s.joinedAt = GetTime()
      showMessage("You joined the request host. Waiting for LayerSwap to confirm the transfer.")
      updateButton()
      C_Timer.After(60, function()
        if swapGroup == s and not s.transferAt then
          s.expired = true
          s.phase = "transfer_unconfirmed"
          showMessage("No layer change was detected. Leave the group manually if the swap did not happen.")
        end
      end)
    else
      candidate = nil
      if pending then endRequest("Group joined. Leave it manually when ready.") else updateButton() end
    end

  elseif event == "GROUP_LEFT" then
    if swapGroup then
      local s = swapGroup
      swapGroup = nil
      s.phase = "finished"
      C_Timer.After(0, function() restoreHosting(s.request) end)
    end

  elseif event == "ZONE_CHANGED_NEW_AREA" then
    invalidateLayer()
    if swapGroup then swapGroup.borderAt = GetTime() end
    if candidate then candidate = nil; updateButton() end
    if pending then endRequest("Stopped: your zone or layer changed.") end

  elseif event == "SHARD_TRANSFER" then
    invalidateLayer()
    if swapGroup and not swapGroup.transferAt and not swapGroup.expired and IsInGroup() then
      swapGroup.transferAt = GetTime()
      swapGroup.phase = "transfer_detected"
      leaveAfterTransfer(swapGroup)
    elseif candidate then
      candidate = nil
      updateButton()
    end
    if pending then endRequest("Stopped: your zone or layer changed.") end

  elseif event == "PLAYER_TARGET_CHANGED" then
    observe("target")

  elseif event == "UPDATE_MOUSEOVER_UNIT" then
    observe("mouseover")

  elseif event == "NAME_PLATE_UNIT_ADDED" and plainString(arg) then
    observe(arg)
  end
end)

local elapsed = 0
frame:SetScript("OnUpdate", function(_, dt)
  if hostOwner and type(LayerSwapDB) == "table" and LayerSwapDB.hosting ~= false then hostOwner = nil end
  elapsed = elapsed + dt
  if elapsed < 1 then return end
  elapsed = 0
  attachLauncher()
end)
