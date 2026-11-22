--[[
	lune run tools/inspect_place <place.rbxl | model.rbxm> [report.md]

	Reads a Roblox place (or model) file and writes a Markdown report of what is in it, set against
	what this repository provides (the Liège map, its Ambience lighting, the LiegeNPCs characters and
	their markers). Used to compare a game made in Studio with the generated assets.

	Read-only: it never writes to the place file.
]]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local path = process.args[1] or error("usage: lune run tools/inspect_place <file.rbxl|file.rbxm> [report.md]")
local outPath = process.args[2]
local bytes = fs.readFile(path)

local roots, isPlace = {}, string.match(path, "%.rbxlx?$") ~= nil
if isPlace then
	local game = roblox.deserializePlace(bytes)
	for _, s in game:GetChildren() do
		table.insert(roots, s)
	end
else
	roots = roblox.deserializeModel(bytes)
end

local out = {}
local function w(...)
	table.insert(out, string.format(...))
end
local function get(inst, prop)
	local ok, v = pcall(function() return inst[prop] end)
	return ok and v or nil
end
local function fullName(inst)
	local parts = {}
	while inst and inst.ClassName ~= "DataModel" do
		table.insert(parts, 1, inst.Name)
		inst = inst.Parent
	end
	return table.concat(parts, ".")
end
local function count(root, pred)
	local n = 0
	for _, d in root:GetDescendants() do
		if pred(d) then n += 1 end
	end
	return n
end
local function isPart(d) return d:IsA("BasePart") end
local function lines(src) return select(2, string.gsub(src or "", "\n", "")) + 1 end

local all = {}
for _, r in roots do
	table.insert(all, r)
	for _, d in r:GetDescendants() do
		table.insert(all, d)
	end
end

w("# Place report: %s\n", path)

---------------------------------------------------------------- overview
local classCount = {}
for _, d in all do
	classCount[d.ClassName] = (classCount[d.ClassName] or 0) + 1
end
local parts = 0
for _, d in all do
	if d:IsA("BasePart") then parts += 1 end
end
w("## Overview\n")
w("- %d instances, %d parts (%d MeshPart, %d UnionOperation, %d Part, %d WedgePart)", #all, parts,
	classCount.MeshPart or 0, classCount.UnionOperation or 0, classCount.Part or 0, classCount.WedgePart or 0)
w("- %d Humanoids, %d scripts (%d Script, %d LocalScript, %d ModuleScript), %d Tools, %d Animations, %d Sounds",
	classCount.Humanoid or 0, (classCount.Script or 0) + (classCount.LocalScript or 0) + (classCount.ModuleScript or 0),
	classCount.Script or 0, classCount.LocalScript or 0, classCount.ModuleScript or 0, classCount.Tool or 0,
	classCount.Animation or 0, classCount.Sound or 0)
w("- %d PointLights / SpotLights / SurfaceLights", (classCount.PointLight or 0) + (classCount.SpotLight or 0) + (classCount.SurfaceLight or 0))

if isPlace then
	local ws = roots[1] and roots[1].Parent and roots[1].Parent:FindFirstChildOfClass("Workspace")
	for _, r in roots do
		if r.ClassName == "Workspace" then ws = r end
	end
	if ws then
		w("- Workspace: StreamingEnabled = %s", tostring(get(ws, "StreamingEnabled")))
	end
	for _, r in roots do
		if r.ClassName == "StarterPlayer" then
			local avatar = get(r, "GameSettingsAvatar")
			w("- Player avatar type (StarterPlayer.GameSettingsAvatar): %s", avatar and tostring(avatar) or "not stored in this file")
		end
	end
end
w("")

---------------------------------------------------------------- top-level contents
w("## Top-level contents\n")
w("| Where | Name | Class | Parts | Notes |")
w("|---|---|---|---|---|")
local entries = {}
for _, r in roots do
	if isPlace then
		for _, c in r:GetChildren() do
			table.insert(entries, { r.Name, c })
		end
	else
		table.insert(entries, { "(file)", r })
	end
