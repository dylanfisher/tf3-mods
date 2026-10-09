recordDef = true

-- Industry Flows shared contract: the plain records the engine reads (flows_gather.tl) produce, the
-- pure model (flows_model.tl) turns into views, and the GUI (gui/flows_window.script.tl) renders.
-- Loaded as module "industry_flows.industry_flows_types" (every content/**/*.d.tl; tools/tealrt.py
-- def_modules). tealdef/industry_flows/industry_flows_types.d.tl is a byte-for-byte editor copy
-- (make check flags drift). Never `require` this module from a .tl/.lua file: the types come in via
-- tealdef/square_industry_flows_def.d.tl. Every global name is prefixed IndustryFlows (globals are
-- shared by all loaded mods).
-- Plain numbers, strings and tables only (no Vec3f userdata), so useStepStateTimer's deepEquals can
-- compare two polls (.cache/game/base/content/gui/main/engine_react_util.tl:126-145).

--- One industry on the map, as read by flows_gather.readWorld (one per INDUSTRY entity with a
--- STOCK_LIST). Cargo lists hold CargoTypeIds; their order does not matter (the model sorts).
global record IndustryFlowsIndustry
	entity : integer          -- the industry (stock-list) entity
	typeKey : string          -- CONSTRUCTION.fileName of its construction, e.g.
	                          -- "::/industries/fishing_grounds/fishing_grounds.con"; "" if unknown
	pos : {number}            -- {x, y, z}: top centre of the bounding box; nil without BOUNDING_VOLUME
	inputs : {integer}        -- cargos consumed by a non-zero rule input (industry_util.tl:609-614)
	outputs : {integer}       -- cargos produced by a rule (industry_util.tl:615-618)
	inputStocks : {integer}   -- cargos with an InputStock (counterpart test, industry_util.tl:640)
	outputStocks : {integer}  -- cargos with an OutputStock
end

--- One town, a possible consumer of a selected industry's outputs.
global record IndustryFlowsTown
	entity : integer
	pos : {number}            -- {x, y, z} like IndustryFlowsIndustry.pos; nil if unknown
	needs : {integer}         -- TOWN.cargoNeeds flattened in order (town_util.tl:1897-1907 takes the
	                          -- first one an industry produces)
end

--- One engine read: everything the model needs, no userdata.
global record IndustryFlowsWorld
	industries : {IndustryFlowsIndustry}
	towns : {IndustryFlowsTown}
	typeNames : {string : string}  -- typeKey -> localized construction name (description.name); a
	                               -- missing / empty entry falls back to the prettified folder name
	cargoNames : {integer : string} -- CargoTypeId -> localized cargo name, for every input / output
	                                -- cargo of an industry (search matches them); may be missing
end

--- One industry type (all industries sharing a construction fileName).
global record IndustryFlowsType
	key : string              -- CONSTRUCTION.fileName
	name : string             -- display name (localized, or the prettified folder name)
	count : integer           -- industries of this type on the map
	entities : {integer}      -- their entities, ascending
	inputs : {integer}        -- cargos any of them consumes (union of IndustryFlowsIndustry.inputs), ascending
	outputs : {integer}       -- cargos any of them produces (union of .outputs), ascending
	cargoNames : {string}     -- names of inputs then outputs (world.cargoNames; unknown ones left out)
end

--- Which arrows to show. Potential = links with no cargo moving (faded, still arrows); when it is
--- off only active links are kept.
global record IndustryFlowsToggles
	inputs : boolean          -- suppliers -> selected industries
	outputs : boolean         -- selected industries -> consumers (industries and towns)
	potential : boolean
end

--- Function the model asks for actual cargo flow: cargo_util.getCargoFlowCount
--- (.cache/game/base/content/gui/main/cargo_util.tl:976-986). Tests pass a fake.
global type IndustryFlowsFlowCountFn = function(fromEntity : integer, toEntity : integer, cargo : integer, toTown : boolean) : integer

--- One arrow: the base industry window's CargoFlowData (industry.tl:204-226) plus its direction.
global record IndustryFlowsLink
	fromEntity : integer   -- source stock-list entity (industry) of the cargo
	toEntity : integer     -- target entity (industry or town)
	from : {number}        -- {x, y, z}: top centre of the source's bounding box
	to : {number}          -- {x, y, z}: top centre of the target's bounding box
	cargo : integer        -- CargoTypeId
	input : boolean        -- true: a supplier delivering to a selected industry (Suppliers3D colours);
	                       -- false: a selected industry delivering to a consumer (Consumers3D colours)
	toTown : boolean       -- the consumer is a town
	active : boolean       -- cargo moved along this link in the last year (flow count > 0)
end

--- One poll for the selected industry types.
global record IndustryFlowsView
	typeKeys : {string}            -- the selected type keys, sorted
	industries : integer           -- industries of the selected types on the map
	links : {IndustryFlowsLink}    -- at most IndustryFlowsModel.MAX_LINKS: active first, then by entities
	total : integer                -- links kept by the toggles (before the cap)
	active : integer               -- of those, links with cargo moving
	drawn : integer                -- #links (after the cap)
