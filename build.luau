--[[
	Lune build script:  lune run build
	Writes
	  build/LiegeDuel.rbxm           the 250 x 250 duel map as one model (drag into an existing place)
	  build/LiegeDuel_Preview.rbxl   a standalone place: the map, its lighting, a spawn on each side and two
	                                 duellists for scale; press Play to walk it
	  build/LiegeNPCs_R15.rbxm       every NPC as an R15 rig, plus the NPCCatalog module
	  build/LiegeNPCs_R6.rbxm        the same NPCs as R6 rigs
	  build/parts.json, build/npc_gallery_*.json   flat part lists used by tools/ (not committed)
]]
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local generate = require("./src/LiegeDuel")
local makeNPCs = require("./src/LiegeNPCs")
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

---------------------------------------------------------------- flat part list (for tools/check_duel.py and tools/preview)
local function partList(root)
	local out = {}
	local lo, hi = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
	local counts = {}
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			local c = { d.CFrame:GetComponents() }
			local s = d.Size
			local shape = d.ClassName == "WedgePart" and "Wedge" or d.Shape.Name
			counts[shape] = (counts[shape] or 0) + 1
			local h = { s.X / 2, s.Y / 2, s.Z / 2 }
			for axis = 1, 3 do
				local r = 0
				for k = 1, 3 do
					r += math.abs(c[3 + (axis - 1) * 3 + k]) * h[k]
				end
				lo[axis] = math.min(lo[axis], c[axis] - r)
				hi[axis] = math.max(hi[axis], c[axis] + r)
			end
			for i = 1, 12 do c[i] = math.floor(c[i] * 1000 + 0.5) / 1000 end
			table.insert(out, {
				k = shape, n = d.Name, c = c, s = { s.X, s.Y, s.Z },
				col = { math.floor(d.Color.R * 255 + 0.5), math.floor(d.Color.G * 255 + 0.5), math.floor(d.Color.B * 255 + 0.5) },
				t = d.Transparency, m = d.Material.Name, col2 = d.CanCollide, q = d.CanQuery,
				team = d:GetAttribute("Team"), slot = d:GetAttribute("Slot"),
				path = d.Parent.Name,
			})
		end
	end
	return out, lo, hi, counts
end

if not fs.isDir("build") then fs.writeDir("build") end
local parts, lo, hi, counts = partList(map)
fs.writeFile("build/parts.json", serde.encode("json", parts))
fs.writeFile("build/LiegeDuel.rbxm", roblox.serializeModel({ map }))

---------------------------------------------------------------- NPC libraries (independent of the map)
local NPCs = makeNPCs(R)
local npcStats = {}
for _, rig in { "R15", "R6" } do
	local lib, st = NPCs.library(rig)
	npcStats[rig] = st
	fs.writeFile("build/LiegeNPCs_" .. rig .. ".rbxm", roblox.serializeModel({ lib }))
	fs.writeFile("build/npc_gallery_" .. rig .. ".json", serde.encode("json", (partList(lib))))
end

---------------------------------------------------------------- preview place
local game = roblox.Instance.new("DataModel")
local ws = game:GetService("Workspace")
local li = game:GetService("Lighting")
-- bake the default mood in, so the place already looks right in Studio's edit mode
Core.begin({ Lighting = li, Instance = roblox.Instance, Color3 = roblox.Color3 }).apply(Core.presets.Dusk)
local clone = map:Clone()
clone.Parent = ws
-- one neutral spawn on each side (players land on either at random), and a duellist on each slot 1 for scale
local duellists = { Red = "ApacheKnife", Blue = "ApacheGunman" }
for _, m in clone.Markers.Spawns:GetChildren() do
	if m:GetAttribute("Slot") == 1 then
		local sp = roblox.Instance.new("SpawnLocation")
		sp.Name = "Spawn_" .. m:GetAttribute("Team")
		sp.Anchored = true
		sp.Size = roblox.Vector3.new(6, 0.2, 6)
		sp.CFrame = m.CFrame
		sp.Transparency = 1
		sp.CanCollide = false
		sp.Neutral = true
		sp.Duration = 0
		sp.Parent = ws
		local npc = NPCs.build(duellists[m:GetAttribute("Team")], 1, "R15", m.CFrame * roblox.CFrame.new(-6, -0.1, 0))
		npc.HumanoidRootPart.Anchored = true
		npc.Parent = ws
	end
end
fs.writeFile("build/LiegeDuel_Preview.rbxl", roblox.serializePlace(game))

---------------------------------------------------------------- report
print(string.format("duel map: %d parts (lights %d, signs %d)", stats.parts, stats.lights, stats.signs))
for k, v in counts do print("  " .. k, v) end
print(string.format("bounds x[%.1f, %.1f] y[%.1f, %.1f] z[%.1f, %.1f]", lo[1], hi[1], lo[2], hi[2], lo[3], hi[3]))
print(string.format("rbxm %.0f KB, preview rbxl %.0f KB", #fs.readFile("build/LiegeDuel.rbxm") / 1024, #fs.readFile("build/LiegeDuel_Preview.rbxl") / 1024))
for _, rig in { "R15", "R6" } do
	local st = npcStats[rig]
	print(string.format("NPCs %s: %d models, %d parts (max %d per model)", rig, st.models, st.parts, st.maxParts))
end
