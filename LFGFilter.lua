----------------------------------------------------------------------
-- LFG Filter v1.1 - TBC Anniversary Looking For Group Browser Filter
-- Two filter modes:
--   "Find Players" - Shows solo players matching class/role/level filters
--   "Find Groups"  - Shows groups with available role slots
-- Auto-refresh removes stale/delisted entries every 10 seconds.
-- Filters auto-apply on toggle. Preferences saved between sessions.
-- Supports ElvUI and TukUI skinning when available.
----------------------------------------------------------------------

local addonName, ns = ...

LFGFilterDB = LFGFilterDB or {}

local pairs, ipairs = pairs, ipairs
local strlower = string.lower
local format = string.format

local MAX_LEVEL = 70

----------------------------------------------------------------------
-- CLASS INFO
----------------------------------------------------------------------
local CLASS_ICON_TEXTURE = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"

local CLASS_INFO = {
    { name = "Warrior",  id = 1,  color = "C79C6E", file = "WARRIOR",  tcoords = { 0,       0.25,     0,    0.25   } },
    { name = "Paladin",  id = 2,  color = "F58CBA", file = "PALADIN",  tcoords = { 0,       0.25,     0.5,  0.75   } },
    { name = "Hunter",   id = 3,  color = "ABD473", file = "HUNTER",   tcoords = { 0,       0.25,     0.25, 0.5    } },
    { name = "Rogue",    id = 4,  color = "FFF569", file = "ROGUE",    tcoords = { 0.49609, 0.74219,  0,    0.25   } },
    { name = "Priest",   id = 5,  color = "FFFFFF", file = "PRIEST",   tcoords = { 0.49609, 0.74219,  0.25, 0.5    } },
    { name = "Shaman",   id = 7,  color = "0070DE", file = "SHAMAN",   tcoords = { 0.25,    0.49609,  0.25, 0.5    } },
    { name = "Mage",     id = 8,  color = "69CCF0", file = "MAGE",     tcoords = { 0.25,    0.49609,  0,    0.25   } },
    { name = "Warlock",  id = 9,  color = "9482C9", file = "WARLOCK",  tcoords = { 0.74219, 0.98828,  0.25, 0.5    } },
    { name = "Druid",    id = 11, color = "FF7D0A", file = "DRUID",    tcoords = { 0.74219, 0.98828,  0,    0.25   } },
}

local ROLE_ICON_TEXTURE = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"

local ROLE_ICON_TCOORDS = {
    tank   = { 0,       0.296875, 0.34375, 0.640625 },
    healer = { 0.296875, 0.59375,  0,       0.296875 },
    dps    = { 0.296875, 0.59375,  0.34375, 0.640625 },
}

-- Remaining slot keys from GetSearchResultMemberCounts
local ROLE_REMAINING_MAP = {
    tank   = "TANK_REMAINING",
    healer = "HEALER_REMAINING",
    dps    = "DAMAGER_REMAINING",
}

----------------------------------------------------------------------
-- STATE
----------------------------------------------------------------------
local filterPanel
local resultCountText
local totalResultCount = 0

local lfgParent
local lfgBrowseFrame
local lfgScrollBox

-- Find Players state
local playerRoleButtons = {}
local classButtons = {}
local activePlayerRoles = {}
local activeClasses = {}

-- Find Groups state
local groupRoleButtons = {}
local activeGroupRoles = {}

-- Max level filter state
local maxLevelButton
local activeMaxLevel = false

-- Auto-refresh state
local AUTO_REFRESH_INTERVAL = 10  -- seconds
local autoRefreshElapsed = 0
local isApplyingFilters = false

-- Track all skinnable frames for ElvUI/TukUI
local skinnableButtons = {}
local skinnableCloseBtn = nil

----------------------------------------------------------------------
-- UTILITY
----------------------------------------------------------------------
local function AnyPlayerFilterActive()
    if activeMaxLevel then return true end
    for _, v in pairs(activePlayerRoles) do if v then return true end end
    for _, v in pairs(activeClasses) do if v then return true end end
    return false
end

local function AnyGroupFilterActive()
    for _, v in pairs(activeGroupRoles) do if v then return true end end
    return false
end

local function AnyFilterActive()
    return AnyPlayerFilterActive() or AnyGroupFilterActive()
end

local function PlayerIsInGroup()
    if _G.GetNumGroupMembers then
        return _G.GetNumGroupMembers() > 0
    end
    return false