end
for _, e in entries do
	local r, c = { Name = e[1] }, e[2]
	do
		local n = count(c, isPart) + (c:IsA("BasePart") and 1 or 0)
		local notes = {}
		if c.Name == "Liege1800s" then
			table.insert(notes, "the Liège map from this repo")
			if not c:FindFirstChild("Ambience") then table.insert(notes, "**no Ambience folder (older copy)**") end
			if not c:FindFirstChild("NPCMarkers") then table.insert(notes, "**no NPCMarkers (older copy)**") end
		end
		if c.Name == "LiegeNPCs" then table.insert(notes, "the NPC templates from this repo (" .. tostring(c:GetAttribute("Rig")) .. ")") end
		local unions = count(c, function(d) return d.ClassName == "UnionOperation" end)
		local meshes = count(c, function(d) return d.ClassName == "MeshPart" end)
		if unions > 0 then table.insert(notes, unions .. " unions") end
		if meshes > 0 then table.insert(notes, meshes .. " meshparts") end
		local hums = count(c, function(d) return d:IsA("Humanoid") end) + (c:FindFirstChildOfClass("Humanoid") and 0 or 0)
		if hums > 0 then table.insert(notes, hums .. " humanoids") end
		if n > 0 or #notes > 0 or c:IsA("LuaSourceContainer") then
			table.insert(out, string.format("| %s | %s | %s | %d | %s |", r.Name, c.Name, c.ClassName, n, table.concat(notes, ", ")))
		end
	end
end
w("")

---------------------------------------------------------------- characters
w("## Characters (models with a Humanoid)\n")
local chars = {}
for _, d in all do
	if d:IsA("Model") and d:FindFirstChildOfClass("Humanoid") then table.insert(chars, d) end
end
if #chars == 0 then
	w("None.\n")
else
	w("| Path | Rig | Parts | Ours? | Animate script | Animations inside |")
	w("|---|---|---|---|---|---|")
	local shown = 0
	for _, m in chars do
		shown += 1
		if shown > 80 then
			w("| … %d more | | | | | |", #chars - 80)
			break
		end
		local hum = m:FindFirstChildOfClass("Humanoid")
		local anims = {}
		for _, d in m:GetDescendants() do
			if d:IsA("Animation") then table.insert(anims, tostring(get(d, "AnimationId"))) end
		end
		w("| %s | %s | %d | %s | %s | %s |", fullName(m), tostring(get(hum, "RigType")):gsub("Enum.HumanoidRigType.", ""), count(m, isPart),
			m:GetAttribute("NPCId") and "yes" or "no", m:FindFirstChild("Animate") and "yes" or "no", #anims > 0 and table.concat(anims, " ", 1, math.min(#anims, 4)) or "")
	end
	w("")
end

---------------------------------------------------------------- tools and weapons
w("## Tools\n")
local tools = {}
for _, d in all do
	if d:IsA("Tool") then table.insert(tools, d) end
end
if #tools == 0 then
	w("None.\n")
else
	w("| Path | Handle | Parts | Scripts |")
	w("|---|---|---|---|")
	for _, t in tools do
		w("| %s | %s | %d | %d |", fullName(t), t:FindFirstChild("Handle") and "yes" or "no", count(t, isPart),
			count(t, function(d) return d:IsA("LuaSourceContainer") end))
	end
	w("")
end

---------------------------------------------------------------- lighting
if isPlace then
	for _, r in roots do
		if r.ClassName == "Lighting" then
			w("## Lighting\n")
			for _, p in { "Technology", "ClockTime", "Brightness", "Ambient", "OutdoorAmbient", "FogEnd", "GlobalShadows", "EnvironmentDiffuseScale" } do
				local v = get(r, p)
				if v ~= nil then w("- %s = %s", p, tostring(v)) end
			end
			local fx = {}
			for _, c in r:GetChildren() do
				table.insert(fx, c.Name .. " (" .. c.ClassName .. ")")
			end
			w("- Children: %s", #fx > 0 and table.concat(fx, ", ") or "none")
			w("")
		end
	end
end

---------------------------------------------------------------- scripts
w("## Scripts\n")
local KEYWORDS = {
	"PathfindingService", "Animator", "LoadAnimation", "ProximityPrompt", "Raycast", "GetPartBoundsInBox", "Touched",
	"TweenService", "RemoteEvent", "DataStore", "Lighting", "Humanoid", "NPC", "Boss", "Arena", "Apache", "NPCMarkers",
	"LiegeNPCs", "Ambience", "CollectionService", "SetNetworkOwner", "PhysicsService",
}
local scripts = {}
for _, d in all do
	if d:IsA("LuaSourceContainer") then table.insert(scripts, d) end
end
if #scripts == 0 then
	w("None.\n")
else
	w("| Path | Class | Lines | Uses |")
	w("|---|---|---|---|")
	for _, s in scripts do
		local src = get(s, "Source") or ""
		local hits = {}
		for _, k in KEYWORDS do
			if string.find(src, k, 1, true) then table.insert(hits, k) end
		end
		w("| %s | %s | %d | %s |", fullName(s), s.ClassName, lines(src), table.concat(hits, ", "))
	end
	w("")
end

local report = table.concat(out, "\n")
if outPath then
	fs.writeFile(outPath, report)
	print("wrote " .. outPath)
else
	print(report)
end
