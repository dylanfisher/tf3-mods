-- Round 18: gui/pm_bar.script.lua, the cutscene bar wrapped around the base FreeCamOptions recipe (react
-- replacement), on a fake react / builtin. Outside a cutscene of ours it renders exactly the original; while one
-- plays it adds 1x / 2x / 4x and Stop; an error in our part never takes the original down.

local R, original, replaced, steps, state, B, drv, lensStops, logs

local function node(kind) return function(p) return { kind = kind, p = p } end end

local function setup(opts)
	opts = opts or {}
	reset_modules()
	steps, replaced, lensStops, logs = {}, nil, 0, {}
	original = { kind = "ORIGINAL" }
	state = { value = false, expired = false }
	R = {
		RegisterRecipe = function(name, fn) return { name = name, fn = fn } end,
		useState = function()
			return {
				old = function() return state.value end,
				set = function(_, v) state.value = v end,
				hasExpired = function() return state.expired end,
			}
		end,
		onStep = function(fn) steps[#steps + 1] = fn end,
		CallOriginalRecipe = function(recipe, param)
			eq(recipe, "FREECAM", "the base recipe is called")
			original.param = param
			return original
		end,
	}
	stub_module("::/gui/main/react.lua", R)
	stub_module("::/gui/main/builtin.lua", {
		BoxLayout = node("BoxLayout"), Component = node("Component"), Button = node("Button"),
		TextView = node("TextView"), ImageView = node("ImageView"),
		type = { Orientation = { Horizontal = "H" } },
	})
	stub_module("::/gui/main/styleutil.tl", { makeStyle = function(t) return t end })
	stub_module("::/gui/main/free_cam_options.tl", { FreeCamOptions = "FREECAM" })
	drv = { S = { cutscene = nil }, shots = {} }
	drv.screenshot = function(scale) drv.shots[#drv.shots + 1] = scale return "shot" end
	stub_module("square_photo_mode::/photo_mode/gui/pm_driver.lua", drv)
	stub_module("square_photo_mode::/photo_mode/gui/pm_lens.lua", { stopFromBar = function() lensStops = lensStops + 1 end })
	stub_module("square_photo_mode::/photo_mode/pm_core.lua", {
		log = function(m) logs[#logs + 1] = m end,
		fmt = function(p, ...) return string.format(p, ...) end,
	})
	set_global("api", {
		gui = { StyleSheet = { new = function() return {} end } },
		type = { Vec4f = { new = function(...) return { ... } end } },
	})
	if opts.badStyle then set_global("api", {}) end
	B = ug_require "square_photo_mode::/photo_mode/gui/pm_bar.script.lua"
end

local function render()
	steps = {}
	return B.Replacement.fn({ getGameContext = "ctx" })
end

local function step()
	for __, f in ipairs(steps) do f() end
end

local function kids(root) return root.p.children end

test("round 18: the replacement registers our recipe for the base FreeCamOptions", function()
	setup()
	local api0 = { ReplaceRecipe = function(a, b) replaced = { a, b } end }
	B.doReplaceFn(api0)
	eq(replaced[1], "FREECAM")
	eq(replaced[2], B.Replacement)
	eq(type(data), "function")
	eq(data().doReplaceFn, B.doReplaceFn)
end)

test("round 18: outside a cutscene only the original; while one plays the bar; it goes again after", function()
	setup()
	local root = render()
	eq(kids(root)[1], original)
	eq(kids(root)[2], nil, "no bar")
	eq(original.param.getGameContext, "ctx", "the original gets its params")
	drv.S.cutscene = { kind = "lens" }
	step()
	eq(state.value, true, "the step asks for a render")
	root = render()
	local bar = kids(root)[2]
	ok(bar ~= nil, "the bar")
	-- outer Component > BoxLayout > panel Component > BoxLayout: icon, gap, 1x, gap, 2x, gap, 4x, gap, Stop
	local row = bar.p.layout.p.children[1].p.layout.p.children
	local labels = {}
	for __, n in ipairs(row) do
		if n.kind == "Button" then labels[#labels + 1] = n.p.content.p.text end
	end
	eq(table.concat(labels, ","), "1x,2x,4x,Stop")
	for __, n in ipairs(row) do
		if n.kind == "Button" then
			ok(type(n.p.meta.tooltip) == "string" and #n.p.meta.tooltip > 10, "tooltip")
			eq(n.p.meta.class, "secondary", "the base outlined button, no rule of ours")
			n.p.onClick()
		end
	end
	eq(table.concat(drv.shots, ","), "1,2,4")
	eq(lensStops, 1)
	drv.S.cutscene = nil
	step()
	eq(state.value, false)
	eq(kids(render())[2], nil)
end)

test("round 18: an error building the bar keeps the original", function()
	setup({ badStyle = true })
	drv.S.cutscene = { kind = "lens" }
	render()
	step()
	local root = render()
	eq(kids(root)[1], original)
	eq(kids(root)[2], nil, "the bar left out")
end)
