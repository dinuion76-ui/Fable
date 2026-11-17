--!nocheck
--[[
	Liège ambience — moods, the day/night cycle and the code that pushes them into Lighting.

	Everything here is plain data plus small functions, shared by:
	  LiegeAmbience        (server Script)  applies the mood, runs the cycle, switches the gas lamps
	  LiegeAmbienceClient  (client Script)  interior colour grading and firelight flicker
	  Studio command bar   require(workspace.Liege1800s.Ambience.AmbienceCore).preview("Dusk")

	Colours are {r, g, b} in 0-255 so moods can be blended with ordinary arithmetic.
	To restyle the map, edit the numbers in `presets`; nothing else needs to change.
]]
local Core = {}

Core.LATITUDE = 50.6 -- Liège
Core.TAG_LAMP = "LiegeLamp" -- street-lamp lanterns (Neon part holding a PointLight)
Core.TAG_WINDOW = "LiegeLitWindow" -- windows that glow after dark
Core.TAG_FIRE = "LiegeFire" -- PointLights of forges, furnaces and hearths

Core.presets = {
	-- Cold river mist before the workshops open.
	Dawn = {
		ClockTime = 6.5, LampsOn = true,
		Lighting = { Brightness = 1.7, Ambient = { 70, 72, 82 }, OutdoorAmbient = { 104, 108, 120 }, ColorShift_Top = { 255, 214, 196 },
			EnvironmentDiffuseScale = 0.55, EnvironmentSpecularScale = 0.3, ExposureCompensation = 0.1, ShadowSoftness = 0.4 },
		Atmosphere = { Density = 0.45, Offset = 0.1, Color = { 198, 198, 204 }, Decay = { 122, 118, 124 }, Glare = 0.15, Haze = 2.6 },
		ColorCorrection = { Brightness = 0, Contrast = 0.04, Saturation = -0.22, TintColor = { 240, 244, 255 } },
		Bloom = { Intensity = 0.4, Size = 24, Threshold = 1.4 },
		SunRays = { Intensity = 0.05, Spread = 0.9 },
		Clouds = { Cover = 0.7, Density = 0.4, Color = { 214, 210, 214 } },
	},
	-- Flat grey working day under coal smoke.
	Overcast = {
		ClockTime = 12.5, LampsOn = false,
		Lighting = { Brightness = 1.9, Ambient = { 88, 86, 84 }, OutdoorAmbient = { 130, 128, 126 }, ColorShift_Top = { 236, 230, 220 },
			EnvironmentDiffuseScale = 0.7, EnvironmentSpecularScale = 0.3, ExposureCompensation = 0, ShadowSoftness = 0.6 },
		Atmosphere = { Density = 0.4, Offset = 0.25, Color = { 190, 186, 178 }, Decay = { 110, 104, 96 }, Glare = 0, Haze = 2.4 },
		ColorCorrection = { Brightness = 0, Contrast = 0.06, Saturation = -0.26, TintColor = { 250, 246, 238 } },
		Bloom = { Intensity = 0.3, Size = 24, Threshold = 1.6 },
		SunRays = { Intensity = 0, Spread = 0.8 },
		Clouds = { Cover = 0.88, Density = 0.7, Color = { 176, 172, 168 } },
	},
	-- The default: low amber sun through the haze, gas lamps just lit.
	Dusk = {
		ClockTime = 17.4, LampsOn = true,
		Lighting = { Brightness = 2.2, Ambient = { 74, 66, 62 }, OutdoorAmbient = { 112, 102, 96 }, ColorShift_Top = { 255, 196, 140 },
			EnvironmentDiffuseScale = 0.6, EnvironmentSpecularScale = 0.4, ExposureCompensation = 0.05, ShadowSoftness = 0.3 },
		Atmosphere = { Density = 0.36, Offset = 0.2, Color = { 200, 174, 146 }, Decay = { 104, 90, 80 }, Glare = 0.25, Haze = 2.1 },
		ColorCorrection = { Brightness = 0, Contrast = 0.08, Saturation = -0.12, TintColor = { 255, 242, 226 } },
		Bloom = { Intensity = 0.5, Size = 24, Threshold = 1.3 },
		SunRays = { Intensity = 0.07, Spread = 0.8 },
		Clouds = { Cover = 0.62, Density = 0.5, Color = { 206, 180, 156 } },
	},
	-- Blue fog; the streets are lit only by lamps, windows and forges.
	Night = {
		ClockTime = 23, LampsOn = true,
		Lighting = { Brightness = 1.4, Ambient = { 38, 42, 60 }, OutdoorAmbient = { 56, 62, 88 }, ColorShift_Top = { 150, 170, 220 },
			EnvironmentDiffuseScale = 0.35, EnvironmentSpecularScale = 0.25, ExposureCompensation = 0.35, ShadowSoftness = 0.3 },
		Atmosphere = { Density = 0.4, Offset = 0, Color = { 58, 64, 88 }, Decay = { 26, 28, 40 }, Glare = 0, Haze = 1.6 },
		ColorCorrection = { Brightness = 0.02, Contrast = 0.12, Saturation = -0.08, TintColor = { 214, 224, 255 } },
		Bloom = { Intensity = 0.9, Size = 28, Threshold = 1 },
		SunRays = { Intensity = 0, Spread = 0.8 },
		Clouds = { Cover = 0.5, Density = 0.35, Color = { 60, 66, 90 } },
	},
}

