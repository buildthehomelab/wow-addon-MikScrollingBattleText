-- Checks the total in MSBT's loot alert against a fake client. Run from the repo root:
--   luajit tests/loot_count_test.lua
-- The fake client changes the bag count and delivers the loot message in whichever order a
-- scenario asks for, since that order is what the total has to survive.

local LOOT_FILE = arg and arg[1] or "MikScrollingBattleText/MSBTLoot.lua"
local LINK = "|cffffffff|Hitem:2770:0:0:0:0:0:0:0:0|h[Copper Ore]|h|r"
local OTHER = "|cffffffff|Hitem:2589:0:0:0:0:0:0:0:0|h[Linen Cloth]|h|r"

-- Builds a fresh client and loads the loot module into it.
local function NewClient()
	local client = { now = 100, bags = {}, alerts = {}, frames = {} }
	local env = {
		string = string, math = math, table = table, select = select, pairs = pairs,
		ipairs = ipairs, tonumber = tonumber, tostring = tostring, type = type,
		GOLD_AMOUNT = "%d Gold", SILVER_AMOUNT = "%d Silver", COPPER_AMOUNT = "%d Copper",
		ITEM_QUALITY_COLORS = { [1] = { r = 1, g = 1, b = 1 } },
		GetAuctionItemClasses = function ()
			return "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "Quest"
		end,
		GetItemInfo = function (link)
			if client.noItemInfo then return nil end
			return link == OTHER and "Linen Cloth" or "Copper Ore", nil, 1, nil, nil, "Trade Goods",
				nil, nil, nil, "icon"
		end,
		GetItemCount = function (link) return client.bags[link] or 0 end,
		GetTime = function () return client.now end,
		CreateFrame = function ()
			local frame = { shown = true, scripts = {} }
			function frame:SetScript(name, fn) self.scripts[name] = fn end
			function frame:Show() self.shown = true end
			function frame:Hide() self.shown = false end
			client.frames[#client.frames + 1] = frame
			return frame
		end,
	}
	client.profile = {
		qualityExclusions = {}, itemExclusions = {}, itemsAllowed = {},
		events = { NOTIFICATION_LOOT = { message = "+%a %e (%t)" }, NOTIFICATION_MONEY = { message = "%e" } },
	}
	env.MikSBT = {
		Profiles = { currentProfile = client.profile, IsModDisabled = function () return client.disabled end },
		Parser = { RegisterHandler = function (fn) client.handler = fn end },
		Animations = { DisplayEvent = function (_, message) client.alerts[#client.alerts + 1] = message end },
	}
	local chunk = assert(loadfile(LOOT_FILE))
	setfenv(chunk, env)
	chunk()
	return client
end

-- The server's item push result reaches the client.
local function Message(client, link, amount, isCreate)
	-- The parser hands over the count as it captured it from the chat line, so a string, or nil
	-- when the line has no count.
	client.handler({ recipientUnit = "player", eventType = "loot", itemLink = link, amount = amount and tostring(amount), isCreate = isCreate })
end

-- Lets time pass, a frame at a time, running whatever OnUpdate is live.
local function Run(client, seconds)
	local stop = client.now + (seconds or 0.05)
	repeat
		client.now = client.now + 0.01
		for _, frame in ipairs(client.frames) do
			if frame.shown and frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame, 0.01) end
		end
	until client.now >= stop
end

local failures, passes = 0, 0
local function Scenario(name, fn)
	local client = NewClient()
	local expected = fn(client)
	local got = table.concat(client.alerts, " | ")
	local want = table.concat(expected, " | ")
	if got == want then
		passes = passes + 1
		print("ok    " .. name)
	else
		failures = failures + 1
		print("FAIL  " .. name .. "\n      want: " .. want .. "\n      got:  " .. got)
	end
end

local ORE = "|cFFffffff[Copper Ore]|r"
local CLOTH = "|cFFffffff[Linen Cloth]|r"

Scenario("message first, then the bag update", function (c)
	c.bags[LINK] = 10
	Message(c, LINK, 3); Run(c)
	c.bags[LINK] = 13; Run(c)
	return { "+3 " .. ORE .. " (13)" }
end)

Scenario("two stacks in one tick both end on the real total", function (c)
	c.bags[LINK] = 10
	Message(c, LINK, 3); Message(c, LINK, 2); Run(c)
	c.bags[LINK] = 15; Run(c)
	return { "+3 " .. ORE .. " (15)", "+2 " .. ORE .. " (15)" }
end)

Scenario("one item, where the chat line has no count", function (c)
	c.bags[LINK] = 10
	Message(c, LINK); Run(c)
	c.bags[LINK] = 11; Run(c)
	return { "+1 " .. ORE .. " (11)" }
end)

Scenario("bag update first, as some servers send it", function (c)
	c.bags[LINK] = 13
	Message(c, LINK, 3); Run(c, 1.1)
	return { "+3 " .. ORE .. " (13)" }
end)

Scenario("nothing of it in the bags yet", function (c)
	Message(c, LINK, 3); Run(c)
	c.bags[LINK] = 3; Run(c)
	return { "+3 " .. ORE .. " (3)" }
end)

Scenario("a reagent deposit lands while the alert waits", function (c)
	c.bags[LINK] = 30
	Message(c, LINK, 3); Run(c)
	c.bags[LINK] = 0; Run(c)
	return { "+3 " .. ORE .. " (3)" }
end)

Scenario("count never moves and GetItemCount says 0", function (c)
	Message(c, LINK, 3); Run(c, 1.1)
	return { "+3 " .. ORE .. " (3)" }
end)

Scenario("alerts stay in the order they were looted", function (c)
	c.bags[LINK], c.bags[OTHER] = 10, 4
	Message(c, LINK, 3); Message(c, OTHER, 1); Run(c)
	c.bags[LINK], c.bags[OTHER] = 13, 5; Run(c)
	return { "+3 " .. ORE .. " (13)", "+1 " .. CLOTH .. " (5)" }
end)

Scenario("created items stay ignored", function (c)
	c.bags[LINK] = 10
	Message(c, LINK, 1, true); Run(c, 1.1)
	return {}
end)

Scenario("a disabled loot alert shows nothing", function (c)
	c.profile.events.NOTIFICATION_LOOT.disabled = true
	Message(c, LINK, 3); Run(c, 1.1)
	return {}
end)

Scenario("MSBT gets disabled while an alert waits", function (c)
	c.bags[LINK] = 10
	Message(c, LINK, 3); Run(c)
	c.disabled = true
	c.bags[LINK] = 13; Run(c)
	return {}
end)

Scenario("an item the client has no info for is skipped", function (c)
	c.noItemInfo = true
	Message(c, LINK, 3); Run(c, 1.1)
	return {}
end)

-- A count that never moves holds its alert for the full wait, then the frame stops running.
do
	local c = NewClient()
	c.bags[LINK] = 13
	Message(c, LINK, 3)
	Run(c, 0.9)
	local heldEarly = #c.alerts == 0
	Run(c, 0.2)
	local idle = true
	for _, frame in ipairs(c.frames) do
		if frame.shown then idle = false end
	end
	if heldEarly and idle and #c.alerts == 1 then
		passes = passes + 1
		print("ok    gives up after a second and stops its frame")
	else
		failures = failures + 1
		print("FAIL  gives up after a second and stops its frame")
	end
end

print(passes .. " passed, " .. failures .. " failed")
os.exit(failures == 0 and 0 or 1)
