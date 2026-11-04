-------------------------------------------------------------------------------
-- Title: Mik's Scrolling Battle Text Loot
-- Author: Mikord
-------------------------------------------------------------------------------

-- Create module and set its name.
local module = {}
local moduleName = "Loot"
MikSBT[moduleName] = module


-------------------------------------------------------------------------------
-- Imports.
-------------------------------------------------------------------------------

-- Local references to various modules for faster access.
local MSBTProfiles = MikSBT.Profiles
local MSBTParser = MikSBT.Parser

-- Get local references to various functions for faster access.
local string_gsub = string.gsub
local string_format = string.format
local math_ceil = math.ceil
local table_insert = table.insert
local table_remove = table.remove
local GetItemInfo = GetItemInfo
local GetItemCount = GetItemCount
local GetTime = GetTime
local DisplayEvent = MikSBT.Animations.DisplayEvent


-------------------------------------------------------------------------------
-- Constants.
-------------------------------------------------------------------------------

-- Money strings.
local GOLD = string_gsub(GOLD_AMOUNT, "%%d ", "")
local SILVER = string_gsub(SILVER_AMOUNT, "%%d ", "")
local COPPER = string_gsub(COPPER_AMOUNT, "%%d ", "")

-- Localized name for item types.
local ITEM_TYPE_QUEST = select(12, GetAuctionItemClasses())

-- How long a loot alert waits for the bag count to change, in seconds.
local LOOT_COUNT_MAX_WAIT = 1


-------------------------------------------------------------------------------
-- Private variables.
-------------------------------------------------------------------------------

-- Color patterns for item qualities.
local qualityPatterns = {}

-- Loot alerts waiting for the bag count to catch up, oldest first.
local pendingLoot = {}

-- Runs the wait for pendingLoot.  Only shown while something is waiting.
local lootWaitFrame


-------------------------------------------------------------------------------
-- Event handlers.
-------------------------------------------------------------------------------

-- ****************************************************************************
-- Handles looted money.
-- ****************************************************************************
local function HandleMoney(parserEvent)
 -- Money gain.
 local moneyString = parserEvent.moneyString
 moneyString = string_gsub(moneyString, GOLD, "|cffffd700%1|r")
 moneyString = string_gsub(moneyString, SILVER, "|cff808080%1|r")
 moneyString = string_gsub(moneyString, COPPER, "|cffeda55f%1|r")
  
 -- Format the event and display it.
 local eventSettings = MSBTProfiles.currentProfile.events.NOTIFICATION_MONEY
 if (eventSettings and not eventSettings.disabled) then
  local message = eventSettings.message
  message = string_gsub(message, "%%e", moneyString)
  DisplayEvent(eventSettings, message)
 end
end


-- ****************************************************************************
-- Displays a loot alert with the number of the item now in the bags.
-- ****************************************************************************
local function ShowLootAlert(alert)
 -- Drop the alert if the mod was disabled while it waited.
 if (MSBTProfiles.IsModDisabled()) then return end

 -- The items were just looted, so the bags hold at least that many.  The count
 -- can read lower when it never changed, such as for a currency token.
 local numTotal = GetItemCount(alert.itemLink) or 0
 if (numTotal < alert.numLooted) then numTotal = alert.numLooted end

 local message = alert.eventSettings.message
 message = string_gsub(message, "%%e", alert.itemName)
 message = string_gsub(message, "%%a", alert.numLooted)
 message = string_gsub(message, "%%t", numTotal)
 DisplayEvent(alert.eventSettings, message, alert.itemTexture)
end


-- ****************************************************************************
-- Displays the waiting loot alerts whose count has settled.
--
-- The loot message and the bag change are separate packets, and which one comes
-- first depends on the server, so the count at the time of the message can't be
-- relied on.  The count has settled once it has gone up by the amount looted or
-- has dropped because something else took the items, such as a bank deposit.
-- When it does neither the update came first or the item isn't counted, so the
-- alert stops waiting.
-- ****************************************************************************
local function OnUpdateLootWait(this)
 local now = GetTime()
 local index = 1
 while (pendingLoot[index]) do
  local alert = pendingLoot[index]
  local numItems = GetItemCount(alert.itemLink) or 0
  if (numItems >= alert.numBefore + alert.numLooted or numItems < alert.numBefore or now >= alert.giveUpTime) then
   table_remove(pendingLoot, index)
   ShowLootAlert(alert)
  else
   index = index + 1
  end
 end

 if (#pendingLoot == 0) then this:Hide() end
end


-- ****************************************************************************
-- Handles looted items.
-- ****************************************************************************
local function HandleItems(parserEvent)
 -- Created items are buggy.  Ignore them.
 if (parserEvent.isCreate) then return end

 -- Get information about the looted item.
 local itemLink = parserEvent.itemLink
 local itemName, _, itemQuality, _, _, itemType, _, _, _, itemTexture = GetItemInfo(itemLink)
 if (not itemName) then return end

 -- Determine whether to show the event and ignore it if necessary.
 local currentProfile = MSBTProfiles.currentProfile
 local showEvent = true
 if (currentProfile.qualityExclusions[itemQuality]) then showEvent = false end
 if ((itemType == ITEM_TYPE_QUEST) and currentProfile.alwaysShowQuestItems) then showEvent = true end
 if (currentProfile.itemExclusions[itemName]) then showEvent = false end
 if (currentProfile.itemsAllowed[itemName]) then showEvent = true end
 if (not showEvent) then return end

 -- Format the item name according to its quality.
 local qualityColor = ITEM_QUALITY_COLORS[itemQuality]
 if (qualityPatterns[itemQuality]) then itemName = string_format(qualityPatterns[itemQuality], itemName) end

 -- Wait for the bag count to catch up before displaying the event.
 local eventSettings = MSBTProfiles.currentProfile.events.NOTIFICATION_LOOT
 if (eventSettings and not eventSettings.disabled) then
  table_insert(pendingLoot, {
   eventSettings = eventSettings,
   itemLink = itemLink,
   itemName = itemName,
   itemTexture = itemTexture,
   numLooted = tonumber(parserEvent.amount) or 1,
   numBefore = GetItemCount(itemLink) or 0,
   giveUpTime = GetTime() + LOOT_COUNT_MAX_WAIT,
  })
  lootWaitFrame:Show()
 end
end


-- ****************************************************************************
-- Parser events handler.
-- ****************************************************************************
local function ParserEventsHandler(parserEvent)
 -- Ignore the event if it isn't for the player or not a loot event.
 if (parserEvent.recipientUnit ~= "player" or parserEvent.eventType ~= "loot") then return end

 -- Call the correct handler for the loot type.
 if (parserEvent.isMoney) then HandleMoney(parserEvent) elseif (parserEvent.itemLink) then HandleItems(parserEvent) end
end


-------------------------------------------------------------------------------
-- Initialization.
-------------------------------------------------------------------------------

-- Setup the item quality color patterns.
for k, v in pairs(ITEM_QUALITY_COLORS) do
 qualityPatterns[k] = string_format("|cFF%02x%02x%02x[%%s]|r", math_ceil(v.r * 255), math_ceil(v.g * 255), math_ceil(v.b * 255))
end

-- Create the frame that runs the wait for loot alerts.
lootWaitFrame = CreateFrame("Frame")
lootWaitFrame:Hide()
lootWaitFrame:SetScript("OnUpdate", OnUpdateLootWait)

-- Register the parser events handler.
MSBTParser.RegisterHandler(ParserEventsHandler)