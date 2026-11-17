--[[
	lune run tools/test_npcs      (run `lune run build` first)

	Loads the shipped NPC files and checks every character the way Roblox will see it:
	  - the body parts, joints and attachments a stock R15 / R6 animation expects
	  - every joint already agrees with where the parts sit, so nothing snaps when physics starts
	  - every part is held to the HumanoidRootPart by a joint (nothing falls off)
	  - HipHeight puts the feet on the floor
	  - clothing and props are massless and invisible to collisions, raycasts and Touched
	  - the NPCCatalog module compiles and lists every model
	  - every NPC marker in the map names a character that exists
	It cannot check how anything looks; that needs Studio.
]]
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local failures, checks = 0, 0
local function check(name, cond, detail)
	checks += 1
	if not cond then
		failures += 1
		print("  FAIL " .. name .. (detail and ("  -> " .. tostring(detail)) or ""))
	end
	return cond
end
local function cfDiff(a, b)
	local ca, cb = { a:GetComponents() }, { b:GetComponents() }
	local d = 0
	for i = 1, 12 do
		d = math.max(d, math.abs(ca[i] - cb[i]))
	end
	return d
end

local R15_BODY = { "HumanoidRootPart", "LowerTorso", "UpperTorso", "Head", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm",
	"RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot" }
local R6_BODY = { "HumanoidRootPart", "Torso", "Head", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }
local R15_JOINTS = { Root = "LowerTorso", Waist = "UpperTorso", Neck = "Head", LeftShoulder = "LeftUpperArm", LeftElbow = "LeftLowerArm",
	LeftWrist = "LeftHand", RightShoulder = "RightUpperArm", RightElbow = "RightLowerArm", RightWrist = "RightHand", LeftHip = "LeftUpperLeg",
	LeftKnee = "LeftLowerLeg", LeftAnkle = "LeftFoot", RightHip = "RightUpperLeg", RightKnee = "RightLowerLeg", RightAnkle = "RightFoot" }
local R6_JOINTS = { -- name = { holder, Part1, rotation matrix of C0 and C1 }
	RootJoint = { "HumanoidRootPart", "Torso", { -1, 0, 0, 0, 0, 1, 0, 1, 0 } },
	Neck = { "Torso", "Head", { -1, 0, 0, 0, 0, 1, 0, 1, 0 } },
	["Right Shoulder"] = { "Torso", "Right Arm", { 0, 0, 1, 0, 1, 0, -1, 0, 0 } },
	["Left Shoulder"] = { "Torso", "Left Arm", { 0, 0, -1, 0, 1, 0, 1, 0, 0 } },
	["Right Hip"] = { "Torso", "Right Leg", { 0, 0, 1, 0, 1, 0, -1, 0, 0 } },
	["Left Hip"] = { "Torso", "Left Leg", { 0, 0, -1, 0, 1, 0, 1, 0, 0 } },
}
local ACCESSORY = {
	R15 = { Head = { "HatAttachment", "HairAttachment", "FaceFrontAttachment", "FaceCenterAttachment" },
		UpperTorso = { "NeckAttachment", "BodyFrontAttachment", "BodyBackAttachment" }, LowerTorso = { "WaistCenterAttachment" },
		RightHand = { "RightGripAttachment" }, LeftHand = { "LeftGripAttachment" }, HumanoidRootPart = { "RootAttachment" } },
	R6 = { Head = { "HatAttachment", "HairAttachment", "FaceFrontAttachment", "FaceCenterAttachment" },
		Torso = { "NeckAttachment", "BodyFrontAttachment", "BodyBackAttachment", "WaistCenterAttachment" },
		["Right Arm"] = { "RightGripAttachment" }, ["Left Arm"] = { "LeftGripAttachment" }, HumanoidRootPart = { "RootAttachment" } },
}

