-- Line Rate Matcher: pure model (plans/square_line_manager_plus/RATE_MATCHER.md "Suggestion maths"). No api.*, no
-- base modules, so it is unit-tested offline (tests/square_line_manager_plus/test_rate_matcher_model.lua). The engine
-- adapter (phase 2) turns the game's tables into the plain records of rate_matcher_types.d.tl.
--
-- Facts it relies on (docs/findings.md "Line Rate, cloning onto a line, sell on arrival", probe 2026-10-10):
--   * Rate (calcLineStationThroughput) is linear in identical vehicles (1/2/3 ships = 51/103/154), so
--     perVehicle = Rate / n predicts n +- k. Mixed lines: each vehicle's share is its capacity share for the
--     cargo (an assumption; identical vehicles reduce to Rate / n).
--   * A vehicle sent to the depot to be sold leaves the line at once and is not in Rate: `selling` vehicles
--     are not counted.
--   * Target = max production (getCargoMaxProductionPerYear, 101 for the probe's logging camp); the measured
--     produced/yr drifts (98-112) and is only a hint. Other lines count only when they LOAD the same cargo at
--     the shared group (the WC Logs group also had passenger lines with Rate 103 and 89: not subtracted).
--
-- Decisions (phase 1, 2026-10-10):
--   * Supply: each producer (stockList, cargo) counts once, however many of the line's loading stops reach it.
--     A cargo the line loads with no producer in reach (transfer from a warehouse or another line) gets no
--     target; it is returned in the second list so the GUI can say so. Passenger cargo never gets a target.
--   * Other lines: a line competes for cargo c when one of its stops loads c at a group where we load c, or
--     (when its stops carry producers) next to one of the producers we counted. Its whole Rate is subtracted
--     once per cargo (Rate is per line, not per cargo: a mixed-cargo competitor is over-counted; rare).
--   * Suggestion: the counts whose estimated Rate lies just below and just above the target; preselected = the
--     one closer to the target, a tie goes to fewer vehicles (cheaper). Clones copy the template: the model with
--     the most vehicles on the line (tie: the one with the newest vehicle, then the lower model id); its newest
--     vehicle is the one to clone. At most MAX_ADD clones; removal leaves at least MIN_VEHICLES.
--   * Surplus: removal sells the NEWEST vehicles first (highest purchaseTime, tie: higher entity id). They
--     resell for the most (resale value falls with age), and right after an over-shooting Apply the newest are
--     the clones just bought, so a removal undoes them almost at no cost. Protected (mission) vehicles and
--     vehicles already selling are skipped, and so are vehicles that carry none of the cargo (selling them would
--     not lower that cargo's Rate).
--   * Multi-cargo lines: one suggestion per cargo; the one needing the most vehicles wins (reason
--     "most_vehicles"), since fewer would leave that cargo's supply behind.
--   * Other models (rev. 2026-10-10 after the second GUI test): a vehicle's Rate is capacity / round trip, and the
--     round trip = driving + time at stops. Driving scales with 1 / top speed, the time at stops with
--     capacity / loadSpeed (cargo moved per stop at the model's metadata transportVehicle.loadSpeed; the terminal and
--     cargo load factors are the same for every model on the line and cancel out). With f = the share of the
--     current round trip spent at stops (model.loadShare of the line's LineCargoInfo section times):
--         perVehicle_m = perVehicle * (cap_m / cap_cur)
--                        / ((1 - f) * speed_cur / speed_m + f * (cap_m / load_m) / (cap_cur / load_cur))
--     The current model gives exactly perVehicle. f unknown or a load speed unknown: f = 0, i.e. the old
--     capacity x speed scaling. Not modelled: acceleration and speed limits on the route (top speed is taken as the
--     travel speed), fixed waits at stops (counted as loading, so a bigger vehicle is estimated a little slow), and
--     arrival / departure delays. Shown as "≈". count = floor or ceil of target / perVehicle_m, whichever is closer
--     (tie: fewer, never below 1); ranked by distance to the target, then fewer vehicles, then model id.
--     Why the speed-only estimate gave every model the same "per rate": base vehicles have price = -1 and
--     runningCosts = -1, which model_metadata_util.addCostMetadata (base/content/base/model_metadata_util.lua:488-552)
--     turns into runningCosts = round(c x averageSpeed x capacity / 4) and price = 6 x that (water: average speed =
--     0.65 x top speed). Running costs and price are both proportional to capacity x speed, exactly what the old
--     estimate scaled the Rate by, so their ratio was a constant. Only the time at stops (and lifespan, hand-set
--     prices of modded vehicles, rounding) makes models differ.
--
-- Plans and costs (2026-10-10, after the first GUI test; plans/square_line_manager_plus/RATE_MATCHER.md "Phase 3b"):
--   * A plan = a model and a count. The fleet's model: the suggestion's below / above (clones or sells). Another
--     model: a SWITCH of the whole fleet (mixed lines too), as the vanilla Replace window does it: the old vehicles
--     are replaced in place (makeVehicleReplaceCmd keeps the vehicle and its line), the extra ones bought onto the
--     line, the surplus old ones sold. Mission (protected) vehicles block a switch.
--   * Purchase: new vehicles x store price (metadata cost.price); refund: resale value (getDepreciatedValue) of
--     every vehicle replaced or sold; net = price - refund, the Replace window's "Replace N Vehicles for {cost}"
--     (vehicle_store_window.tl:3525-3541 refund, 2992-3003 hasEnoughMoney, 4267-4278).
--   * Running per year after the plan: the kept vehicles' own running cost (getRunningCost, as the vehicle window),
--     plus new vehicles x the model's metadata running cost (the store's "{cost}/year"; for clones of the fleet's
--     model, when that is unknown, its vehicles' mean).
--   * Cost of ownership per year (costYear) = running + capital: capital = every vehicle's store price spread over
--     its model's lifespan (maintenance.lifespan x 1000 game ms, vehicle_util.getLifespan, divided by the calendar
--     year at the current speed as Problem Radar's radar_checks.calendarYearMs; capitalPerYear). Kept vehicles count
--     at their model's new price, so fleets of different ages compare as if each were bought new. perRate =
--     costYear / rate: the yearly cost of 1 unit of Rate, the comparison figure; bestByPerRate marks the lowest
--     (within BEST_TOLERANCE; nothing when all tie). "Price" (net) stays the cash needed today.
--   * Which old vehicles go when a switch shrinks the fleet does not change the net (all of them are refunded):
--     the newest are sold (pickSurplus order), the rest replaced.

local model : SquareRateMatcherModel = {}

model.MAX_ADD = 100
model.MIN_VEHICLES = 1
model.MAX_MODEL_COUNT = 100
model.TOP_MODELS = 5
model.EPS = 1e-6
model.MAX_LOAD_SHARE = 0.95
model.BEST_TOLERANCE = 0.005

local function num(v : any) : number
	if type(v) ~= "number" then return nil end
	local n = v as number
	if n ~= n or n == math.huge or n == -math.huge then return nil end
	return n
end

-- Non-negative finite number, else 0.
local function nonneg(v : any) : number
	local n = num(v)
	if n == nil or n < 0 then return 0 end
	return n
end

--- floor(x + 0.5) like base mathutil.round; nil for non-numbers, NaN, inf and negatives.
function model.roundValue(v : any) : integer
	local n = num(v)
	if n == nil or n < 0 then return nil end
	return math.floor(n + 0.5)
end

--- IdVector (index = cargo + 1, value true when loaded; Line.Stop.stopConfig.load) -> {cargo -> true}.
function model.loadSetFromIdVector(v : {boolean}) : {integer : boolean}
	local out : {integer : boolean} = {}
	if type(v) ~= "table" then return out end
	for k, b in pairs(v as {integer : boolean}) do
		if b == true and type(k) == "number" and k >= 1 then
			out[math.floor(k) - 1] = true
		end
	end
	return out
end

local function sortedKeys(set : {integer : any}) : {integer}
	local out : {integer} = {}
	for k, __ in pairs(set) do out[#out + 1] = k end
	table.sort(out)
	return out
end

-- targetsFromSupply -----------------------------------------------------------------

function model.targetsFromSupply(input : SquareRateMatcherSupplyInput) : {SquareRateMatcherCargoTarget}, {integer}
	local targets : {SquareRateMatcherCargoTarget} = {}
	local unsupplied : {integer} = {}
	if type(input) ~= "table" then return targets, unsupplied end
	local passenger = input.passengerCargo
	local stops = input.stops or {}

	-- Per cargo: the groups where we load it, the producers counted (key stockList) and whether loaded at all.
	local loaded : {integer : boolean} = {}
	local groupsOf : {integer : {integer : boolean}} = {}
	local producersOf : {integer : {integer : SquareRateMatcherProducer}} = {}
	for __, stop in ipairs(stops) do
		local loads = stop.loads or {}
		for cargo, isLoaded in pairs(loads) do
			if isLoaded == true and cargo ~= passenger then
				loaded[cargo] = true
				local groups = groupsOf[cargo]
				if groups == nil then
					groups = {}
					groupsOf[cargo] = groups
				end
				if stop.stationGroup ~= nil then groups[stop.stationGroup] = true end
			end
		end
		for __, p in ipairs(stop.producers or {}) do
			local cargo = p.cargo
			if cargo ~= nil and cargo ~= passenger and loads[cargo] == true and p.stockList ~= nil then
				local byStock = producersOf[cargo]
				if byStock == nil then
					byStock = {}
					producersOf[cargo] = byStock
				end
				-- Dedupe: a producer reached from several loading stops counts once.
				if byStock[p.stockList] == nil then byStock[p.stockList] = p end
			end
		end
	end

	for __, cargo in ipairs(sortedKeys(loaded)) do
		local byStock = producersOf[cargo]
		if byStock == nil then
			unsupplied[#unsupplied + 1] = cargo
		else
			local maxSupply, produced, anyProduced = 0.0, 0.0, false
			for __, p in pairs(byStock) do
				maxSupply = maxSupply + nonneg(p.maxPerYear)
				local pr = num(p.producedPerYear)
				if pr ~= nil and pr >= 0 then
					produced = produced + pr
					anyProduced = true
				end
			end
			local groups = groupsOf[cargo]
			local competitors : {integer : boolean} = {}
			local seenTables : {SquareRateMatcherOtherLine : boolean} = {}
			local otherRate = 0.0
			for __, other in ipairs(input.otherLines or {}) do
				local isSelf = other.line ~= nil and other.line == input.line
				local seen = (other.line ~= nil and competitors[other.line]) or seenTables[other]
				if not isSelf and not seen then
					local competes = false
					for __, s in ipairs(other.stops or {}) do
						if s.loads ~= nil and s.loads[cargo] == true then
							if s.stationGroup ~= nil and groups[s.stationGroup] then
								competes = true
							else
								for __, p in ipairs(s.producers or {}) do
									if p.cargo == cargo and p.stockList ~= nil and byStock[p.stockList] ~= nil then
										competes = true
										break
									end
								end
							end
						end
						if competes then break end
					end
					if competes then
						if other.line ~= nil then competitors[other.line] = true end
						seenTables[other] = true
						otherRate = otherRate + nonneg(other.rate)
					end
				end
			end
			local target = maxSupply - otherRate
			if target < 0 then target = 0 end
			targets[#targets + 1] = {
				cargo = cargo,
				maxSupply = maxSupply,
				produced = anyProduced and produced or nil,
				otherRate = otherRate,
				otherLines = sortedKeys(competitors),
				producers = sortedKeys(byStock),
				target = model.roundValue(target),
			}
		end
	end
	return targets, unsupplied
end

-- perVehicleRates / pickSurplus --------------------------------------------------------

-- Capacity for the cargo (0 when invalid); weight 1 for every vehicle when no cargo is given.
local function weight(v : SquareRateMatcherVehicle, cargo : integer) : number
	if cargo == nil then return 1 end
	if v.capacities == nil then return 0 end
	return nonneg(v.capacities[cargo])
end

--- Splits the line's Rate over its vehicles by capacity share for `cargo` (equal shares when cargo is nil).
--- Returns {vehicle id -> perVehicle} and {model -> mean perVehicle}; nil when the vehicles carry none of it.
--- Vehicles already selling are not on the line and get nothing.
function model.perVehicleRates(rate : number, vehicles : {SquareRateMatcherVehicle}, cargo : integer) : {integer : number}, {integer : number}
	local r = num(rate)
	if r == nil or r < 0 or type(vehicles) ~= "table" then return nil, nil end
	local total = 0.0
	for __, v in ipairs(vehicles) do
		if not v.selling then total = total + weight(v, cargo) end
	end
	if total <= 0 then return nil, nil end
	local perVehicle : {integer : number} = {}
	local sum : {integer : number} = {}
	local cnt : {integer : integer} = {}
	for __, v in ipairs(vehicles) do
		if not v.selling then
			local pv = r * weight(v, cargo) / total
			if v.id ~= nil then perVehicle[v.id] = pv end
			if v.model ~= nil then
				sum[v.model] = (sum[v.model] or 0) + pv
				cnt[v.model] = (cnt[v.model] or 0) + 1
			end
		end
	end
	local perModel : {integer : number} = {}
	for m, s in pairs(sum) do perModel[m] = s / cnt[m] end
	return perVehicle, perModel
end

local function newerFirst(a : SquareRateMatcherVehicle, b : SquareRateMatcherVehicle) : boolean
	local ta, tb = num(a.purchaseTime), num(b.purchaseTime)
	if ta ~= tb then
		if ta == nil then return false end
		if tb == nil then return true end
		return ta > tb
	end
	return (a.id or 0) > (b.id or 0)
end

--- Vehicle ids to sell, best first, at most k (all eligible when k is nil): newest purchaseTime first
--- (tie: higher id); skips protected and selling vehicles and, with a cargo, those carrying none of it.
function model.pickSurplus(vehicles : {SquareRateMatcherVehicle}, k : integer, cargo? : integer) : {integer}
	local out : {integer} = {}
	if type(vehicles) ~= "table" then return out end
	if k ~= nil and k <= 0 then return out end
	local eligible : {SquareRateMatcherVehicle} = {}
	for __, v in ipairs(vehicles) do
		if v.id ~= nil and not v.protected and not v.selling and (cargo == nil or weight(v, cargo) > 0) then
			eligible[#eligible + 1] = v
		end
	end
	table.sort(eligible, newerFirst)
	for i, v in ipairs(eligible) do
		if k ~= nil and i > k then break end
		out[#out + 1] = v.id
	end
	return out
end

-- suggest -------------------------------------------------------------------------------

local function status(s : string, cargo : integer, target : number) : SquareRateMatcherSuggestion
	return { status = s, cargo = cargo, target = target }
end

function model.suggest(rate : number, vehicles : {SquareRateMatcherVehicle}, cargo : integer, target : number) : SquareRateMatcherSuggestion
	local t = num(target)
	if t == nil or t < 0 then return status("invalid_target", cargo, target) end
	local active : {SquareRateMatcherVehicle} = {}
	for __, v in ipairs(vehicles or {}) do
		if not v.selling then active[#active + 1] = v end
	end
	local n = #active
	if n == 0 then return status("no_vehicles", cargo, t) end
	local r = num(rate)
	if r == nil or r <= 0 then return status("no_rate", cargo, t) end
	local pvOf, perModel = model.perVehicleRates(r, active, cargo)
	if pvOf == nil then return status("no_capacity", cargo, t) end

	-- Template: the model with the most carrying vehicles; tie: newest vehicle; then lower model id.
	local countOf : {integer : integer} = {}
	local newestOf : {integer : SquareRateMatcherVehicle} = {}
	for __, v in ipairs(active) do
		if v.model ~= nil and (pvOf[v.id] or 0) > 0 then
			countOf[v.model] = (countOf[v.model] or 0) + 1
			local cur = newestOf[v.model]
			if cur == nil or newerFirst(v, cur) then newestOf[v.model] = v end
		end
	end
	local template : integer = nil
	for __, m in ipairs(sortedKeys(countOf)) do
		if template == nil or countOf[m] > countOf[template]
			or (countOf[m] == countOf[template] and newerFirst(newestOf[m], newestOf[template])) then
			template = m
		end
	end
	if template == nil then return status("no_capacity", cargo, t) end
	local perVehicle = perModel[template]

	local order = model.pickSurplus(active, nil, cargo)
	local maxRemove = math.min(#order, n - model.MIN_VEHICLES)
	if maxRemove < 0 then maxRemove = 0 end

	local function option(d : integer, est : number) : SquareRateMatcherOption
		local o : SquareRateMatcherOption = { delta = d, count = n + d, rate = est }
		if d < 0 then
			o.remove = {}
			for i = 1, -d do o.remove[i] = order[i] end
		end
		return o
	end

	-- est(d) rises with d: removals subtract the picked vehicles' shares, clones add the template's.
	local estOf : {integer : number} = { [0] = r }
	local acc = r
	for i = 1, maxRemove do
		acc = acc - (pvOf[order[i]] or 0)
		estOf[-i] = acc
	end
	-- the scan keeps only the deltas; the two options (with their remove lists) are built once at the end
	local belowD, aboveD : integer, integer = nil, nil
	local belowEst, aboveEst : number, number = nil, nil
	for d = -maxRemove, model.MAX_ADD do
		local est = d > 0 and (r + d * perVehicle) or estOf[d]
		if est <= t + model.EPS then belowD, belowEst = d, est end
		if est >= t - model.EPS then
			aboveD, aboveEst = d, est
			break
		end
	end
	local below = belowD ~= nil and option(belowD, belowEst) or nil
	local above : SquareRateMatcherOption = nil
	if aboveD ~= nil then above = aboveD == belowD and below or option(aboveD, aboveEst) end

	local pre : SquareRateMatcherOption
	if below == nil then
		pre = above
	elseif above == nil then
		pre = below
	elseif math.abs(above.rate - t) < math.abs(below.rate - t) - model.EPS then
		pre = above
	else
		pre = below
	end

	return {
		status = "ok",
		cargo = cargo,
		target = t,
		rate = r,
		count = n,
		perVehicle = perVehicle,
		perModel = perModel,
		templateModel = template,
		templateVehicle = newestOf[template].id,
		below = below,
		above = above,
		preselected = pre,
		delta = pre.delta,
		capped = above == nil,
	}
end

--- One suggestion per cargo in `targets` ({cargo -> target}); returns the one needing the most vehicles
--- (preselected count, tie: the larger "above" count, then the lower cargo id) with perCargo = all of them
--- in cargo order. With no usable cargo it returns the lowest cargo's (failed) suggestion.
function model.suggestForCargos(rate : number, vehicles : {SquareRateMatcherVehicle}, targets : {integer : number}) : SquareRateMatcherSuggestion
	local all : {SquareRateMatcherSuggestion} = {}
	for __, cargo in ipairs(sortedKeys(targets or {})) do
		all[#all + 1] = model.suggest(rate, vehicles, cargo, targets[cargo])
	end
	if #all == 0 then
		local s = status("invalid_target", nil, nil)
		s.perCargo = all
		return s
	end
	local function aboveCount(s : SquareRateMatcherSuggestion) : number
		if s.above == nil then return math.huge end
		return s.above.count
	end
	local best : SquareRateMatcherSuggestion = nil
	for __, s in ipairs(all) do
		if s.status == "ok" then
			if best == nil or s.preselected.count > best.preselected.count
				or (s.preselected.count == best.preselected.count and aboveCount(s) > aboveCount(best)) then
				best = s
			end
		end
	end
	best = best or all[1]
	best.reason = #all == 1 and "single_cargo" or "most_vehicles"
	best.perCargo = all
	return best
end

-- rankModels ----------------------------------------------------------------------------

function model.loadShare(sectionTimes : {number}, driveTimes : {number}) : number
	if type(sectionTimes) ~= "table" or type(driveTimes) ~= "table" then return nil end
	local section, drive = 0.0, 0.0
	for __, t in ipairs(sectionTimes) do
		local n = num(t)
		if n == nil or n < 0 then return nil end
		section = section + n
	end
	for __, t in ipairs(driveTimes) do
		local n = num(t)
		if n == nil or n < 0 then return nil end
		drive = drive + n
	end
	if section <= 0 or drive <= 0 or drive > section * (1 + model.EPS) then return nil end
	local f = 1 - drive / section
	if f < 0 then f = 0 end
	if f > model.MAX_LOAD_SHARE then f = model.MAX_LOAD_SHARE end
	return f
end

function model.modelPerVehicle(current : SquareRateMatcherCurrent, cand : SquareRateMatcherCandidate) : number
	if type(current) ~= "table" or type(cand) ~= "table" then return nil end
	local capCur, speedCur, pvCur = num(current.capacity), num(current.speed), num(current.perVehicle)
	local cap, speed = num(cand.capacity), num(cand.speed)
	if capCur == nil or capCur <= 0 or speedCur == nil or speedCur <= 0 or pvCur == nil or pvCur <= 0
		or cap == nil or cap <= 0 or speed == nil or speed <= 0 then
		return nil
	end
	local f = num(current.loadShare)
	local loadCur, load = num(current.loadSpeed), num(cand.loadSpeed)
	if f == nil or f < 0 or loadCur == nil or loadCur <= 0 or load == nil or load <= 0 then f = 0 end
	if f > model.MAX_LOAD_SHARE then f = model.MAX_LOAD_SHARE end
	if f == 0 then return pvCur * cap / capCur * speed / speedCur end
	local timeRatio = (1 - f) * speedCur / speed + f * (cap / load) / (capCur / loadCur)
	return pvCur * (cap / capCur) / timeRatio
end

function model.capitalPerYear(price : number, lifespanMs : number, yearMs : number) : number
	local p, l, y = num(price), num(lifespanMs), num(yearMs)
	if p == nil or p < 0 or l == nil or l <= 0 or y == nil or y <= 0 then return nil end
	return p * y / l
end

function model.bestByPerRate(plans : {SquareRateMatcherPlan}) : {integer : boolean}
	local out : {integer : boolean} = {}
	local best : number = nil
	local known = 0
	for __, p in ipairs(plans or {}) do
		local r = p ~= nil and num(p.perRate) or nil
		if r ~= nil and r >= 0 then
			known = known + 1
			if best == nil or r < best then best = r end
		end
	end
	if best == nil or known < 2 then return out end
	local marked = 0
	for i, p in ipairs(plans) do
		local r = p ~= nil and num(p.perRate) or nil
		if r ~= nil and r <= best * (1 + model.BEST_TOLERANCE) + model.EPS then
			out[i] = true
			marked = marked + 1
		end
	end
	if marked == known then return {} end
	return out
end

function model.rankModels(candidates : {SquareRateMatcherCandidate}, current : SquareRateMatcherCurrent, target : number, topN? : integer) : {SquareRateMatcherModelOption}
	local out : {SquareRateMatcherModelOption} = {}
	if type(candidates) ~= "table" or type(current) ~= "table" then return out end
	local t = num(target)
	local capCur, speedCur, pvCur = num(current.capacity), num(current.speed), num(current.perVehicle)
	if t == nil or t <= 0 or capCur == nil or capCur <= 0 or speedCur == nil or speedCur <= 0
		or pvCur == nil or pvCur <= 0 then
		return out
	end
	local seen : {integer : boolean} = {}
	for __, c in ipairs(candidates) do
		local pv = (c.model ~= nil and c.model ~= current.model and not seen[c.model])
			and model.modelPerVehicle(current, c) or nil
		if pv ~= nil and pv > 0 then
			seen[c.model] = true
			local lo = math.max(1, math.floor(t / pv))
			local hi = math.max(1, math.ceil(t / pv))
			local count = lo
			if math.abs(hi * pv - t) < math.abs(lo * pv - t) - model.EPS then count = hi end
			if count <= model.MAX_MODEL_COUNT then
				out[#out + 1] = { model = c.model, perVehicle = pv, count = count, rate = count * pv,
					diff = math.abs(count * pv - t) }
			end
		end
	end
	table.sort(out, function(a : SquareRateMatcherModelOption, b : SquareRateMatcherModelOption) : boolean
		if math.abs(a.diff - b.diff) > model.EPS then return a.diff < b.diff end
		if a.count ~= b.count then return a.count < b.count end
		return a.model < b.model
	end)
	local limit = topN or model.TOP_MODELS
	while #out > limit do table.remove(out) end
	return out
end

-- plans ------------------------------------------------------------------------------------


local function activeOf(vehicles : {SquareRateMatcherVehicle}) : {SquareRateMatcherVehicle}
	local out : {SquareRateMatcherVehicle} = {}
	for __, v in ipairs(vehicles or {}) do
		if not v.selling then out[#out + 1] = v end
	end
	return out
end

function model.fleetRunning(vehicles : {SquareRateMatcherVehicle}) : number
	local sum, any = 0.0, false
	for __, v in ipairs(activeOf(vehicles)) do
		local r = num(v.running)
		if r ~= nil and r >= 0 then
			sum = sum + r
			any = true
		end
	end
	if not any then return nil end
	return sum
end

function model.planCost(p : SquareRateMatcherPlan, vehicles : {SquareRateMatcherVehicle}, costs : SquareRateMatcherModelCosts) : SquareRateMatcherPlan
	if p == nil then return nil end
	local gone : {integer : boolean} = {}
	for __, id in ipairs(p.remove or {}) do gone[id] = true end
	for __, id in ipairs(p.replace or {}) do gone[id] = true end
	local newCount = (p.buy or 0) + #(p.replace or {})
	local price = costs ~= nil and num(costs.price) or nil
	local runNew = costs ~= nil and num(costs.running) or nil
	local capNew = costs ~= nil and num(costs.capital) or nil
	-- a clone of the fleet's model: its vehicles' mean running cost / capital, when the model's is unknown
	local function fleetMean(field : string) : number
		local sum, n = 0.0, 0
		for __, v in ipairs(activeOf(vehicles)) do
			local r = num((v as {string : any})[field])
			if v.model == p.model and r ~= nil then
				sum, n = sum + r, n + 1
			end
		end
		if n > 0 then return sum / n end
		return nil
	end
	if runNew == nil and not p.switch then runNew = fleetMean("running") end
	if capNew == nil and not p.switch then capNew = fleetMean("capital") end
	if newCount == 0 then
		p.price = 0
	elseif price ~= nil then
		p.price = newCount * price
	else
		p.price = nil
	end
	local refund, running, runningKnown = 0.0, 0.0, true
	local capital, capitalKnown = 0.0, true
	for __, v in ipairs(activeOf(vehicles)) do
		if gone[v.id] then
			refund = refund + nonneg(v.value)
		else
			local r = num(v.running)
			if r == nil and not p.switch and v.model == p.model then r = runNew end
			if r == nil then runningKnown = false else running = running + r end
			local c = num(v.capital)
			if c == nil and not p.switch and v.model == p.model then c = capNew end
			if c == nil then capitalKnown = false else capital = capital + c end
		end
	end
	if newCount > 0 then
		if runNew == nil then runningKnown = false else running = running + newCount * runNew end
		if capNew == nil then capitalKnown = false else capital = capital + newCount * capNew end
	end
	p.refund = refund
	p.net = p.price ~= nil and p.price - refund or nil
	p.running = runningKnown and running or nil
	p.capital = capitalKnown and capital or nil
	p.costYear = (p.running ~= nil and p.capital ~= nil) and p.running + p.capital or nil
	local rate = num(p.rate)
	p.perRate = (p.costYear ~= nil and rate ~= nil and rate > model.EPS) and p.costYear / rate or nil
	return p
end

function model.plansFromSuggestion(s : SquareRateMatcherSuggestion, vehicles : {SquareRateMatcherVehicle}, costs : SquareRateMatcherModelCosts) : {SquareRateMatcherPlan}
	local out : {SquareRateMatcherPlan} = {}
	if s == nil or s.status ~= "ok" then return out end
	local opts : {SquareRateMatcherOption} = {}
	if s.below ~= nil then opts[#opts + 1] = s.below end
	if s.above ~= nil and (s.below == nil or s.above.delta ~= s.below.delta) then opts[#opts + 1] = s.above end
	table.sort(opts, function(a : SquareRateMatcherOption, b : SquareRateMatcherOption) : boolean
		return a.count < b.count
	end)
	for __, o in ipairs(opts) do
		local p : SquareRateMatcherPlan = {
			model = s.templateModel,
			switch = false,
			count = o.count,
			delta = o.delta,
			rate = o.rate,
			diff = o.rate - s.target,
			buy = o.delta > 0 and o.delta or 0,
			remove = o.remove or {},
			replace = {},
			suggested = s.preselected ~= nil and s.preselected.delta == o.delta,
		}
		out[#out + 1] = model.planCost(p, vehicles, costs)
	end
	return out
end

function model.switchPlans(modelId : integer, perVehicle : number, target : number, vehicles : {SquareRateMatcherVehicle}, costs : SquareRateMatcherModelCosts) : {SquareRateMatcherPlan}, string
	local out : {SquareRateMatcherPlan} = {}
	local t, pv = num(target), num(perVehicle)
	if modelId == nil or t == nil or t <= 0 or pv == nil or pv <= 0 then return out, "invalid" end
	local active = activeOf(vehicles)
	local n = #active
	if n == 0 then return out, "no_vehicles" end
	for __, v in ipairs(active) do
		if v.protected then return out, "protected" end
	end
	-- rankModels' counts and pick, so the comparison table and the plan rows agree
	local lo = math.max(1, math.floor(t / pv))
	local hi = math.max(1, math.ceil(t / pv))
	local pick = lo
	if math.abs(hi * pv - t) < math.abs(lo * pv - t) - model.EPS then pick = hi end
	local counts : {integer} = { lo }
	if hi ~= lo then counts[2] = hi end
	local order = model.pickSurplus(active, nil) -- newest first; none protected here
	for __, k in ipairs(counts) do
		if k <= model.MAX_MODEL_COUNT then
			local remove, replace : {integer}, {integer} = {}, {}
			local sellN = math.max(0, n - k)
			for i, id in ipairs(order) do
				if i <= sellN then remove[#remove + 1] = id else replace[#replace + 1] = id end
			end
			local p : SquareRateMatcherPlan = {
				model = modelId,
				switch = true,
				count = k,
				delta = k - n,
				rate = k * pv,
				diff = k * pv - t,
				buy = math.max(0, k - n),
				remove = remove,
				replace = replace,
				suggested = k == pick,
			}
			out[#out + 1] = model.planCost(p, vehicles, costs)
		end
	end
	return out, nil
end

return model