-- Clock times at which the cycle passes through each mood.
Core.cycle = {
	{ 0, "Night" }, { 4.8, "Night" }, { 6.5, "Dawn" }, { 9.5, "Overcast" },
	{ 15.5, "Overcast" }, { 17.4, "Dusk" }, { 19.6, "Night" }, { 24, "Night" },
}
Core.LAMPS_OFF_AT = 7.6 -- lamplighter's rounds
Core.LAMPS_ON_AT = 16.6

local GROUPS = { "Lighting", "Atmosphere", "ColorCorrection", "Bloom", "SunRays", "Clouds" }

local function lerp(a, b, t)
	return a + (b - a) * t
end

-- Blend of two moods (t = 0 gives `a`, t = 1 gives `b`).
function Core.blend(a, b, t)
	local out = {}
	for _, group in ipairs(GROUPS) do
		local ga, gb, go = a[group], b[group], {}
		for key, va in pairs(ga) do
			local vb = gb[key]
			if type(va) == "table" then
				go[key] = { lerp(va[1], vb[1], t), lerp(va[2], vb[2], t), lerp(va[3], vb[3], t) }
			else
				go[key] = lerp(va, vb, t)
			end
		end
		out[group] = go
	end
	return out
end

-- Mood for an arbitrary clock time (0-24), following Core.cycle.
function Core.sample(clock)
	clock = clock % 24
	local keys = Core.cycle
	local values
	for i = 1, #keys - 1 do
		local t0, t1 = keys[i][1], keys[i + 1][1]
		if clock >= t0 and clock < t1 then
			values = Core.blend(Core.presets[keys[i][2]], Core.presets[keys[i + 1][2]], (clock - t0) / (t1 - t0))
			break
		end
	end
	values = values or Core.blend(Core.presets.Night, Core.presets.Night, 0)
	values.ClockTime = clock
	values.LampsOn = clock < Core.LAMPS_OFF_AT or clock >= Core.LAMPS_ON_AT
	return values
end