end

--- One row of the panel's type list (phase 3): a matching type with its checkbox state.
global record IndustryFlowsTypeRow
	key : string              -- CONSTRUCTION.fileName
	name : string             -- display name
	count : integer           -- industries of this type on the map
	inputs : {integer}        -- IndustryFlowsType.inputs (cargo icons left of the arrow)
	outputs : {integer}       -- IndustryFlowsType.outputs (cargo icons right of the arrow)
	selected : boolean
end

--- The panel's type list for one search query.
global record IndustryFlowsTypeList
	rows : {IndustryFlowsTypeRow}  -- the types matching the query, model.search order
	selectedCount : integer        -- selected keys in total (shown or not)
	hiddenSelected : integer       -- selected keys without a row: filtered out by the query, or no
	                               -- longer on the map (they stay selected)
end

--- What the summary line says (the GUI owns the strings).
global enum IndustryFlowsSummaryState
	"empty"     -- nothing selected
	"loading"   -- selected, but no view yet
	"none"      -- none of the selected types on the map
	"links"     -- industries found: show the counts
end

--- Inputs for the summary lines: "{industries} industries · {total} links · {active} active" and,
--- when capped, "Showing {drawn} of {total} (active first)".
global record IndustryFlowsSummary
	state : IndustryFlowsSummaryState
	industries : integer
	total : integer
	active : integer
	drawn : integer
	capped : boolean          -- drawn < total (MAX_LINKS reached)
end

--- What the panel remembers for the rest of the session (GUI memory only, never saved).
global record IndustryFlowsPanelState
	query : string
	selection : {string : boolean}
	toggles : IndustryFlowsToggles
end

--- Pure model (flows_model.tl): no api.*, unit-tested in tests/square_industry_flows/.
global record IndustryFlowsModel
	MAX_LINKS : integer
	--- "::/industries/fishing_grounds/fishing_grounds.con" -> "Fishing Grounds".
	prettifyKey : function(key : string) : string
	--- The localized name when usable (non-empty, not a raw "SOME_KEY_NAME" string), else prettifyKey.
	displayName : function(key : string, localizedName : string) : string
	--- Industries grouped by typeKey (unknown "" skipped), sorted by name (case-insensitive), then key.
	groupTypes : function(world : IndustryFlowsWorld) : {IndustryFlowsType}
	--- Case-insensitive plain substring match over name, key and input / output cargo names;
	--- empty / blank query = all.
	search : function(types : {IndustryFlowsType}, query : string) : {IndustryFlowsType}
	--- A fresh selection set from a list of keys.
	newSelection : function(keys? : {string}) : {string : boolean}
	--- A new set with key flipped (the input set is not changed).
	toggleSelected : function(selection : {string : boolean}, key : string) : {string : boolean}
	--- The selected keys, sorted.
	selectedKeys : function(selection : {string : boolean}) : {string}
	--- Inputs, Outputs and Potential all on.
	defaultToggles : function() : IndustryFlowsToggles
	--- A copy of toggles with one field ("inputs", "outputs" or "potential") set; others unchanged.
	withToggle : function(toggles : IndustryFlowsToggles, name : string, on : boolean) : IndustryFlowsToggles
	--- The panel's start state: empty query, nothing selected, default toggles.
	newPanelState : function() : IndustryFlowsPanelState
	--- A deep copy (selection and toggles are fresh tables).
	copyPanelState : function(state : IndustryFlowsPanelState) : IndustryFlowsPanelState
	--- Rows for the types matching query (model.search), with checkbox state and hidden selections.
	typeList : function(types : {IndustryFlowsType}, query : string, selection : {string : boolean}) : IndustryFlowsTypeList
	--- Summary inputs for a view of the given selection (view nil = not read yet).
	summary : function(view : IndustryFlowsView, selection : {string : boolean}) : IndustryFlowsSummary
	--- All links of every industry of the selected types, filtered by the toggles, de-duplicated,
	--- ordered (active first, then fromEntity, toEntity, cargo) and capped at MAX_LINKS.
	buildView : function(world : IndustryFlowsWorld, selection : {string : boolean}, toggles : IndustryFlowsToggles, flowCount : IndustryFlowsFlowCountFn) : IndustryFlowsView
end

--- Engine reads (flows_gather.tl), GUI thread, read-only.
global record IndustryFlowsGather
	--- Construction fileName of the industry (stock-list) entity, "" if unknown.
	typeOf : function(industryEntity : integer) : string
	--- Localized construction name (description.name) of a type key, nil if not found. Cached.
	typeName : function(typeKey : string) : string
	--- Localized cargo name (CargoType.name) of a CargoTypeId, nil if not found. Cached.
	cargoName : function(cargo : integer) : string
	--- All industries and towns as plain records, plus the names of the types and cargos found.
	readWorld : function() : IndustryFlowsWorld
	--- cargo_util.getCargoFlowCount, the model's flowCount.
	flowCount : IndustryFlowsFlowCountFn
end

recordDef = false
