-- gui/pm_foreground.lua (Photo Mode round 16b): the Weather tab's Foreground section: something between the camera
-- and the subject (user: "Add the items you propose"). PLAN.md "Round 16b" item 2, TESTING.md FG1-FG6.
--
--   veil   a low cloud layer around the camera: cloudBase VEIL.below m under the eye, cloudTop VEIL.above m over
--          it, a denser cloudScattering and at least VEIL.cover cloud cover. Haze can't veil the near field (it
--          only grows with distance, findings environment.md "Haze only grows with distance"); a cloud layer
--          around the camera is the one thing that does. The layer follows the eye's height (re-set when it moves
--          more than VEIL.follow m, at most once a second, quietly).
--   rain   cloud cover RAIN.cover: the rain shader (base rendering/programs/shaders/atmosphere/rain.fs) fades its
--          drops in with smoothstep(0.8, 1.0, cloudCoverage), so nothing falls at 0.8 or less and the most at 1.0;
--          and it draws them only below cloudBase (`vpos.z > u_atmosphere.cloudBase` discards), so with the eye
--          above the cloud deck no drop shows near the camera (logged).
-- (Round 16b also had Dust, puffs of api.gui.rendering.spawnDust between the camera and the subject: removed in
-- round 17, the user found it bad and too subtle. PLAN.md "Round 17".)
-- The veil and the rain set their values through pm_sky (K.set: the Light & weather override, so the pause menu,
-- an untick of the override and the next load put the player's values back, as for every other cloud change);
-- unticking one puts back what it changed when the values are still ours. Nothing is saved; every exit
-- (untick, pause menu, a new game) ends both. Logs "[PhotoMode] foreground ...".

local core = ug_require "square_photo_mode::/photo_mode/pm_core.lua"
local sky = ug_require "square_photo_mode::/photo_mode/gui/pm_sky.lua"
local world = ug_require "square_photo_mode::/photo_mode/gui/pm_world.lua"

local M = {}

M.VEIL = { below = 30, above = 60, scattering = 0.012, cover = 0.6, follow = 40, followMs = 1000 }
M.RAIN = { cover = 0.97, threshold = 0.8 }
M.TOL = { height = 5, scattering = 0.0002, cover = 0.02 }

local S = { veil = nil, rain = nil }
M.S = S

-- Set by pm_window: the window shows something new.
M.changed = function() end

local function log(msg) core.log("foreground " .. msg) end
local function finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

local function nowMs() return world.nowMs() end

local function atmosphere()
	local ok, a = pcall(function()
		local at = api.gui.rendering.getEnvironment().atmosphere
		return { cloudBase = at.cloudBase, cloudTop = at.cloudTop, cloudScattering = at.cloudScattering,
			cloud = at.cloudCoverage }
	end)
	return ok and a or nil
end

local function eyeZ()
	local ok, z = pcall(function() return api.gui.camera.getEye().z end)
	return ok and finite(z) and z or nil
end

local function atText(a)
	if a == nil then return "unreadable" end
	return string.format("cloudBase=%s cloudTop=%s cloudScattering=%s cloudCoverage=%s", tostring(a.cloudBase),
		tostring(a.cloudTop), tostring(a.cloudScattering), tostring(a.cloud))
end

local function near(a, b, tol) return finite(a) and finite(b) and math.abs(a - b) <= tol end

--- The veil's values for an eye at height z, keeping at least the cover `cur` has (pure).
function M.veilValues(z, cur)
	local base = math.max(0, z - M.VEIL.below)
	return { cloudBase = base, cloudTop = base + M.VEIL.below + M.VEIL.above, cloudScattering = M.VEIL.scattering,
		cloud = math.max(M.VEIL.cover, finite(cur) and cur or 0) }
end

--- Puts back the fields of `orig` that still hold what we `set` (the player may have moved a slider since).
--- Returns the changes put back (a table, maybe empty), kept (field names).
function M.restorePlan(orig, set, now)
	local put, kept = {}, {}
	if orig == nil or set == nil then return put, kept end
	local tol = { cloudBase = M.TOL.height, cloudTop = M.TOL.height, cloudScattering = M.TOL.scattering,
		cloud = M.TOL.cover }
	for f, v in pairs(set) do
		if orig[f] ~= nil then
			if now ~= nil and near(now[f], v, tol[f] or 0) then put[f] = orig[f] else kept[#kept + 1] = f end
		end
	end
	table.sort(kept)
	return put, kept
end

local function setValues(values, why, quiet)
	local ok, err = pcall(function()
		if quiet then sky.setLive(values, why) else sky.set(values, why) end
	end)
	if not ok then log(why .. " ERROR " .. tostring(err)) end
	return ok
end

local function putBack(st, what, why)
	local now = atmosphere()
	local put, kept = M.restorePlan(st.orig, st.set, now)
	if next(put) ~= nil then setValues(put, "foreground " .. what .. " off") end
	log(string.format("%s off (%s): put back %s; kept (changed since) %s; now %s", what, why, atText(put),
		#kept > 0 and table.concat(kept, ",") or "-", atText(atmosphere())))
end

function M.veilOn() return S.veil ~= nil end
function M.rainOn() return S.rain ~= nil end

function M.setVeil(on, why)
	why = why or "checkbox"
	if on and S.veil == nil then
		local z, a = eyeZ(), atmosphere()
		if z == nil or a == nil then log("veil: no eye or environment read") return end
		local v = M.veilValues(z, a.cloud)
		-- the player's cover: the rain's own original when it is on (the cover now is the rain's)
		local player = S.rain ~= nil and S.rain.orig.cloud or a.cloud
		S.veil = { orig = { cloudBase = a.cloudBase, cloudTop = a.cloudTop, cloudScattering = a.cloudScattering,
			cloud = player }, set = v, z = z, at = nowMs() }
		setValues(v, "foreground veil")
		log(string.format("veil on: eye z %.0f; set %s; read back %s", z, atText(v), atText(atmosphere())))
	elseif not on and S.veil ~= nil then
		local st = S.veil
		S.veil = nil
		-- the rain keeps the cover it set
		if S.rain ~= nil then st.set.cloud = nil end
		putBack(st, "veil", why)
	end
	M.changed()
end

function M.setRain(on, why)
	why = why or "checkbox"
	if on and S.rain == nil then
		local a = atmosphere()
		if a == nil then log("rain: no environment read") return end
		local player = S.veil ~= nil and S.veil.orig.cloud or a.cloud
		S.rain = { orig = { cloud = player }, set = { cloud = math.max(M.RAIN.cover, finite(a.cloud) and a.cloud or 0) } }
		setValues(S.rain.set, "foreground rain")
		local b, z = atmosphere(), eyeZ()
		log(string.format("rain on: cloud cover %s -> %s (the shader's drops fade in above %.2f, full at 1.0); read back %s; "
			.. "eye z %s %s the cloud base (drops only below it)", tostring(a.cloud), tostring(S.rain.set.cloud),
			M.RAIN.threshold, atText(b), z and string.format("%.0f", z) or "-",
			(z and b and finite(b.cloudBase)) and (z < b.cloudBase and "under" or "ABOVE") or "vs"))
	elseif not on and S.rain ~= nil then
		local st = S.rain
		S.rain = nil
		-- the veil keeps its own cover: back to what the veil wants over the player's
		if S.veil ~= nil then
			st.orig.cloud = math.max(M.VEIL.cover, finite(st.orig.cloud) and st.orig.cloud or 0)
			S.veil.set.cloud = st.orig.cloud
		end
		putBack(st, "rain", why)
	end
	M.changed()
end

function M.busy() return S.veil ~= nil or S.rain ~= nil end

--- Every frame while busy (pm_button.script.lua): the veil following the eye; a value of ours
--- that is gone (the override unticked, a preset) ends that item.
function M.step()
	local now = nowMs()
	local v = S.veil
	if v ~= nil and now - v.at >= M.VEIL.followMs then
		v.at = now
		local a = atmosphere()
		if a ~= nil and not near(a.cloudBase, v.set.cloudBase, M.TOL.height) then
			S.veil = nil
			log("veil ended: the cloud base was changed elsewhere (" .. atText(a) .. ")")
			M.changed()
			return
		end
		local z = eyeZ()
		if z ~= nil and math.abs(z - v.z) > M.VEIL.follow then
			local nv = M.veilValues(z, v.set.cloud)
			v.z, v.set = z, nv
			setValues({ cloudBase = nv.cloudBase, cloudTop = nv.cloudTop }, "foreground veil follow", true)
		end
	end
	local r = S.rain
	if r ~= nil and r.checkAt == nil then r.checkAt = now end
	if r ~= nil and now - r.checkAt >= 2000 then
		r.checkAt = now
		local a = atmosphere()
		if a ~= nil and not near(a.cloud, r.set.cloud, M.TOL.cover) then
			S.rain = nil
			log("rain ended: the cloud cover was changed elsewhere (" .. atText(a) .. ")")
			M.changed()
		end
	end
end

--- Every exit: both off (the pause menu: before pm_sky puts the override's values back).
function M.stopAll(why)
	if S.rain ~= nil then M.setRain(false, why) end
	if S.veil ~= nil then M.setVeil(false, why) end
end

--- A new game: nothing of ours is on in it (the environment is the new game's).
function M.reset()
	S.veil, S.rain = nil, nil
end

--- The Weather tab's rows (pm_window's helpers UI = { heading, row, checkBox, note }).
function M.rows(UI)
	return {
		UI.heading(_("Foreground")),
		UI.row(UI.checkBox(_("Low cloud veil"),
			_("A thin cloud layer at the camera's height: a soft veil\nover everything in front of the camera.\nIt follows the camera up and down."),
			M.veilOn(), function(on) M.setVeil(on) end)),
		UI.row(UI.checkBox(_("Rain"),
			_("Thick clouds, so rain falls around the camera.\nRain shows only below the clouds."),
			M.rainOn(), function(on) M.setRain(on) end)),
		UI.note(_("The veil and the rain change only the picture and go when you untick them or open the menu.")),
	}
end

return M
