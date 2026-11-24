--[[
	lune run tools/test_ambience      (run `lune run build` first)

	Exercises the ambience scripts outside Roblox: compiles all three, drives the mood controller
	against the built model, and runs the two glue scripts in a mocked Roblox environment.
	It cannot check how anything looks; that needs Studio.
]]
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local failures = 0
local function check(name, cond, detail)
	if cond then
		print("  ok   " .. name)
	else
		failures += 1
		print("  FAIL " .. name .. (detail and ("  -> " .. tostring(detail)) or ""))
	end
end

local sources = {
	core = fs.readFile("src/Ambience/AmbienceCore.luau"),
	server = fs.readFile("src/Ambience/LiegeAmbience.server.luau"),
	client = fs.readFile("src/Ambience/LiegeAmbienceClient.client.luau"),
}

print("compile")
for name, src in sources do
	check(name .. " compiles", pcall(luau.compile, src))
end

-- the model exactly as shipped
local map = roblox.deserializeModel(fs.readFile("build/LiegeDuel.rbxm"))[1]
local ambience = map:FindFirstChild("Ambience")
local function getTagged(tag)
	local out = {}
	for _, d in map:GetDescendants() do
		if d:HasTag(tag) then table.insert(out, d) end
	end
	return out
end

print("shipped model")
check("Ambience folder present", ambience ~= nil)
check("scripts embedded", ambience.AmbienceCore.Source == sources.core and ambience.LiegeAmbience.Source == sources.server
	and ambience.LiegeAmbienceClient.Source == sources.client)