--[[
	Takes over Lighting and returns { apply(values), restore() }.
	  - an existing Atmosphere / Clouds is reused (there can only be one of each);
	  - our post effects are separate instances named Liege*, so the game's own are left alone;
	  - every property we change is remembered and put back by restore().
	`env` is only for running outside Roblox (build script, tests).
]]
function Core.begin(env)
	env = env or {}
	local lighting = env.Lighting or game:GetService("Lighting")
	local newInstance = (env.Instance or Instance).new
	local rgb = (env.Color3 or Color3).fromRGB
	local terrain = env.Terrain
	if terrain == nil and not env.Lighting then
		terrain = workspace:FindFirstChildOfClass("Terrain")
	end

	local created, saved, seen = {}, {}, {}
	local function own(className, name, parent, reuseAnyOfClass)
		local inst = parent:FindFirstChild(name)
		if inst and inst.ClassName ~= className then inst = nil end
		if not inst and reuseAnyOfClass then inst = parent:FindFirstChildOfClass(className) end
		if not inst then
			inst = newInstance(className)
			inst.Name = name
			inst.Parent = parent
			created[#created + 1] = inst
		end
		return inst
	end

	local targets = {
		Lighting = lighting,
		Atmosphere = own("Atmosphere", "LiegeAtmosphere", lighting, true),
		ColorCorrection = own("ColorCorrectionEffect", "LiegeColorGrade", lighting, false),
		Bloom = own("BloomEffect", "LiegeBloom", lighting, false),
		SunRays = own("SunRaysEffect", "LiegeSunRays", lighting, false),
	}
	if terrain then targets.Clouds = own("Clouds", "LiegeClouds", terrain, true) end

	local function set(inst, prop, value)
		if type(value) == "table" then value = rgb(value[1], value[2], value[3]) end
		local key = seen[inst]
		if not key then
			key = {}
			seen[inst] = key
		end
		if not key[prop] then
			key[prop] = true
			local ok, old = pcall(function() return inst[prop] end)
			if ok then saved[#saved + 1] = { inst, prop, old } end
		end
		inst[prop] = value
	end

	local session = { targets = targets }
	function session.apply(values)
		set(lighting, "GeographicLatitude", Core.LATITUDE)
		set(lighting, "ClockTime", values.ClockTime)
		for _, group in ipairs(GROUPS) do
			local inst, props = targets[group], values[group]
			if inst and props then
				for prop, value in pairs(props) do set(inst, prop, value) end
			end
		end
	end
	function session.restore()
		for i = #saved, 1, -1 do
			local s = saved[i]
			pcall(function() s[1][s[2]] = s[3] end)
		end
		for _, inst in ipairs(created) do
			pcall(function() inst:Destroy() end)
		end
		created, saved, seen = {}, {}, {}
	end
	return session
end

-- One-off look for Studio's edit mode (run from the command bar).
function Core.preview(moodName)
	local session = Core.begin()
	session.apply(Core.presets[moodName or "Dusk"] or Core.presets.Dusk)
	return session
end

local LIT, DARK_GLASS, COLD_LANTERN = { 255, 196, 120 }, { 38, 48, 60 }, { 74, 74, 68 }

-- Lights or douses every street lamp and glowing window under `root`.
function Core.setLamps(root, on, env)
	env = env or {}
	local enum = env.Enum or Enum
	local rgb = (env.Color3 or Color3).fromRGB
	local getTagged = env.getTagged or function(tag)
		return game:GetService("CollectionService"):GetTagged(tag)
	end
	local neon, glass = enum.Material.Neon, enum.Material.Glass
	local lit = rgb(LIT[1], LIT[2], LIT[3])
	local darkGlass = rgb(DARK_GLASS[1], DARK_GLASS[2], DARK_GLASS[3])
	local cold = rgb(COLD_LANTERN[1], COLD_LANTERN[2], COLD_LANTERN[3])
	for _, part in ipairs(getTagged(Core.TAG_LAMP)) do
		if part:IsDescendantOf(root) then
			part.Material = on and neon or glass
			part.Color = on and lit or cold
			local light = part:FindFirstChildOfClass("PointLight")
			if light then light.Enabled = on end
		end
	end
	for _, part in ipairs(getTagged(Core.TAG_WINDOW)) do
		if part:IsDescendantOf(root) then
			part.Material = on and neon or glass
			part.Color = on and lit or darkGlass
		end
	end
end

--[[
	Controller for the server script.  Reads these attributes of the Ambience folder every step,
	so they can be changed while the game runs (by hand or from your own scripts):
	  ManageLighting  boolean  false = leave Lighting completely alone        (default true)
	  Mood            string   Dawn | Overcast | Dusk | Night                 (default Dusk)
	  CycleMinutes    number   0 = hold Mood; > 0 = minutes for a full 24 h   (default 0)
	Returns nil when ManageLighting is false.
]]
function Core.start(ambience, env)
	if ambience:GetAttribute("ManageLighting") == false then return nil end
	local root = ambience.Parent
	local session = Core.begin(env)
	local state = {}
	local controller = { state = state }

	function controller.step(dt)
		local cycle = tonumber(ambience:GetAttribute("CycleMinutes")) or 0
		local moodName = ambience:GetAttribute("Mood")
		if not Core.presets[moodName] then moodName = "Dusk" end
		local values
		if cycle > 0 then
			state.clock = ((state.clock or Core.presets[moodName].ClockTime) + (dt or 0) * 24 / (cycle * 60)) % 24
			state.held = nil
			values = Core.sample(state.clock)
		else
			if state.held == moodName then return end -- nothing changed
			state.held = moodName
			values = Core.presets[moodName]
			state.clock = values.ClockTime
		end
		session.apply(values)
		if values.LampsOn ~= state.lampsOn then
			state.lampsOn = values.LampsOn
			Core.setLamps(root, values.LampsOn, env)
		end
	end

	function controller.stop()
		session.restore()
		if state.lampsOn == false then
			state.lampsOn = true
			Core.setLamps(root, true, env)
		end
	end

	controller.step(0)
	return controller
end

-- Interior zone (a part in Ambience.InteriorZones) containing `position`, or nil.
function Core.zoneAt(zones, position)
	for _, zone in ipairs(zones:GetChildren()) do
		if zone:IsA("BasePart") then
			local p = zone.CFrame:PointToObjectSpace(position)
			local s = zone.Size
			if math.abs(p.X) <= s.X / 2 and math.abs(p.Y) <= s.Y / 2 and math.abs(p.Z) <= s.Z / 2 then
				return zone
			end
		end
	end
	return nil
end

-- Colour-grade targets for a zone (neutral when `zone` is nil).  Tint is {r, g, b}.
function Core.gradeOf(zone)
	if not zone then return { Brightness = 0, Contrast = 0, Saturation = 0, Tint = { 255, 255, 255 } } end
	local tint = zone:GetAttribute("Tint")
	return {
		Brightness = zone:GetAttribute("Brightness") or 0,
		Contrast = zone:GetAttribute("Contrast") or 0,
		Saturation = zone:GetAttribute("Saturation") or 0,
		Tint = tint and { tint.R * 255, tint.G * 255, tint.B * 255 } or { 255, 255, 255 },
	}
end

return Core