end

local function HexColor(hex)
    return tonumber(hex:sub(1, 2), 16) / 255,
           tonumber(hex:sub(3, 4), 16) / 255,
           tonumber(hex:sub(5, 6), 16) / 255
end

----------------------------------------------------------------------
-- SAVED VARIABLES: Save/restore filter state
----------------------------------------------------------------------
local function SaveFilterState()
    LFGFilterDB.playerRoles = {}
    for k, v in pairs(activePlayerRoles) do
        if v then LFGFilterDB.playerRoles[k] = true end
    end

    LFGFilterDB.classes = {}
    for k, v in pairs(activeClasses) do
        if v then LFGFilterDB.classes[k] = true end
    end

    LFGFilterDB.groupRoles = {}
    for k, v in pairs(activeGroupRoles) do
        if v then LFGFilterDB.groupRoles[k] = true end
    end

    LFGFilterDB.maxLevel = activeMaxLevel or nil
end

local function RestoreFilterState()
    if not LFGFilterDB then return end

    if LFGFilterDB.playerRoles then
        for k, v in pairs(LFGFilterDB.playerRoles) do
            activePlayerRoles[k] = v
            if playerRoleButtons[k] then
                playerRoleButtons[k].isActive = v
                playerRoleButtons[k]:UpdateVisual()
            end
        end
    end

    if LFGFilterDB.classes then
        for k, v in pairs(LFGFilterDB.classes) do
            activeClasses[k] = v
            if classButtons[k] then
                classButtons[k].isActive = v
                classButtons[k]:UpdateVisual()
            end
        end
    end

    if LFGFilterDB.groupRoles then
        for k, v in pairs(LFGFilterDB.groupRoles) do
            activeGroupRoles[k] = v
            if groupRoleButtons[k] then
                groupRoleButtons[k].isActive = v
                groupRoleButtons[k]:UpdateVisual()
            end
        end
    end

    if LFGFilterDB.maxLevel then
        activeMaxLevel = true
        if maxLevelButton then
            maxLevelButton.isActive = true
            maxLevelButton:UpdateVisual()
        end
    end
end

----------------------------------------------------------------------
-- Clear one mode's filters (used when switching modes)
----------------------------------------------------------------------
local function ClearPlayerFilters()
    for role, btn in pairs(playerRoleButtons) do
        btn.isActive = false
        activePlayerRoles[role] = false
        btn:UpdateVisual()
    end
    for classId, btn in pairs(classButtons) do
        btn.isActive = false
        activeClasses[classId] = false
        btn:UpdateVisual()
    end
    activeMaxLevel = false
    if maxLevelButton then
        maxLevelButton.isActive = false
        maxLevelButton:UpdateVisual()
    end
end

local function ClearGroupFilters()
    for role, btn in pairs(groupRoleButtons) do
        btn.isActive = false
        activeGroupRoles[role] = false
        btn:UpdateVisual()
    end
end

----------------------------------------------------------------------
-- CORE: Check if entry passes max level filter
----------------------------------------------------------------------
local function EntryPassesMaxLevel(entry, info)
    if not activeMaxLevel then return true end
    local rid = entry.resultID
    if not rid then return false end
    if info then
        local reqLevel = info.requiredLvl or info.requiredLevel or 0
        if reqLevel >= MAX_LEVEL then return true end
    end
    -- If no level requirement is set, check leader level
    if C_LFGList and C_LFGList.GetSearchResultLeaderInfo then
        local ok, leaderInfo = pcall(C_LFGList.GetSearchResultLeaderInfo, rid)
        if ok and type(leaderInfo) == "table" then
            local leaderLevel = leaderInfo.level or 0
            if leaderLevel >= MAX_LEVEL then return true end
        end
    end
    return false
end

