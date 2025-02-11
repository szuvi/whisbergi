--[[
  WhisBergi.lua
  A Cataclysm Classic (or older) addon to whisper multiple friends
  whenever a chosen quest ID's objectives update.

  - /whisbergi to open the panel
  - Panel under Esc → Interface → AddOns → WhisBergi
]] ------------------------------
-- 1) SavedVariables Handling
------------------------------
local defaults = {
    questID = 12345, -- A default quest ID
    friends = {"YourFriendName"} -- Default friend list
}

------------------------------
-- 2) Local Variables
------------------------------
local previousObjectives = {} -- For detecting quest updates

-- A helper to find a quest’s log index by scanning quest log for the given questID.
-- In Cataclysm, the 8th return from GetQuestLogTitle(i) is the quest ID (which might be 0 if not available).
local function GetQuestLogIndexByID(questID)
    if not questID then
        return nil
    end
    local numEntries = GetNumQuestLogEntries()
    for i = 1, numEntries do
        local questTitle, _, _, isHeader, _, _, _, thisQuestID = GetQuestLogTitle(i)
        if (not isHeader) and thisQuestID == questID then
            return i
        end
    end
    return nil
end

------------------------------
-- 3) Main Config Panel
------------------------------
local WhisBergiOptionsPanel = CreateFrame("Frame", "WhisBergiOptionsPanel", UIParent)
WhisBergiOptionsPanel.name = "WhisBergi"

-- Title text
local title = WhisBergiOptionsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("WhisBergi Settings")

-- Quest ID label
local questIDLabel = WhisBergiOptionsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
questIDLabel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -30)
questIDLabel:SetText("Quest ID:")

-- Quest ID edit box
local questIDEditBox = CreateFrame("EditBox", "WhisBergiQuestIDEditBox", WhisBergiOptionsPanel, "InputBoxTemplate")
questIDEditBox:SetSize(100, 25)
questIDEditBox:SetPoint("LEFT", questIDLabel, "RIGHT", 10, 0)
questIDEditBox:SetAutoFocus(false)

-- This function will parse the contents of questIDEditBox and store in WhisBergiDB
local function SaveQuestIDFromEditBox()
    local newQuestID = tonumber(questIDEditBox:GetText())
    if newQuestID then
        WhisBergiDB.questID = newQuestID
    else
        -- If the user typed non-numeric, we can reset or ignore
        WhisBergiDB.questID = nil
    end
end

-- Attach an OnTextChanged script so changes are saved immediately
questIDEditBox:SetScript("OnTextChanged", function(self, userInput)
    if userInput then
        SaveQuestIDFromEditBox()
    end
end)

-- Friends label
local friendsLabel = WhisBergiOptionsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
friendsLabel:SetPoint("TOPLEFT", questIDLabel, "BOTTOMLEFT", 0, -40)
friendsLabel:SetText("Friends (comma-separated):")

-- Friends edit box
local friendsEditBox = CreateFrame("EditBox", "WhisBergiFriendsEditBox", WhisBergiOptionsPanel, "InputBoxTemplate")
friendsEditBox:SetSize(300, 25)
friendsEditBox:SetPoint("TOPLEFT", friendsLabel, "BOTTOMLEFT", 0, -8)
friendsEditBox:SetAutoFocus(false)

-- A helper function to parse the comma list and store in WhisBergiDB
local function SaveFriendsFromEditBox()
    local friendsText = friendsEditBox:GetText() or ""
    local friendsTable = {}
    for friend in string.gmatch(friendsText, "([^,]+)") do
        friend = strtrim(friend)
        if friend ~= "" then
            table.insert(friendsTable, friend)
        end
    end
    WhisBergiDB.friends = friendsTable
end

-- Attach OnTextChanged so changes to the friends list are saved immediately
friendsEditBox:SetScript("OnTextChanged", function(self, userInput)
    if userInput then
        SaveFriendsFromEditBox()
    end
end)

------------------------------
-- 3a) Panel Refresh
------------------------------
-- We’ll just refresh the text fields from WhisBergiDB any time the panel is shown.
WhisBergiOptionsPanel:SetScript("OnShow", function(self)
    if not WhisBergiDB then
        WhisBergiDB = {}
    end
    if WhisBergiDB.questID == nil then
        WhisBergiDB.questID = defaults.questID
    end
    if not WhisBergiDB.friends then
        WhisBergiDB.friends = {unpack(defaults.friends)}
    end

    -- Display the current questID
    questIDEditBox:SetText(tostring(WhisBergiDB.questID))

    -- Display the current friend list as a comma-separated string
    friendsEditBox:SetText(table.concat(WhisBergiDB.friends, ", "))
end)

------------------------------
-- 4) Settings Registration
------------------------------
local function Bergi_RegisterOptionsPanel()
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(WhisBergiOptionsPanel, "WhisBergi")
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(WhisBergiOptionsPanel)
    else
        print("|cffff0000[Bergi]|r: No Interface Options API found—no in-game config panel.")
    end
end

------------------------------
-- 5) Slash Command
------------------------------
SLASH_Bergi1 = "/whisbergi"
SlashCmdList["WhisBergi"] = function(msg)
    InterfaceOptionsFrame_OpenToCategory(WhisBergiOptionsPanel)
    InterfaceOptionsFrame_OpenToCategory(WhisBergiOptionsPanel)
end

------------------------------
-- 6) Quest-Tracking Logic
------------------------------
local function CheckQuestProgressUpdate()
    local questID = WhisBergiDB.questID
    if not questID then
        return
    end

    local questLogIndex = GetQuestLogIndexByID(questID)
    if not questLogIndex then
        return
    end

    local questTitle, _, _, isHeader = GetQuestLogTitle(questLogIndex)
    if not questTitle or isHeader then
        return
    end

    local numLeaderboards = GetNumQuestLeaderBoards(questLogIndex)
    if not numLeaderboards or numLeaderboards == 0 then
        return
    end

    local newObjectives = {}
    for i = 1, numLeaderboards do
        local leaderboardText, objectiveType, finished = GetQuestLogLeaderBoard(i, questLogIndex)
        newObjectives[i] = leaderboardText or ""
    end

    for i, newVal in ipairs(newObjectives) do
        if previousObjectives[i] ~= newVal then
            -- Something changed
            if WhisBergiDB.friends and #WhisBergiDB.friends > 0 then
                for _, friendName in ipairs(WhisBergiDB.friends) do
                    SendChatMessage(string.format("%s", newVal), "WHISPER", nil, friendName)
                end
            end
        end
    end

    previousObjectives = newObjectives
end

------------------------------
-- 7) Event Handling
------------------------------
local WhisBergiFrame = CreateFrame("Frame")
WhisBergiFrame:RegisterEvent("ADDON_LOADED")
WhisBergiFrame:RegisterEvent("VARIABLES_LOADED")
WhisBergiFrame:RegisterEvent("QUEST_LOG_UPDATE")

WhisBergiFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "WhisBergi" then
        if not WhisBergiDB then
            WhisBergiDB = {}
        end
        if WhisBergiDB.questID == nil then
            WhisBergiDB.questID = defaults.questID
        end
        if not WhisBergiDB.friends then
            WhisBergiDB.friends = {unpack(defaults.friends)}
        end

        Bergi_RegisterOptionsPanel()

    elseif event == "VARIABLES_LOADED" then
        if not IsAddOnLoaded("Blizzard_OptionsUI") then
            LoadAddOn("Blizzard_OptionsUI")
        end

    elseif event == "QUEST_LOG_UPDATE" then
        CheckQuestProgressUpdate()
    end
end)
