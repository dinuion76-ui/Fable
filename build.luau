--[[
	Lune build script:  lune run build
	Writes
	  build/Liege1800s.rbxm          the map as a model (drag into an existing place), with NPCMarkers
	  build/Liege1800s_Preview.rbxl  a standalone place: map, lighting, NPCs standing at their markers
	  build/LiegeNPCs_R15.rbxm       every character as an R15 rig, plus the NPCCatalog module
	  build/LiegeNPCs_R6.rbxm        the same characters as R6 rigs
	  build/parts.json, build/npc_*.json   flat part / marker lists used by tools/ (not committed)
]]
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local generate = require("./src/LiegeMap")
local makeNPCs = require("./src/LiegeNPCs")
local makePlacements = require("./src/LiegeNPCPlacements")
local Core = require("./src/Ambience/AmbienceCore")

local R = {
	Instance = roblox.Instance,
	Vector3 = roblox.Vector3,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	Enum = roblox.Enum,
	UDim2 = roblox.UDim2,
	Font = roblox.Font,
}

local map, stats = generate({
	scripts = {
		core = fs.readFile("src/Ambience/AmbienceCore.luau"),
		server = fs.readFile("src/Ambience/LiegeAmbience.server.luau"),
		client = fs.readFile("src/Ambience/LiegeAmbienceClient.client.luau"),
	},
}, R)

---------------------------------------------------------------- NPC markers (snapped to the floor under them)
local NPCs = makeNPCs(R)
local Placements = makePlacements(R)
local function aabb(part)
	local c = { part.CFrame:GetComponents() }
	local h = { part.Size.X / 2, part.Size.Y / 2, part.Size.Z / 2 }
	local lo, hi = {}, {}
	for axis = 1, 3 do
		local r = 0
		for k = 1, 3 do
			r += math.abs(c[3 + (axis - 1) * 3 + k]) * h[k]
		end
		lo[axis], hi[axis] = c[axis] - r, c[axis] + r
	end
	return lo, hi
end
local solids = {}
for _, d in map:GetDescendants() do
	if d:IsA("BasePart") and d.CanCollide and d.ClassName ~= "WedgePart" then
		local lo, hi = aabb(d)
		table.insert(solids, { lo[1], lo[3], hi[1], hi[3], hi[2] })
	end
end
local function floorAt(x, z, yHint)
	local best
	for _, b in solids do
		if x >= b[1] and x <= b[3] and z >= b[2] and z <= b[4] and b[5] <= yHint + 1 and b[5] >= yHint - 3 then
			if not best or b[5] > best then best = b[5] end
		end
	end
	return best or yHint
end
local markers = Placements.build(floorAt, NPCs.byId)
markers.Parent = map

-- bounds + flat export
local parts = {}
local lo, hi = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
local counts = {}
for _, d in map:GetDescendants() do
	if d:IsA("BasePart") then
		local c = { d.CFrame:GetComponents() }
		local s = d.Size
		local shape = d.ClassName == "WedgePart" and "Wedge" or d.Shape.Name
		counts[shape] = (counts[shape] or 0) + 1
		-- world AABB half extents
		local sz = { s.X / 2, s.Y / 2, s.Z / 2 }
		for axis = 1, 3 do
			local r = 0
			for k = 1, 3 do
				r += math.abs(c[3 + (axis - 1) * 3 + k]) * sz[k]
			end
			lo[axis] = math.min(lo[axis], c[axis] - r)
			hi[axis] = math.max(hi[axis], c[axis] + r)
		end
		local round = function(v) return math.floor(v * 1000 + 0.5) / 1000 end
		for i = 1, 12 do c[i] = round(c[i]) end
		table.insert(parts, {
			k = shape, n = d.Name, c = c, s = { round(s.X), round(s.Y), round(s.Z) },
			col = { math.floor(d.Color.R * 255 + 0.5), math.floor(d.Color.G * 255 + 0.5), math.floor(d.Color.B * 255 + 0.5) },
			t = d.Transparency, m = d.Material.Name, col2 = d.CanCollide,
		})
	end
end

if not fs.isDir("build") then fs.writeDir("build") end
fs.writeFile("build/parts.json", serde.encode("json", parts))
fs.writeFile("build/Liege1800s.rbxm", roblox.serializeModel({ map }))

---------------------------------------------------------------- NPC libraries
local function partList(root)
	local out = {}
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			local c = { d.CFrame:GetComponents() }
			for i = 1, 12 do c[i] = math.floor(c[i] * 1000 + 0.5) / 1000 end
			table.insert(out, {
				k = d.ClassName == "WedgePart" and "Wedge" or d.Shape.Name, n = d.Name, c = c, s = { d.Size.X, d.Size.Y, d.Size.Z },
				col = { math.floor(d.Color.R * 255 + 0.5), math.floor(d.Color.G * 255 + 0.5), math.floor(d.Color.B * 255 + 0.5) },
				t = d.Transparency, m = d.Material.Name, col2 = d.CanCollide,
			})
		end
	end
	return out
end
local libraries, npcStats = {}, {}
for _, rig in { "R15", "R6" } do
	local lib, st = NPCs.library(rig)
	libraries[rig], npcStats[rig] = lib, st
	fs.writeFile("build/LiegeNPCs_" .. rig .. ".rbxm", roblox.serializeModel({ lib }))
	fs.writeFile("build/npc_gallery_" .. rig .. ".json", serde.encode("json", partList(lib)))
end