check("client script runs on the client", ambience.LiegeAmbienceClient.RunContext == roblox.Enum.RunContext.Client)
check("server script uses default run context", ambience.LiegeAmbience.RunContext == roblox.Enum.RunContext.Legacy)
local lamps, windows, fires = getTagged("LiegeLamp"), getTagged("LiegeLitWindow"), getTagged("LiegeFire")
check("street lamps tagged (" .. #lamps .. ")", #lamps > 30)
check("lit windows tagged (" .. #windows .. ")", #windows > 40)
check("fire lights tagged (" .. #fires .. ")", #fires == 4)

-- a fresh mocked game for each scenario
local function world()
	local game = roblox.Instance.new("DataModel")
	local lighting = game:GetService("Lighting")
	local workspace = game:GetService("Workspace")
	local terrain = roblox.Instance.new("Terrain")
	terrain.Parent = workspace
	return game, lighting, workspace, terrain
end
local function env(lighting, terrain)
	return { Lighting = lighting, Terrain = terrain, Instance = roblox.Instance, Color3 = roblox.Color3, Enum = roblox.Enum, getTagged = getTagged }
end
local Core = require("../src/Ambience/AmbienceCore")
local function near(a, b) return math.abs(a - b) < 1e-3 end

print("moods")
for name, preset in Core.presets do
	local s = Core.sample(preset.ClockTime)
	check(name .. " is hit exactly by the cycle", near(s.Atmosphere.Density, preset.Atmosphere.Density)
		and near(s.Lighting.Brightness, preset.Lighting.Brightness) and near(s.Clouds.Cover, preset.Clouds.Cover))
end
do
	local okAll, lastLamps, switches = true, Core.sample(0).LampsOn, 0
	for i = 0, 24 * 60 do
		local v = Core.sample(i / 60)
		for _, g in { "Lighting", "Atmosphere", "ColorCorrection", "Bloom", "SunRays", "Clouds" } do
			for _, x in v[g] do
				for _, n in (type(x) == "table" and x or { x }) do
					if n ~= n or n < -1 or n > 255.001 then okAll = false end
				end
			end
		end
		if v.LampsOn ~= lastLamps then switches += 1; lastLamps = v.LampsOn end
	end
	check("every minute of the day gives sane numbers", okAll)
	check("lamps switch exactly twice a day", switches == 2, switches)
	check("lamps are off at noon and on at midnight", Core.sample(12).LampsOn == false and Core.sample(0).LampsOn == true)
end

print("taking over and handing back Lighting")
do
	local _, lighting, _, terrain = world()
	local existing = roblox.Instance.new("Atmosphere")
	existing.Name = "GameAtmosphere"
	existing.Density = 0.11
	existing.Parent = lighting
	local theirGrade = roblox.Instance.new("ColorCorrectionEffect")
	theirGrade.Name = "GameGrade"
	theirGrade.Saturation = 0.5
	theirGrade.Parent = lighting
	lighting.Brightness = 3
	local session = Core.begin(env(lighting, terrain))
	session.apply(Core.presets.Dusk)
	check("reuses the game's Atmosphere", #lighting:GetChildren() == 5 and near(existing.Density, 0.36), #lighting:GetChildren())
	check("leaves the game's own colour grade alone", near(theirGrade.Saturation, 0.5))
	check("mood applied", near(lighting.Brightness, 2.2) and near(lighting.ClockTime, 17.4) and lighting:FindFirstChild("LiegeColorGrade") ~= nil)
	check("clouds created in Terrain", terrain:FindFirstChild("LiegeClouds") ~= nil and near(terrain.LiegeClouds.Cover, 0.62))
	local again = Core.begin(env(lighting, terrain))
	again.apply(Core.presets.Night)
	check("a second start does not duplicate effects", #lighting:GetChildren() == 5, #lighting:GetChildren())
	again.restore()
	session.restore()
	check("restore puts values back", near(lighting.Brightness, 3) and near(existing.Density, 0.11))
	check("restore removes only what it created", #lighting:GetChildren() == 2 and terrain:FindFirstChild("LiegeClouds") == nil, #lighting:GetChildren())
end

print("controller")
local function lampState()
	local neon, enabled = 0, 0
	for _, p in lamps do
		if p.Material == roblox.Enum.Material.Neon then neon += 1 end
		local l = p:FindFirstChildOfClass("PointLight")
		if l and l.Enabled then enabled += 1 end
	end
	local w = 0
	for _, p in windows do
		if p.Material == roblox.Enum.Material.Neon then w += 1 end
	end
	return neon, enabled, w
end
do
	local _, lighting, _, terrain = world()
	local e = env(lighting, terrain)
	local c = Core.start(ambience, e)
	check("starts in Dusk with lamps lit", near(lighting.ClockTime, 17.4) and select(1, lampState()) == #lamps)
	ambience:SetAttribute("Mood", "Overcast")
	c.step(1)
	local neon, enabled, w = lampState()
	check("Overcast: lamps and windows go dark", neon == 0 and enabled == 0 and w == 0 and near(lighting.ClockTime, 12.5), `{neon} {enabled} {w}`)
	ambience:SetAttribute("Mood", "Night")
	c.step(1)
	neon, enabled, w = lampState()
	check("Night: lamps and windows come back", neon == #lamps and enabled == #lamps and w == #windows)
	ambience:SetAttribute("Mood", "NoSuchMood")
	c.step(1)
	check("unknown mood falls back to Dusk", near(lighting.ClockTime, 17.4))

	ambience:SetAttribute("CycleMinutes", 24) -- one game hour per real minute
	local toggles, last, maxJump, prev = 0, true, 0, lighting.ClockTime
	for _ = 1, 24 * 60 do
		c.step(1)
		local on = select(1, lampState()) > 0
		if on ~= last then toggles += 1; last = on end
		local jump = (lighting.ClockTime - prev) % 24
		maxJump = math.max(maxJump, jump)
		prev = lighting.ClockTime
	end
	check("cycle: a full day returns to the start time", near(lighting.ClockTime, 17.4), lighting.ClockTime)
	check("cycle: clock advances smoothly", near(maxJump, 1 / 60), maxJump)
	check("cycle: lamps toggled twice", toggles == 2, toggles)
	ambience:SetAttribute("CycleMinutes", 0)
	ambience:SetAttribute("Mood", "Overcast")
	c.step(1)
	c.stop()
	check("stop relights the lamps and clears effects", select(1, lampState()) == #lamps and lighting:FindFirstChild("LiegeColorGrade") == nil)
	ambience:SetAttribute("Mood", "Dusk")

	ambience:SetAttribute("ManageLighting", false)
	check("ManageLighting = false does nothing", Core.start(ambience, e) == nil)
	ambience:SetAttribute("ManageLighting", true)
end

print("interior zones")
do
	local zones = ambience.InteriorZones
	local V = roblox.Vector3.new
	local z = Core.zoneAt(zones, V(-40, 6, -57))
	check("camera in Red's gunsmith -> Atelier_Red", z and z.Name == "Atelier_Red", z and z.Name)
	check("camera in Blue's estaminet -> Estaminet_Blue", (Core.zoneAt(zones, V(-36, 6, 55)) or {}).Name == "Estaminet_Blue")
	check("camera on Place du Marché -> none", Core.zoneAt(zones, V(0, 6, -40)) == nil)
	check("camera above the workshop roof -> none", Core.zoneAt(zones, V(-40, 40, -57)) == nil)
	local g = Core.gradeOf(z)
	check("zone grade read from attributes", near(g.Contrast, 0.1) and near(g.Tint[1], 255) and near(g.Tint[3], 170))
	check("neutral grade outdoors", Core.gradeOf(nil).Contrast == 0 and Core.gradeOf(nil).Tint[2] == 255)
end

--------------------------------------------------------------------- glue scripts under a mocked Roblox
-- Lune instances have no events, so wrap the few the scripts touch.
local function signal()
	local s = { handlers = {} }
	function s:Connect(fn)
		table.insert(self.handlers, fn)
		local conn = { Connected = true }
		function conn.Disconnect() conn.Connected = false; local i = table.find(s.handlers, fn); if i then table.remove(s.handlers, i) end end
		return conn
	end
	function s:fire(...) for _, fn in table.clone(self.handlers) do fn(...) end end
	return s
end
local function mockRun(source, name, opts)
	local game, lighting, workspace, terrain = world()
	local inWorkspace = true
	local signals = { AncestryChanged = signal(), Destroying = signal(), ScriptDestroying = signal(), Heartbeat = signal() }
	local ambienceProxy = setmetatable({}, { __index = function(_, k)
		if k == "AncestryChanged" or k == "Destroying" then return signals[k] end
		if k == "WaitForChild" then return function(_, n) return ambience:FindFirstChild(n) end end
		if k == "IsDescendantOf" then return function() return inWorkspace end end
		if k == "GetAttribute" then return function(_, n) return ambience:GetAttribute(n) end end
		if k == "Parent" then return map end
		error("unexpected ambience." .. tostring(k))
	end })
	local services = {
		Lighting = lighting,
		CollectionService = { GetTagged = function(_, tag) return getTagged(tag) end },
		RunService = { Heartbeat = signals.Heartbeat },
	}
	local gameProxy = { GetService = function(_, n) return services[n] or error("unexpected service " .. n) end }
	local workspaceProxy = setmetatable({ CurrentCamera = opts.camera }, { __index = function(_, k)
		if k == "FindFirstChildOfClass" then return function(_, c) return workspace:FindFirstChildOfClass(c) end end
		error("unexpected workspace." .. tostring(k))
	end })
	local waits = 0
	local environment = {
		game = gameProxy, workspace = workspaceProxy, Instance = roblox.Instance, Color3 = roblox.Color3, Enum = roblox.Enum,
		script = { Parent = ambienceProxy, Destroying = signals.ScriptDestroying },
		task = { wait = function(t)
			waits += 1
			if opts.onWait then opts.onWait(waits, signals, function(v) inWorkspace = v end) end
			return t or 0
		end },
	}
	local core
	environment.require = function()
		core = core or luau.load(sources.core, { debugName = "AmbienceCore", environment = environment })()
		return core
	end
	local ok, err = pcall(luau.load(source, { debugName = name, environment = environment }))
	return ok, err, { lighting = lighting, terrain = terrain, signals = signals, waits = waits, setInWorkspace = function(v) inWorkspace = v end }
end

print("server script, mocked")
do
	local seenNight
	local ok, err, w = mockRun(sources.server, "LiegeAmbience", { onWait = function(n, signals, setIn)
		if n == 2 then ambience:SetAttribute("Mood", "Night") end
		if n == 4 then
			setIn(false) -- map removed from Workspace
			signals.AncestryChanged:fire()
		end
	end })
	ambience:SetAttribute("Mood", "Dusk")
	check("runs to completion", ok, err)
	check("loop ended after the map was removed", w.waits == 4, w.waits)
	check("Lighting handed back (effects gone, lamps lit)", w.lighting:FindFirstChild("LiegeColorGrade") == nil
		and w.lighting:FindFirstChild("LiegeAtmosphere") == nil and select(1, lampState()) == #lamps)
end
do
	local midNight
	local ok, err, w
	ok, err, w = mockRun(sources.server, "LiegeAmbience", { onWait = function(n, signals)
		if n == 1 then ambience:SetAttribute("Mood", "Night") end
		if n == 3 then signals.Destroying:fire() end
	end })
	ambience:SetAttribute("Mood", "Dusk")
	check("Destroying also stops it", ok and w.waits == 3, err or w.waits)
end

print("client script, mocked")
do
	local camera = { CFrame = roblox.CFrame.new(-200, 6, -100) } -- outdoors
	local ok, err, w = mockRun(sources.client, "LiegeAmbienceClient", { camera = camera })
	check("starts", ok, err)
	local grade = w.lighting:FindFirstChild("LiegeInteriorGrade")
	check("creates its own colour grade", grade ~= nil)
	for _ = 1, 120 do w.signals.Heartbeat:fire(1 / 60) end
	check("neutral outdoors", near(grade.Contrast, 0) and near(grade.TintColor.B, 1), grade.Contrast)
	camera.CFrame = roblox.CFrame.new(36, 6, -55) -- walk into the estaminet
	for _ = 1, 240 do w.signals.Heartbeat:fire(1 / 60) end
	check("eases to the estaminet grade indoors", near(grade.Contrast, 0.08) and math.abs(grade.TintColor.B - 150 / 255) < 0.01, grade.Contrast)
	local flickered = false
	for _, l in fires do
		if not near(l.Brightness, l:GetAttribute("BaseBrightness")) then flickered = true end
		if l.Brightness <= 0 or l.Brightness > l:GetAttribute("BaseBrightness") * 1.5 then flickered = false; break end
	end
	check("fire lights flicker within bounds", flickered)
	camera.CFrame = roblox.CFrame.new(-200, 6, -100)
	for _ = 1, 240 do w.signals.Heartbeat:fire(1 / 60) end
	check("eases back outdoors", near(grade.Contrast, 0))
	w.setInWorkspace(false)
	w.signals.Heartbeat:fire(1 / 60)
	check("cleans up when the map is removed", w.lighting:FindFirstChild("LiegeInteriorGrade") == nil and #w.signals.Heartbeat.handlers == 0)
end

print(failures == 0 and "\nALL PASSED" or ("\n" .. failures .. " FAILED"))
if failures > 0 then error("ambience tests failed") end