local ids = {}
for _, rig in { "R15", "R6" } do
	print(rig)
	local root = roblox.deserializeModel(fs.readFile("build/LiegeNPCs_" .. rig .. ".rbxm"))[1]
	check(rig .. " root folder", root and root.Name == "LiegeNPCs" and root:GetAttribute("Rig") == rig)

	-- catalogue
	local catalogSrc = root:FindFirstChild("NPCCatalog") and root.NPCCatalog.Source
	local okCompile = check(rig .. " NPCCatalog compiles", catalogSrc and pcall(luau.compile, catalogSrc))
	local catalog = okCompile and luau.load(catalogSrc)() or {}

	local models, worst, least = 0, 0, math.huge
	for _, m in root:GetDescendants() do
		if m:IsA("Model") and m:FindFirstChildOfClass("Humanoid") then
			models += 1
			local name = rig .. "/" .. m.Name
			local id = m:GetAttribute("NPCId")
			ids[id] = true
			local entry = catalog[id]
			check(name .. " in catalogue", entry and table.find(entry.Models, m.Name) ~= nil)
			check(name .. " attributes", id and m:GetAttribute("Category") and m:GetAttribute("Rig") == rig and m:GetAttribute("DisplayName"))
			check(name .. " streams as one piece", m.ModelStreamingMode == roblox.Enum.ModelStreamingMode.Atomic)
			check(name .. " tagged", m:HasTag("LiegeNPC"))

			local hum = m:FindFirstChildOfClass("Humanoid")
			check(name .. " rig type", hum.RigType == (rig == "R6" and roblox.Enum.HumanoidRigType.R6 or roblox.Enum.HumanoidRigType.R15))
			check(name .. " animator", hum:FindFirstChildOfClass("Animator") ~= nil)
			local hrp = m:FindFirstChild("HumanoidRootPart")
			check(name .. " primary part", m.PrimaryPart == hrp)

			-- body parts
			local body = {}
			for _, n in rig == "R6" and R6_BODY or R15_BODY do
				local p = m:FindFirstChild(n)
				if check(name .. " has " .. n, p and p:IsA("BasePart")) then
					body[n] = p
					check(name .. " " .. n .. " not anchored", not p.Anchored)
				end
			end

			-- joints
			local joints, adj = {}, {}
			local function link(a, b)
				adj[a] = adj[a] or {}
				adj[b] = adj[b] or {}
				table.insert(adj[a], b)
				table.insert(adj[b], a)
			end
			local partCount = 0
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") then partCount += 1 end
				if d:IsA("JointInstance") then
					table.insert(joints, d)
					if d.Part0 and d.Part1 then
						link(d.Part0, d.Part1)
						local err = cfDiff(d.Part0.CFrame * d.C0, d.Part1.CFrame * d.C1)
						check(name .. " joint " .. d.Name .. " (" .. d.Parent.Name .. ") agrees with part positions", err < 2e-3, err)
					else
						check(name .. " joint " .. d.Name .. " has both parts", false)
					end
				end
			end
			worst = math.max(worst, partCount)
			least = math.min(least, partCount)
			check(name .. " part budget", partCount <= 80, partCount)

			if rig == "R15" then
				for jn, p1 in R15_JOINTS do
					local j = body[p1] and body[p1]:FindFirstChild(jn)
					if check(name .. " Motor6D " .. jn, j and j:IsA("Motor6D")) then
						local a0 = j.Part0:FindFirstChild(jn .. "RigAttachment")
						local a1 = j.Part1:FindFirstChild(jn .. "RigAttachment")
						check(name .. " " .. jn .. " rig attachments", a0 and a1 and cfDiff(a0.CFrame, j.C0) < 1e-4 and cfDiff(a1.CFrame, j.C1) < 1e-4)
					end
				end
			else
				for jn, spec in R6_JOINTS do
					local j = body[spec[1]] and body[spec[1]]:FindFirstChild(jn)
					if check(name .. " Motor6D " .. jn, j and j:IsA("Motor6D") and j.Part1 == body[spec[2]]) then
						for _, c in { j.C0, j.C1 } do
							local comp = { c:GetComponents() }
							local maxd = 0
							for i = 1, 9 do
								maxd = math.max(maxd, math.abs(comp[3 + i] - spec[3][i]))
							end
							check(name .. " " .. jn .. " uses the standard R6 joint frame", maxd < 1e-4, maxd)
						end
					end
				end
			end
			for partName, list in ACCESSORY[rig] do
				for _, an in list do
					check(name .. " " .. partName .. "." .. an, body[partName] and body[partName]:FindFirstChild(an) ~= nil)
				end
			end

			-- everything hangs off the root
			local seen, queue = { [hrp] = true }, { hrp }
			while #queue > 0 do
				local p = table.remove(queue)
				for _, q in adj[p] or {} do
					if not seen[q] then
						seen[q] = true
						table.insert(queue, q)
					end
				end
			end
			local loose = 0
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") and not seen[d] then loose += 1 end
			end
			check(name .. " every part is jointed to the root", loose == 0, loose .. " loose")

			-- clothing and props
			local bad = 0
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") and d.Parent ~= m then
					if not d.Massless or d.CanCollide or d.CanQuery or d.CanTouch or d.Anchored then bad += 1 end
				end
			end
			check(name .. " outfit parts are massless and non-interacting", bad == 0, bad)

			-- standing height
			local footBottom = math.huge
			for _, n in rig == "R6" and { "Left Leg", "Right Leg" } or { "LeftFoot", "RightFoot" } do
				footBottom = math.min(footBottom, body[n].CFrame.Y - body[n].Size.Y / 2)
			end
			local expected
			if rig == "R15" then
				expected = footBottom + hum.HipHeight + hrp.Size.Y / 2
			else
				expected = footBottom + body["Left Leg"].Size.Y + hrp.Size.Y / 2 + hum.HipHeight
			end
			check(name .. " HipHeight puts the feet on the floor", math.abs(expected - hrp.CFrame.Y) < 1e-3, expected - hrp.CFrame.Y)
			check(name .. " pivot is at the feet", math.abs((hrp.CFrame * hrp.PivotOffset).Y - footBottom) < 1e-3)
		end
	end
	check(rig .. " model count", models == 63, models)
	print(string.format("  %d models, %d to %d parts each", models, least, worst))