----------------------------------------------------------------------
-- CORE: Check if entry passes "Find Players" filters.
----------------------------------------------------------------------
local function EntryPassesFindPlayers(entry, counts, info)
    if not counts then return false end

    local numMembers = info and info.numMembers or 0
    if numMembers ~= 1 then return false end

    -- Check role filter using lfgRoles from LeaderInfo
    local hasRole = false
    for _, v in pairs(activePlayerRoles) do if v then hasRole = true; break end end

    if hasRole then
        local rolePass = false
        local rid = entry.resultID
        if rid and C_LFGList and C_LFGList.GetSearchResultLeaderInfo then
            local ok, leaderInfo = pcall(C_LFGList.GetSearchResultLeaderInfo, rid)
            if ok and type(leaderInfo) == "table" and leaderInfo.lfgRoles then
                local lfgRoles = leaderInfo.lfgRoles
                for roleKey, isActive in pairs(activePlayerRoles) do
                    if isActive and lfgRoles[roleKey] then
                        rolePass = true
                        break
                    end
                end
            end
        end
        if not rolePass then return false end
    end

    -- Check class filter
    local hasClass = false
    for _, v in pairs(activeClasses) do if v then hasClass = true; break end end

    if hasClass then
        local classPass = false
        for classId, isActive in pairs(activeClasses) do
            if isActive then
                for _, cinfo in ipairs(CLASS_INFO) do
                    if cinfo.id == classId then
                        if counts[cinfo.file] and counts[cinfo.file] > 0 then
                            classPass = true
                            break
                        end
                    end
                end
                if classPass then break end
            end
        end
        if not classPass then return false end
    end

    return true
end

----------------------------------------------------------------------
-- CORE: Check if entry passes "Find Groups" filters.
----------------------------------------------------------------------
local function EntryPassesFindGroups(entry, counts, info)
    if not counts then return false end

    local numMembers = info and info.numMembers or 0
    if numMembers < 2 then return false end

    local rolePass = false
    for roleKey, isActive in pairs(activeGroupRoles) do
        if isActive then
            local remainKey = ROLE_REMAINING_MAP[roleKey]
            if remainKey and counts[remainKey] and counts[remainKey] > 0 then
                rolePass = true
                break
            end
        end
    end

    return rolePass
end

----------------------------------------------------------------------
-- CORE: Apply filters
----------------------------------------------------------------------
local function ResetAutoRefreshTimer()
    autoRefreshElapsed = 0
end

