-- Every menu entry's params sit in the left toolbar (location "Toolbar", 2026-10-09: the menu's
-- hover tooltip no longer covers the settings there). The toolbar's buttons fit about 6 characters
-- (the user's screenshot: 3-button rows fit "Medium", 2-button rows cut "Highway" to "Highwa…"), so
-- every Button row has at most 5 labels of at most 6 characters; longer choices are ComboBoxes.

local DIR = "square_roundabouts::/infrastructure/street_construction/"

local function loadData(file)
	-- the file defines a global data(); each load replaces it
	ug_require(DIR .. file)
	return data()
end

local ENTRIES = {
	"square_roundabouts.con.lua",
	"square_roundabouts_magic.con.lua",
	"square_roundabouts_channel.con.lua",
	"square_roundabouts_interchange.con.lua",
	"square_roundabouts_highway_parclo.con.lua",
	"square_roundabouts_highway_parclo2.con.lua",
	"square_roundabouts_highway_diamond.con.lua",
}

-- UTF-8 characters, not bytes
local function chars(s)
	local _, n = s:gsub("[^\128-\191]", "")
	return n
end

test("every entry: params in the toolbar; Button rows of at most 5 labels of at most 6 characters", function()
	local buttons = 0
	for _, file in ipairs(ENTRIES) do
		local con = loadData(file)
		ok(#con.params > 0, file)
		for _, p in ipairs(con.params) do
			local n = file .. " " .. p.key
			eq(p.location, "Toolbar", n .. ": location")
			ok(p.uiType == "Button" or p.uiType == "ComboBox", n .. ": Button or ComboBox")
			if p.uiType == "Button" then
				buttons = buttons + 1
				ok(#p.values <= 5, n .. ": at most 5 buttons")
				for _, v in ipairs(p.values) do ok(chars(v) <= 6, n .. ": label '" .. v .. "' at most 6 characters") end
				-- per-value tooltips, where given, cover every button
				if p.tooltips then eq(#p.tooltips, #p.values, n .. ": tooltips") end
			else
				eq(p.tooltips, nil, n .. ": no per-value tooltips on a ComboBox")
			end
		end
	end
	ok(buttons >= 30, "button rows checked: " .. buttons)
end)

test("short labels are explained in the tooltip", function()
	-- S / M / L (and XS / XL) and the CCW / CW, Hwy abbreviations: the row's tooltip says what they mean
	local explain = { S = "small", M = "medium", L = "large", XS = "extra small", XL = "extra large",
		CCW = "counterclockwise", CW = "clockwise", Hwy = "highway", Right = "right-hand", Left = "left-hand" }
	for _, file in ipairs(ENTRIES) do
		local con = loadData(file)
		for _, p in ipairs(con.params) do
			if p.uiType == "Button" then
				for _, v in ipairs(p.values) do
					local word = explain[v]
					if word then
						ok(type(p.tooltip) == "string" and p.tooltip:lower():find(word, 1, true) ~= nil,
							file .. " " .. p.key .. ": tooltip explains '" .. v .. "'")
					end
				end
			end
		end
	end
end)