end

print("markers")
local map = roblox.deserializeModel(fs.readFile("build/Liege1800s.rbxm"))[1]
local markers = map:FindFirstChild("NPCMarkers")
if check("map has NPCMarkers", markers ~= nil) then
	local n = 0
	for _, m in markers.Spawns:GetChildren() do
		n += 1
		check("spawn " .. m.Name .. " names a real character", ids[m:GetAttribute("NPCType")] ~= nil, m:GetAttribute("NPCType"))
		check("spawn " .. m.Name .. " does not interact", m.Anchored and not m.CanCollide and not m.CanQuery and not m.CanTouch and m.Transparency == 1)
		if m:GetAttribute("Behaviour") == "Patrol" then
			check("spawn " .. m.Name .. " route exists", markers.PatrolRoutes:FindFirstChild(m:GetAttribute("Route")) ~= nil)
		end
	end
	for _, f in markers.PatrolRoutes:GetChildren() do
		check("route " .. f.Name .. " names a real character", ids[f:GetAttribute("NPCType")] ~= nil)
		check("route " .. f.Name .. " has waypoints", f:FindFirstChild("P01") and f:FindFirstChild("P02"))
	end
	for _, f in markers.BossArenas:GetChildren() do
		check("arena " .. f.Name .. " boss exists", ids[f:GetAttribute("Boss")] ~= nil)
		check("arena " .. f.Name .. " parts", f:FindFirstChild("Bounds") and f:FindFirstChild("BossSpawn") and f:FindFirstChild("PlayerEntry") and f:FindFirstChild("Barriers"))
		if f:FindFirstChild("Reinforcements") then
			for _, a in f.Reinforcements:GetChildren() do
				check("arena " .. f.Name .. " reinforcement " .. a.Name, ids[a:GetAttribute("NPCType")] ~= nil)
			end
		end
	end
	print(string.format("  %d spawn markers", n))
end

local place = roblox.deserializePlace(fs.readFile("build/Liege1800s_Preview.rbxl"))
local preview = place:GetService("Workspace"):FindFirstChild("PreviewNPCs")
check("preview place has NPCs", preview and #preview:GetChildren() >= 90, preview and #preview:GetChildren())
check("preview place has NPC templates in ServerStorage", place:GetService("ServerStorage"):FindFirstChild("LiegeNPCs") ~= nil)

print(string.format("\n%d checks, %s", checks, failures == 0 and "ALL PASSED" or (failures .. " FAILED")))
if failures > 0 then error("NPC tests failed") end