-- ApplyFilters: re-filters the current DataProvider without triggering a refresh.
-- Use this when data has already been updated (hooks, events, server results).
local function ApplyFilters()
    if not lfgBrowseFrame or not lfgBrowseFrame:IsShown() then return end
    if isApplyingFilters then return end
    isApplyingFilters = true

    if not lfgScrollBox then
        lfgScrollBox = _G["LFGBrowseFrameScrollBox"]
    end
    if not lfgScrollBox then
        isApplyingFilters = false
        return
    end

    SaveFilterState()

    if not AnyFilterActive() then
        if resultCountText then resultCountText:SetText("") end
        isApplyingFilters = false
        return
    end

    local dp = lfgScrollBox.GetDataProvider and lfgScrollBox:GetDataProvider()
    if not dp or not dp.Enumerate then
        isApplyingFilters = false
        return
    end

    local findPlayers = AnyPlayerFilterActive()
    local findGroups = AnyGroupFilterActive()

    local allEntries = {}
    local passingEntries = {}

    for idx, entry in dp:Enumerate() do
        table.insert(allEntries, entry)

        if type(entry) == "table" and entry.resultID then
            local rid = entry.resultID

            local info = nil
            if C_LFGList and C_LFGList.GetSearchResultInfo then
                local ok, result = pcall(C_LFGList.GetSearchResultInfo, rid)
                if ok and type(result) == "table" then info = result end
            end

            -- Skip stale/delisted entries
            local hasInfo = C_LFGList.HasSearchResultInfo and C_LFGList.HasSearchResultInfo(rid)
            if not info or not hasInfo then
                -- Entry no longer valid
            elseif info.isDelisted then
                -- Explicitly delisted
            else
                local counts = nil
                if C_LFGList and C_LFGList.GetSearchResultMemberCounts then
                    local ok, result = pcall(C_LFGList.GetSearchResultMemberCounts, rid)
                    if ok and type(result) == "table" then counts = result end
                end

                -- Max level filter (Find Players only)
                if activeMaxLevel and not EntryPassesMaxLevel(entry, info) then
                    -- Skip non-max-level entries
                elseif findPlayers then
                    if EntryPassesFindPlayers(entry, counts, info) then
                        table.insert(passingEntries, entry)
                    end
                elseif findGroups then
                    if EntryPassesFindGroups(entry, counts, info) then
                        table.insert(passingEntries, entry)
                    end
                end
            end
        end
    end

    totalResultCount = #allEntries

    local newDP = CreateDataProvider()
    if newDP then
        newDP:InsertTable(passingEntries)
        lfgScrollBox:SetDataProvider(newDP)
    end

    if resultCountText then
        if findPlayers then
            resultCountText:SetText(format("Showing %d players of %d listings", #passingEntries, totalResultCount))
        elseif findGroups then
            resultCountText:SetText(format("Showing %d groups of %d listings", #passingEntries, totalResultCount))
        else
            resultCountText:SetText(format("Showing %d of %d listings", #passingEntries, totalResultCount))
        end
    end

    isApplyingFilters = false
end

-- ApplyAndRefresh: refreshes the DataProvider from cached data, then filters.
-- Use this for manual filter toggles (instant feedback, no server call).
local function ApplyAndRefresh()
    ResetAutoRefreshTimer()
    if not lfgBrowseFrame or not lfgBrowseFrame:IsShown() then return end
    if isApplyingFilters then return end

    -- When in a group, skip UpdateResultList (causes "Searching..." freeze)
    -- but still re-filter the existing data
    if PlayerIsInGroup() then
        ApplyFilters()
        return
    end

    -- Refresh to get full unfiltered data from cache
    isApplyingFilters = true
    if lfgBrowseFrame.UpdateResultList then
        lfgBrowseFrame:UpdateResultList()
    elseif lfgBrowseFrame.UpdateResults then
        lfgBrowseFrame:UpdateResults()
    end
    isApplyingFilters = false

    -- Now filter the refreshed data
    ApplyFilters()
end



----------------------------------------------------------------------
-- UI HELPERS
----------------------------------------------------------------------
local function CreateSectionHeader(parent, text, yOffset)
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", 16, yOffset)
    header:SetText(text)
    header:SetTextColor(1, 0.82, 0)
    return header
end

local function CreateSeparator(parent, yOffset)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 12, yOffset)
    line:SetPoint("TOPRIGHT", -12, yOffset)
    line:SetColorTexture(0.6, 0.6, 0.6, 0.3)
    return line
end

local function CreateToggleButton(parent, text, width, height, colorHex, iconInfo)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, height)

    btn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets   = { left = 1, right = 1, top = 1, bottom = 1 },
    })

    local r, g, b = 1, 1, 1
    if colorHex then r, g, b = HexColor(colorHex) end

    local icon
    local iconSize = height - 4
    if iconInfo then
        icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(iconSize, iconSize)
        icon:SetPoint("LEFT", 4, 0)
        icon:SetTexture(iconInfo.texture)
        if iconInfo.tcoords then
            icon:SetTexCoord(unpack(iconInfo.tcoords))
        end
    end

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if icon then
        label:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    else
        label:SetPoint("CENTER", 0, 0)
    end
    label:SetText(text)
    btn.label = label
    btn.icon = icon
    btn.isActive = false

    local function UpdateVisual()
        if btn.isActive then
            btn:SetBackdropColor(r, g, b, 0.3)
            btn:SetBackdropBorderColor(r, g, b, 0.8)
            label:SetTextColor(r, g, b)
            if icon then icon:SetDesaturated(false); icon:SetAlpha(1.0) end
        else
            btn:SetBackdropColor(0.1, 0.1, 0.1, 0.6)
            btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5)
            label:SetTextColor(0.5, 0.5, 0.5)
            if icon then icon:SetDesaturated(true); icon:SetAlpha(0.5) end
        end
    end
    btn.UpdateVisual = UpdateVisual

    btn:SetScript("OnClick", function(self)
        self.isActive = not self.isActive
        UpdateVisual()
        if self.onToggle then self.onToggle(self.isActive) end
    end)
    btn:EnableMouse(true)

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(1, 1, 1, 0.6)
        if icon then icon:SetDesaturated(false); icon:SetAlpha(1.0) end
    end)
    btn:SetScript("OnLeave", function(self) UpdateVisual() end)

    UpdateVisual()

    table.insert(skinnableButtons, btn)

    return btn
end

----------------------------------------------------------------------
-- CLEAR ALL FILTERS
----------------------------------------------------------------------
local function ClearAllFilters()
    ClearPlayerFilters()
    ClearGroupFilters()
    totalResultCount = 0
    if resultCountText then resultCountText:SetText("") end

    SaveFilterState()

    if lfgBrowseFrame then
        if lfgBrowseFrame.UpdateResultList then
            lfgBrowseFrame:UpdateResultList()
        elseif lfgBrowseFrame.UpdateResults then
            lfgBrowseFrame:UpdateResults()
        end
    end
