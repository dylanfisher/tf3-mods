recordDef = true

-- Full Refund Window shared types. Every global name is prefixed FullRefund (globals are shared by
-- all loaded mods). Editor copy: tealdef/refund/refund_types.d.tl (keep both identical).

--- One recently built player object, its share of the build cost and build game time (ms).
--- Constructions are keyed by entity id (e). Street/track segments are keyed by geometry (k, g):
--- their entity ids are not known after a build (p[3] and old2new are empty for streets).
global record FullRefundEntry
	e : integer           -- construction entity id (nil for a segment)
	k : string            -- segment key "e:x0,y0,z0|x1,y1,z1" (0.1 m, order-independent; nil for a construction)
	g : {number}          -- segment endpoints x0,y0,z0,x1,y1,z1 (canonical order), matched with a tolerance
	c : integer
	t : integer
end

--- Geometry of one street/track segment, read from a proposal or the live BaseEdge.
global record FullRefundEdge
	p0 : {number}         -- {x, y, z}
	p1 : {number}         -- {x, y, z}
	len : number          -- length used to split the cost (tangent or chord)
end

--- A pure removal seen in onPreBuildProposal, waiting for its onPostBuildProposal.
global record FullRefundPending
	key : string          -- fingerprint of the removed entities (count + ids), matched in post
	owed : integer        -- sum of the ledger costs of the removed entities
	hits : integer        -- number of ledger entries owed
	balance : integer     -- player balance before the apply
	t : integer           -- game time of the pre event
	await : boolean       -- post saw no engine refund yet: measure again in the next update
end

--- GameScriptState. Small: only objects built within the refund window are kept.
global record FullRefundState
	v : integer
	ledger : {FullRefundEntry}
	pending : FullRefundPending
	--- credit waiting to be booked on the next update (commands can't be sent mid-build)
	payout : integer
	--- paid cost of ledger entries a rebuild's pre removed; carried onto the rebuild's new objects in post
	carry : integer
end

--- Pure ledger logic. Module: ug_require "/refund/refund_logic.tl" as FullRefundLogic
global record FullRefundLogic
	--- Refund window in seconds for the raw mod param (seconds via mod.json "numbers", or an index).
	windowSeconds : function(raw : any) : number
	--- New or upgraded state (nil / malformed -> empty).
	normalize : function(s : FullRefundState) : FullRefundState
	--- Drops entries older than windowMs (and caps the ledger size). Returns the number dropped.
	prune : function(s : FullRefundState, now : integer, windowMs : integer) : integer
	--- Splits cost over the entities (remainder to the first) and records them at time now.
	add : function(s : FullRefundState, entities : {integer}, cost : integer, now : integer) : {FullRefundEntry}
	--- Removes the entities from the ledger; returns the removed entries.
	take : function(s : FullRefundState, entities : {integer}) : {FullRefundEntry}
	--- Order-independent key of a segment (0.1 m) and its endpoints in canonical order.
	edgeKey : function(p0 : {number}, p1 : {number}) : string, {number}
	--- True when two canonical endpoint lists describe the same segment (either orientation, within tol m).
	sameEdge : function(a : {number}, b : {number}, tol : number) : boolean
	--- Integer shares of cost proportional to the weights (sum == cost; equal split if all weights are 0).
	split : function(weights : {number}, cost : integer) : {integer}
	--- Records segments with a length-proportional share of cost; a segment already in the ledger is replaced.
	addEdges : function(s : FullRefundState, edges : {FullRefundEdge}, cost : integer, now : integer) : {FullRefundEntry}
	--- Removes and returns the ledger entries matching the segments (one entry per segment at most).
	takeEdges : function(s : FullRefundState, edges : {FullRefundEdge}) : {FullRefundEntry}
	--- Sum of the entries' costs within the window (entries older than windowMs are ignored).
	owed : function(entries : {FullRefundEntry}, now : integer, windowMs : integer) : integer, integer
	--- Amount to credit: owed minus what the engine already refunded, never negative.
	credit : function(owed : integer, actualRefund : integer) : integer
	--- Fingerprint of a removal set (order-independent).
	fingerprint : function(entities : {integer}) : string
	--- "add" | "remove" | "rebuild" | "none"
	classify : function(numAdd : integer, numRemove : integer) : string
end

recordDef = false
