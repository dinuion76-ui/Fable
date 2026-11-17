--[[
	Lune build script:  lune run build
	Writes
	  build/Liege1800s.rbxm          the map as a model (drag into an existing place)
	  build/Liege1800s_Preview.rbxl  a standalone place with the lighting preset applied
	  build/parts.json              flat part list used by tools/preview
]]
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local generate = require("./src/LiegeMap")
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
fs.writeFile("build/Liege1800s_Preview.rbxl", roblox.serializePlace(game))

print(string.format("parts %d  (lights %d, smoke %d, signs %d, spawns %d)", stats.parts, stats.lights, stats.smoke, stats.signs, stats.spawns))
for k, v in counts do print("  " .. k, v) end
print(string.format("bounds x[%.1f, %.1f] y[%.1f, %.1f] z[%.1f, %.1f]", lo[1], hi[1], lo[2], hi[2], lo[3], hi[3]))
print(string.format("rbxm %.0f KB, rbxl %.0f KB", #fs.readFile("build/Liege1800s.rbxm") / 1024, #fs.readFile("build/Liege1800s_Preview.rbxl") / 1024))