end

----------------------------------------------------------------------
-- ElvUI / TukUI SKINNING
----------------------------------------------------------------------
local function ApplyElvUISkin()
    local E = unpack(ElvUI)
    if not E then return end
    local S = E:GetModule("Skins", true)
    if not S then return end

    -- Skin the main panel
    if filterPanel.StripTextures then
        filterPanel:StripTextures()
    end
    if filterPanel.SetTemplate then
        filterPanel:SetTemplate("Transparent")
    end

    -- Skin the close button
    if skinnableCloseBtn and S.HandleCloseButton then
        S:HandleCloseButton(skinnableCloseBtn)
    end

    -- Skin the clear button
    for _, btn in ipairs(skinnableButtons) do
        if btn.isUIPanelButton and S.HandleButton then
            S:HandleButton(btn)
        end
    end
end

local function ApplyTukUISkin()
    local T = unpack(Tukui)
    if not T then return end

    -- Skin the main panel
    if filterPanel.StripTextures then
        filterPanel:StripTextures()
    end
    if filterPanel.SetTemplate then
        filterPanel:SetTemplate("Transparent")
    end

    -- Skin the close button
    if skinnableCloseBtn and skinnableCloseBtn.SkinCloseButton then
        skinnableCloseBtn:SkinCloseButton()
    end
end

local function TrySkinPanel()
    if not filterPanel then return end

    -- Try ElvUI first
    if ElvUI then
        local ok, err = pcall(ApplyElvUISkin)
        if ok then return end
    end

    -- Try TukUI
    if Tukui then
        pcall(ApplyTukUISkin)
    end
end