-- markers as plain data for tools/check_npcs.py
local markerData = { spawns = {}, routes = {}, arenas = {} }
for _, m in markers.Spawns:GetChildren() do
	local x, y, z = m.CFrame.Position.X, m.CFrame.Position.Y - 0.1, m.CFrame.Position.Z
	local npc = m:GetAttribute("NPCType")
	table.insert(markerData.spawns, { name = m.Name, npc = npc, x = x, y = y, z = z, behaviour = m:GetAttribute("Behaviour"),
		route = m:GetAttribute("Route"), scale = (NPCs.byId[npc].body and NPCs.byId[npc].body.scale) or 1 })
end
for _, f in markers.PatrolRoutes:GetChildren() do
	local pts = {}
	for i = 1, #f:GetChildren() do
		local p = f:FindFirstChild(string.format("P%02d", i))
		table.insert(pts, { p.CFrame.Position.X, p.CFrame.Position.Y - 0.1, p.CFrame.Position.Z })
	end
	markerData.routes[f.Name] = { npc = f:GetAttribute("NPCType"), loop = f:GetAttribute("Loop"), points = pts }
end
for _, f in markers.BossArenas:GetChildren() do
	local bs = f.BossSpawn
	local npc = bs:GetAttribute("NPCType")
	local entry = { name = f.Name, boss = npc, x = bs.CFrame.Position.X, y = bs.CFrame.Position.Y - 0.1, z = bs.CFrame.Position.Z,
		scale = NPCs.byId[npc].body.scale, entry = { f.PlayerEntry.CFrame.Position.X, f.PlayerEntry.CFrame.Position.Y - 0.1, f.PlayerEntry.CFrame.Position.Z }, adds = {} }
	if f:FindFirstChild("Reinforcements") then
		for _, a in f.Reinforcements:GetChildren() do
			table.insert(entry.adds, { a.Name, a.CFrame.Position.X, a.CFrame.Position.Y - 0.1, a.CFrame.Position.Z })
		end
	end
	table.insert(markerData.arenas, entry)
end
fs.writeFile("build/npc_markers.json", serde.encode("json", markerData))

-- preview place
local game = roblox.Instance.new("DataModel")
local ws = game:GetService("Workspace")
local li = game:GetService("Lighting")
-- bake the default mood in, so the place already looks right in Studio's edit mode
Core.begin({ Lighting = li, Instance = roblox.Instance, Color3 = roblox.Color3 }).apply(Core.presets.Dusk)
ws.StreamingEnabled = true
ws.StreamingMinRadius = 192
ws.StreamingTargetRadius = 640
local clone = map:Clone()
clone.Parent = ws
local spawn = roblox.Instance.new("SpawnLocation")
spawn.Anchored = true
spawn.Size = roblox.Vector3.new(8, 1, 8)
spawn.CFrame = roblox.CFrame.new(-158, 0.5, -78)
spawn.Transparency = 1
spawn.CanCollide = false
spawn.Neutral = true
spawn.Parent = ws

-- populate the preview: one R15 character per spawn marker and each boss in its arena (HumanoidRootPart anchored)
local preview = roblox.Instance.new("Folder")
preview.Name = "PreviewNPCs"
preview.Parent = ws
local used = {}
local previewCount = 0
local function place(npc, cf)
	local d = NPCs.byId[npc]
	used[npc] = (used[npc] or 0) + 1
	local variant = (used[npc] - 1) % (d.variants or 1) + 1
	local m = NPCs.build(npc, variant, "R15", cf)
	m.HumanoidRootPart.Anchored = true
	m.Parent = preview
	previewCount += 1
end
for _, m in clone.NPCMarkers.Spawns:GetChildren() do
	place(m:GetAttribute("NPCType"), m.CFrame * roblox.CFrame.new(0, -0.1, 0))
end
for _, f in clone.NPCMarkers.BossArenas:GetChildren() do
	place(f.BossSpawn:GetAttribute("NPCType"), f.BossSpawn.CFrame * roblox.CFrame.new(0, -0.1, 0))
end
fs.writeFile("build/npc_preview.json", serde.encode("json", partList(preview)))
local templates = libraries.R15:Clone()
templates.Parent = game:GetService("ServerStorage")
fs.writeFile("build/Liege1800s_Preview.rbxl", roblox.serializePlace(game))

print(string.format("parts %d  (lights %d, smoke %d, signs %d, spawns %d)", stats.parts, stats.lights, stats.smoke, stats.signs, stats.spawns))
for k, v in counts do print("  " .. k, v) end
print(string.format("bounds x[%.1f, %.1f] y[%.1f, %.1f] z[%.1f, %.1f]", lo[1], hi[1], lo[2], hi[2], lo[3], hi[3]))
print(string.format("rbxm %.0f KB, rbxl %.0f KB", #fs.readFile("build/Liege1800s.rbxm") / 1024, #fs.readFile("build/Liege1800s_Preview.rbxl") / 1024))
for _, rig in { "R15", "R6" } do
	local st = npcStats[rig]
	print(string.format("NPCs %s: %d models, %d parts (max %d per model), %.0f KB", rig, st.models, st.parts, st.maxParts,
		#fs.readFile("build/LiegeNPCs_" .. rig .. ".rbxm") / 1024))
end
print(string.format("markers: %d spawns, %d routes, %d arenas; preview NPCs: %d", #markerData.spawns, (function()
	local n = 0
	for _ in markerData.routes do n += 1 end
	return n
end)(), #markerData.arenas, previewCount))