----------------------------------------------------------------------
-- UI: Build the side panel
----------------------------------------------------------------------
local function CreateFilterPanel()
    if not lfgParent then return false end

    local PANEL_WIDTH = 260
    local PADDING = 14
    local INNER_WIDTH = PANEL_WIDTH - PADDING * 2

    -- Use standard Blizzard framing for a native WoW look
    -- Height will be set after layout is complete
    filterPanel = CreateFrame("Frame", "LFGFilterPanel", lfgParent, "BackdropTemplate")
    filterPanel:SetWidth(PANEL_WIDTH)
    filterPanel:SetPoint("TOPLEFT", lfgParent, "TOPRIGHT", -2, 0)
    filterPanel:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true, tileSize = 32, edgeSize = 32,
        insets   = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    filterPanel:SetBackdropColor(0.09, 0.09, 0.09, 0.95)
    filterPanel:SetFrameStrata("DIALOG")

    -- Title bar texture (Blizzard-style header)
    local titleBg = filterPanel:CreateTexture(nil, "ARTWORK")
    titleBg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    titleBg:SetSize(200, 64)
    titleBg:SetPoint("TOP", 0, 12)

    -- Only show filter panel when the Browse tab is active, not Create Listing
    lfgBrowseFrame:HookScript("OnShow", function() filterPanel:Show() end)
    lfgBrowseFrame:HookScript("OnHide", function() filterPanel:Hide() end)
    lfgParent:HookScript("OnHide", function() filterPanel:Hide() end)
    if not lfgBrowseFrame:IsShown() then filterPanel:Hide() end

    local yPos = -8

    -- Close button (X) - standard Blizzard close button
    local closeBtn = CreateFrame("Button", nil, filterPanel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -6, -6)
    closeBtn:SetScript("OnClick", function() filterPanel:Hide() end)
    skinnableCloseBtn = closeBtn

    -- Title (sits inside the header texture with proper padding)
    local title = filterPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", titleBg, "TOP", 0, -14)
    title:SetText("LFG Filter")
    title:SetTextColor(1, 0.82, 0)
    yPos = yPos - 30

    -- Result count
    resultCountText = filterPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    resultCountText:SetPoint("TOP", 0, yPos)
    resultCountText:SetTextColor(0.7, 0.7, 0.7)
    yPos = yPos - 20

    CreateSeparator(filterPanel, yPos)
    yPos = yPos - 10

    ----------------------------------------------------------------
    -- SECTION 1: FIND PLAYERS (for group leaders)
    ----------------------------------------------------------------
    CreateSectionHeader(filterPanel, "Find Players", yPos)
    yPos = yPos - 16
    local fpDesc = filterPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fpDesc:SetPoint("TOPLEFT", 16, yPos)
    fpDesc:SetText("Show solo players matching class/role")
    fpDesc:SetTextColor(0.6, 0.6, 0.6)
    yPos = yPos - 16

    -- Role filters
    local roleLabel = filterPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    roleLabel:SetPoint("TOPLEFT", 16, yPos)
    roleLabel:SetText("Role:")
    roleLabel:SetTextColor(0.8, 0.8, 0.8)
    yPos = yPos - 18

    local roleData = {
        { key = "tank",   text = "Tank",   color = "5588DD" },
        { key = "healer", text = "Healer", color = "55DD55" },
        { key = "dps",    text = "DPS",    color = "DD5555" },
    }

    local ROLE_BTN_W = (INNER_WIDTH - 8) / 3
    local ROLE_BTN_H = 28
    for i, rd in ipairs(roleData) do
        local iconData = nil
        if ROLE_ICON_TCOORDS[rd.key] then
            iconData = { texture = ROLE_ICON_TEXTURE, tcoords = ROLE_ICON_TCOORDS[rd.key] }
        end
        local btn = CreateToggleButton(filterPanel, rd.text, ROLE_BTN_W, ROLE_BTN_H, rd.color, iconData)
        btn:SetPoint("TOPLEFT", PADDING + (i - 1) * (ROLE_BTN_W + 4), yPos)
        btn.onToggle = function(isActive)
            activePlayerRoles[rd.key] = isActive
            if isActive then ClearGroupFilters() end
            ApplyAndRefresh()
        end
        playerRoleButtons[rd.key] = btn
    end

    yPos = yPos - ROLE_BTN_H - 8

    -- Class filters
    local classLabel = filterPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    classLabel:SetPoint("TOPLEFT", 16, yPos)
    classLabel:SetText("Class:")
    classLabel:SetTextColor(0.8, 0.8, 0.8)
    yPos = yPos - 18

    local COLS = 2
    local COL_GAP = 6
    local CLASS_BTN_W = (INNER_WIDTH - COL_GAP) / COLS
    local CLASS_BTN_H = 24
    local CLASS_ROW_H = CLASS_BTN_H + 4

    for idx, cinfo in ipairs(CLASS_INFO) do
        local row = math.floor((idx - 1) / COLS)
        local col = (idx - 1) % COLS
        local xOff = PADDING + col * (CLASS_BTN_W + COL_GAP)
        local rowY = yPos - row * CLASS_ROW_H

        local iconData = { texture = CLASS_ICON_TEXTURE, tcoords = cinfo.tcoords }
        local btn = CreateToggleButton(filterPanel, cinfo.name, CLASS_BTN_W, CLASS_BTN_H, cinfo.color, iconData)
        btn:SetPoint("TOPLEFT", xOff, rowY)
        btn.onToggle = function(isActive)
            activeClasses[cinfo.id] = isActive
            if isActive then ClearGroupFilters() end
            ApplyAndRefresh()
        end
        classButtons[cinfo.id] = btn
    end

    local classRows = math.ceil(#CLASS_INFO / COLS)
    yPos = yPos - classRows * CLASS_ROW_H - 4

    -- Max level toggle (part of Find Players)
    local GROUP_BTN_H = 26
    maxLevelButton = CreateToggleButton(filterPanel, format("Max Level (%d) Only", MAX_LEVEL), INNER_WIDTH, GROUP_BTN_H, "FFD100", nil)
    maxLevelButton:SetPoint("TOPLEFT", PADDING, yPos)
    maxLevelButton.onToggle = function(isActive)
        activeMaxLevel = isActive
        if isActive then ClearGroupFilters() end
        ApplyAndRefresh()
    end
    yPos = yPos - GROUP_BTN_H - 4

    CreateSeparator(filterPanel, yPos)
    yPos = yPos - 10

    ----------------------------------------------------------------
    -- SECTION 2: FIND GROUPS (for solo players)
    ----------------------------------------------------------------
    CreateSectionHeader(filterPanel, "Find Groups", yPos)
    yPos = yPos - 16
    local fgDesc = filterPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fgDesc:SetPoint("TOPLEFT", 16, yPos)
    fgDesc:SetText("Show groups with open role slots")
    fgDesc:SetTextColor(0.6, 0.6, 0.6)
    yPos = yPos - 16

    local groupRoleData = {
        { key = "tank",   text = "Tank Needed",   color = "5588DD" },
        { key = "healer", text = "Healer Needed",  color = "55DD55" },
        { key = "dps",    text = "DPS Needed",     color = "DD5555" },
    }

    local GROUP_BTN_W = INNER_WIDTH
    for i, rd in ipairs(groupRoleData) do
        local iconData = nil
        if ROLE_ICON_TCOORDS[rd.key] then
            iconData = { texture = ROLE_ICON_TEXTURE, tcoords = ROLE_ICON_TCOORDS[rd.key] }
        end
        local btn = CreateToggleButton(filterPanel, rd.text, GROUP_BTN_W, GROUP_BTN_H, rd.color, iconData)
        btn:SetPoint("TOPLEFT", PADDING, yPos)
        btn.onToggle = function(isActive)
            activeGroupRoles[rd.key] = isActive
            if isActive then ClearPlayerFilters() end
            ApplyAndRefresh()
        end
        groupRoleButtons[rd.key] = btn
        yPos = yPos - GROUP_BTN_H - 4
    end

    yPos = yPos - 4
    CreateSeparator(filterPanel, yPos)
    yPos = yPos - 14

    ----------------------------------------------------------------
    -- CLEAR BUTTON
    ----------------------------------------------------------------
    local clearBtn = CreateFrame("Button", nil, filterPanel, "UIPanelButtonTemplate")
    clearBtn:SetSize(INNER_WIDTH, 28)
    clearBtn:SetPoint("TOPLEFT", PADDING, yPos)
    clearBtn:SetText("Clear Filters")
    clearBtn:SetScript("OnClick", ClearAllFilters)
    clearBtn.isUIPanelButton = true
    table.insert(skinnableButtons, clearBtn)

    -- Set panel height based on content
    local contentBottom = -yPos + 28 + 16  -- account for clear button height + bottom padding
    filterPanel:SetHeight(contentBottom)

    -- Auto-refresh every 10 seconds: re-filter cached data to remove delisted entries.
    -- New listings appear when the user clicks Refresh or when the server pushes updates
    -- (we listen for LFG_LIST_SEARCH_RESULTS_RECEIVED to re-apply filters automatically).
    filterPanel:SetScript("OnUpdate", function(self, elapsed)
        if not AnyFilterActive() then
            autoRefreshElapsed = 0
            return
        end
        autoRefreshElapsed = autoRefreshElapsed + elapsed
        if autoRefreshElapsed >= AUTO_REFRESH_INTERVAL then
            autoRefreshElapsed = 0
            if PlayerIsInGroup() then
                ApplyFilters()
            else
                ApplyAndRefresh()
            end
        end
    end)

    return true
end

----------------------------------------------------------------------
-- DEBUG
----------------------------------------------------------------------
local function DumpFrameInfo()
    print("|cff00ff00[LFG Filter]|r === Debug ===")

    lfgScrollBox = lfgScrollBox or _G["LFGBrowseFrameScrollBox"]
    if not lfgScrollBox then
        print("  ScrollBox: NOT FOUND")
        return
    end

    local dp = lfgScrollBox.GetDataProvider and lfgScrollBox:GetDataProvider()
    if not dp then
        print("  DataProvider: NOT FOUND")
        return
    end

    local size = dp.GetSize and dp:GetSize() or 0
    print(format("  DataProvider size: %d (total tracked: %d)", size, totalResultCount))

    if dp.Enumerate and size > 0 then
        local soloCount, groupCount = 0, 0
        local count = 0
        for idx, entry in dp:Enumerate() do
            if type(entry) == "table" and entry.resultID then
                local ok, info = pcall(C_LFGList.GetSearchResultInfo, entry.resultID)
                if ok and type(info) == "table" then
                    if info.numMembers == 1 then
                        soloCount = soloCount + 1
                    else
                        groupCount = groupCount + 1
                    end
                end

                count = count + 1
                if count <= 3 then
                    local ok2, counts = pcall(C_LFGList.GetSearchResultMemberCounts, entry.resultID)
                    if ok2 and type(counts) == "table" then
                        local parts = {}
                        for _, cinfo in ipairs(CLASS_INFO) do
                            local n = counts[cinfo.file] or 0
                            if n > 0 then table.insert(parts, format("%s=%d", cinfo.name, n)) end
                        end
                        local roleParts = {}
                        if (counts["TANK"] or 0) > 0 then table.insert(roleParts, "T=" .. counts["TANK"]) end
                        if (counts["HEALER"] or 0) > 0 then table.insert(roleParts, "H=" .. counts["HEALER"]) end
                        if (counts["DAMAGER"] or 0) > 0 then table.insert(roleParts, "D=" .. counts["DAMAGER"]) end

                        local nm = ok and type(info) == "table" and info.numMembers or "?"
                        print(format("  Entry %d (rid=%d, members=%s): %s | %s",
                            count, entry.resultID, tostring(nm),
                            table.concat(parts, ", "),
                            table.concat(roleParts, ", ")))
                    end
                end
            end
        end
        print(format("  Solo players: %d | Groups: %d", soloCount, groupCount))
    end

    -- Active filters
    print("  --- Active filters ---")
    local any = false
    for role, active in pairs(activePlayerRoles) do
        if active then print("    Find Players Role: " .. role); any = true end
    end
    for classId, active in pairs(activeClasses) do
        if active then
            for _, ci in ipairs(CLASS_INFO) do
                if ci.id == classId then print("    Find Players Class: " .. ci.name); any = true end
            end
        end
    end
    for role, active in pairs(activeGroupRoles) do
        if active then print("    Find Groups: " .. role .. " needed"); any = true end
    end
    if activeMaxLevel then print("    Max Level: " .. MAX_LEVEL); any = true end
    if not any then print("    (none)") end

    -- Frame status
    print("  --- Status ---")
    print(format("    Browse frame: %s", lfgBrowseFrame and "found" or "NOT FOUND"))
    print(format("    Auto-refresh: %s", AnyFilterActive() and "active" or "idle"))
end

----------------------------------------------------------------------
-- SLASH COMMANDS
----------------------------------------------------------------------
SLASH_LFGFILTER1 = "/lfgf"
SLASH_LFGFILTER2 = "/lfgfilter"
SlashCmdList["LFGFILTER"] = function(msg)
    msg = strlower(msg or "")
    if msg == "reset" then
        ClearAllFilters()
    elseif msg == "hide" then
        if filterPanel then filterPanel:Hide() end
    elseif msg == "show" then
        if filterPanel then filterPanel:Show() end
    elseif msg == "debug" then
        DumpFrameInfo()
    else
        print("|cff00ff00[LFG Filter]|r Commands:")
        print("  /lfgf show  - Show filter panel")
        print("  /lfgf hide  - Hide filter panel")
        print("  /lfgf reset - Reset all filters")
        print("  /lfgf debug - Dump debug info")
    end
end

----------------------------------------------------------------------
-- INITIALIZATION
----------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("LFG_UPDATE")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
initFrame:RegisterEvent("LFG_LIST_SEARCH_RESULT_UPDATED")

local initialized = false

initFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        LFGFilterDB = LFGFilterDB or {}
        print("|cff00ff00[LFG Filter]|r loaded. Type /lfgf for commands.")
    end

    -- Re-apply filters whenever new search results arrive (manual refresh, server push, etc.)
    if event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" or event == "LFG_LIST_SEARCH_RESULT_UPDATED" then
        if initialized and AnyFilterActive() and lfgBrowseFrame and lfgBrowseFrame:IsShown() then
            -- Let the native UI update first, then re-apply our filters
            C_Timer.After(0.1, function()
                ApplyAndRefresh()
            end)
        end
        return
    end

    if not initialized then
        lfgParent = _G["LFGParentFrame"]
        lfgBrowseFrame = _G["LFGBrowseFrame"]

        if lfgParent and lfgBrowseFrame then
            if CreateFilterPanel() then
                initialized = true
                RestoreFilterState()

                -- Hook native refresh so filters persist when WoW updates the list.
                -- Debounced to avoid racing with rapid dungeon filter clicks.
                local pendingFilterTimer = nil
                if lfgBrowseFrame.UpdateResultList then
                    hooksecurefunc(lfgBrowseFrame, "UpdateResultList", function()
                        if not isApplyingFilters and AnyFilterActive() and not PlayerIsInGroup() then
                            if pendingFilterTimer then pendingFilterTimer:Cancel() end
                            pendingFilterTimer = C_Timer.NewTimer(0.3, function()
                                pendingFilterTimer = nil
                                ApplyFilters()
                            end)
                        end
                    end)
                end

                -- Apply ElvUI/TukUI skin after a short delay to ensure UI addons are ready
                C_Timer.After(1, TrySkinPanel)
            end
        end
    end
end)
