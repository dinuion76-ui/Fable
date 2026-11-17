--!nocheck
--[[
	Liège in the 1800s (a c. 1870-1880 snapshot) — procedural map generator.

	Returns a function:   build(config?, R?) -> Model, stats
	  config.seed         number   layout seed for house variation (default 1867)
	  config.lampLights   boolean  put a PointLight in every street lamp (default true)
	  config.spawnLocations boolean  emit real SpawnLocations instead of marker parts (default false)
	  config.scripts      table    { core, server, client } sources of src/Ambience; when given, the
	                               ambience scripts are embedded in the model (the Lune build does this)
	  R                   table    {Instance, Vector3, CFrame, Color3, Enum, UDim2, Font}; defaults to Roblox globals.
	                               (Lets the same file run under Lune to produce the .rbxm.)

	Footprint: x and z in [-500, 500]  (1000 x 1000 studs).  North = -Z, East = +X.
	Street level y = 0, water surface y = -8, river bed y = -11, citadel plateau y = 64.

	Only Part / WedgePart primitives are used: no unions, no meshes, no textures.
]]

return function(config, R)
	config = config or {}
	R = R or {}
	local Instance = R.Instance or Instance
	local Vector3 = R.Vector3 or Vector3
	local CFrame = R.CFrame or CFrame
	local Color3 = R.Color3 or Color3
	local Enum = R.Enum or Enum
	local UDim2 = R.UDim2 or UDim2
	local Font = R.Font or Font

	local LAMP_LIGHTS = config.lampLights ~= false
	local SPAWN_LOCATIONS = config.spawnLocations == true

	local N, S, E, W = "N", "S", "E", "W"
	local OPP = { N = S, S = N, E = W, W = E }
	local PI = math.pi
	local YAW = { N = 0, S = PI, W = PI / 2, E = -PI / 2 } -- direction a wedge slope descends towards
	local min, max, floor = math.min, math.max, math.floor

	local M = Enum.Material
	local SMOOTH = Enum.SurfaceType.Smooth
	local STREAMING_MESH = Enum.ModelLevelOfDetail.StreamingMesh

	local function C(r, g, b)
		return Color3.fromRGB(r, g, b)
	end

	local P = {
		cobble = C(98, 95, 90),
		paving = C(132, 128, 119),
		dirt = C(104, 90, 70),
		grass = C(88, 110, 64),
		stone = C(128, 132, 135), -- Meuse bluestone
		darkstone = C(96, 98, 102),
		lime = C(188, 181, 164), -- pale limestone
		brick = { C(142, 74, 58), C(122, 64, 52), C(156, 88, 66), C(108, 60, 50), C(134, 82, 68) },
		plaster = {
			C(206, 192, 162), C(192, 164, 116), C(160, 158, 150), C(214, 208, 190),
			C(150, 160, 136), C(184, 146, 130), C(170, 150, 120),
		},
		slate = { C(58, 62, 72), C(68, 70, 78), C(50, 54, 62) },
		tile = C(120, 66, 50),
		glass = C(38, 48, 60),
		lit = C(255, 196, 120),
		wood = C(92, 62, 40),
		darkwood = C(60, 42, 30),
		iron = C(44, 46, 50),
		water = C(58, 84, 86),
		mud = C(84, 76, 62),
		coal = C(28, 28, 30),
		sand = C(176, 158, 120),
		ember = C(255, 120, 40),
		brass = C(176, 140, 70),
		awning = { C(150, 54, 44), C(60, 84, 70), C(190, 170, 120), C(70, 80, 110) },
		leaf = { C(74, 104, 54), C(94, 112, 52), C(122, 108, 50), C(64, 92, 60) },
	}

	---------------------------------------------------------------- RNG
	local seed = (config.seed or 1867) % 2147483647
	if seed <= 0 then seed = 1867 end
	local function rnd()
		seed = (seed * 16807) % 2147483647
		return seed / 2147483647
	end
	local function rint(a, b)
		return a + floor(rnd() * (b - a + 1))
	end
	local function pick(t)
		return t[rint(1, #t)]
	end

	---------------------------------------------------------------- primitives
	local stats = { parts = 0, lights = 0, signs = 0 }

	local function finish(p, parent, name, color, mat, o)
		p.Name = name or "Part"
		p.Anchored = true
		p.CanTouch = false
		p.TopSurface = SMOOTH
		p.BottomSurface = SMOOTH
		p.Color = color
		p.Material = mat
		if o then
			if o.deco then
				p.CanCollide = false
				p.CanQuery = false
				p.CastShadow = false
			end
			if o.nc then p.CanCollide = false end
			if o.noshadow then p.CastShadow = false end
			if o.t then p.Transparency = o.t end
			if o.refl then p.Reflectance = o.refl end
		end
		if name == "Window" and mat.Name == "Neon" then p:AddTag("LiegeLitWindow") end
		p.Parent = parent
		stats.parts += 1
		return p
	end

	local function box(parent, x0, y0, z0, x1, y1, z1, color, mat, o, name)
		if x1 < x0 then x0, x1 = x1, x0 end
		if y1 < y0 then y0, y1 = y1, y0 end
		if z1 < z0 then z0, z1 = z1, z0 end
		local p = Instance.new("Part")
		p.Size = Vector3.new(x1 - x0, y1 - y0, z1 - z0)
		p.CFrame = CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
		return finish(p, parent, name, color, mat, o)
	end

	-- Wedge filling the given bounding box; the slope descends towards `dir`.
	-- o.flip turns it upside down (flat face on top) for corbels / arch haunches.
	local function wedge(parent, x0, y0, z0, x1, y1, z1, dir, color, mat, o, name)
		if x1 < x0 then x0, x1 = x1, x0 end
		if z1 < z0 then z0, z1 = z1, z0 end
		local sx, sy, sz = x1 - x0, y1 - y0, z1 - z0
		local p = Instance.new("WedgePart")
		if dir == N or dir == S then
			p.Size = Vector3.new(sx, sy, sz)
		else
			p.Size = Vector3.new(sz, sy, sx)
		end
		local cf = CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2) * CFrame.Angles(0, YAW[dir], 0)
		if o and o.flip then cf = cf * CFrame.Angles(0, 0, PI) end
		p.CFrame = cf
		return finish(p, parent, name or "Wedge", color, mat, o)
	end

	local function cylY(parent, cx, y0, y1, cz, d, color, mat, o, name)
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(y1 - y0, d, d)
		p.CFrame = CFrame.new(cx, (y0 + y1) / 2, cz) * CFrame.Angles(0, 0, PI / 2)
		return finish(p, parent, name or "Column", color, mat, o)
	end
	local function cylX(parent, x0, x1, cy, cz, d, color, mat, o, name)
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(x1 - x0, d, d)
		p.CFrame = CFrame.new((x0 + x1) / 2, cy, cz)
		return finish(p, parent, name or "Cylinder", color, mat, o)
	end
	local function cylZ(parent, cx, cy, z0, z1, d, color, mat, o, name)
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(z1 - z0, d, d)
		p.CFrame = CFrame.new(cx, cy, (z0 + z1) / 2) * CFrame.Angles(0, PI / 2, 0)
		return finish(p, parent, name or "Cylinder", color, mat, o)
	end
	local function ball(parent, cx, cy, cz, d, color, mat, o, name)
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.new(d, d, d)
		p.CFrame = CFrame.new(cx, cy, cz)
		return finish(p, parent, name or "Ball", color, mat, o)
	end
	-- Thin board between two points (gangplanks, jibs, shafts).
	local function plank(parent, ax, ay, az, bx, by, bz, width, thick, color, mat, o, name)
		local a, b = Vector3.new(ax, ay, az), Vector3.new(bx, by, bz)
		local p = Instance.new("Part")
		p.Size = Vector3.new(width, thick, (b - a).Magnitude)
		p.CFrame = CFrame.new((a + b) / 2, b)
		return finish(p, parent, name or "Plank", color, mat, o)
	end

	local function model(parent, name, lod)
		local m = Instance.new("Model")
		m.Name = name
		if lod then m.LevelOfDetail = STREAMING_MESH end
		m.Parent = parent
		return m
	end
	local function folder(parent, name)
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
		return f
	end

	local DECO = { deco = true }

	local function windowLook(litChance)
		if rnd() < (litChance or 0.12) then return P.lit, M.Neon end
		return P.glass, M.Glass
	end

	---------------------------------------------------------------- composite helpers
	-- Visual steps + one invisible collision ramp (smooth to walk, cheap to simulate).
	local function stairs(parent, x0, z0, x1, z1, yLow, yHigh, up, yBase, color, mat)
		local n = max(1, floor(yHigh - yLow + 0.5))
		local rise = (yHigh - yLow) / n
		local alongX = (up == E or up == W)
		local r = (alongX and (x1 - x0) or (z1 - z0)) / n
		for i = 0, n - 1 do
			local top = yLow + (i + 1) * rise
			local a0, a1 = i * r, (i + 1) * r
			local bx0, bx1, bz0, bz1 = x0, x1, z0, z1
			if up == E then bx0, bx1 = x0 + a0, x0 + a1
			elseif up == W then bx0, bx1 = x1 - a1, x1 - a0
			elseif up == S then bz0, bz1 = z0 + a0, z0 + a1
			else bz0, bz1 = z1 - a1, z1 - a0 end
			box(parent, bx0, yBase, bz0, bx1, top, bz1, color, mat, { nc = true }, "Step")
		end
		local h = r / 2
		local rx0, rx1, rz0, rz1 = x0, x1, z0, z1
		if up == E then rx0, rx1 = rx0 - h, rx1 - h
		elseif up == W then rx0, rx1 = rx0 + h, rx1 + h
		elseif up == S then rz0, rz1 = rz0 - h, rz1 - h
		else rz0, rz1 = rz0 + h, rz1 + h end
		wedge(parent, rx0, yLow, rz0, rx1, yHigh, rz1, OPP[up], color, mat, { t = 1, noshadow = true }, "StairRamp")
	end

	-- Four walls with door / window holes.  openings = { {side, a, b, sillY, headY}, ... } (a,b in world coords)
	local function walls(parent, x0, z0, x1, z1, y0, y1, t, color, mat, openings, sides)
		sides = sides or "NSEW"
		for i = 1, #sides do
			local sd = string.sub(sides, i, i)
			local a0, a1
			if sd == N or sd == S then a0, a1 = x0, x1 else a0, a1 = z0 + t, z1 - t end
			local function seg(a, b, ya, yb)
				if b - a < 0.05 or yb - ya < 0.05 then return end
				if sd == N then box(parent, a, ya, z0, b, yb, z0 + t, color, mat, nil, "Wall")
				elseif sd == S then box(parent, a, ya, z1 - t, b, yb, z1, color, mat, nil, "Wall")
				elseif sd == W then box(parent, x0, ya, a, x0 + t, yb, b, color, mat, nil, "Wall")
				else box(parent, x1 - t, ya, a, x1, yb, b, color, mat, nil, "Wall") end
			end
			local ops = {}
			for _, op in ipairs(openings or {}) do
				if op[1] == sd then ops[#ops + 1] = op end
			end
			table.sort(ops, function(p, q) return p[2] < q[2] end)
			local cur = a0
			for _, op in ipairs(ops) do
				local a, b, oy0, oy1 = op[2], op[3], op[4] or 0, op[5] or 8
				seg(cur, a, y0, y1)
				seg(a, b, y0, y0 + oy0)
				seg(a, b, y0 + oy1, y1)
				cur = b
			end
			seg(cur, a1, y0, y1)
		end
	end

	local function gableRoof(parent, x0, z0, x1, z1, y, h, axis, color, mat, ov)
		ov = ov or 0.8
		mat = mat or M.Slate
		if axis == "X" then
			local zc = (z0 + z1) / 2
			wedge(parent, x0, y, z0 - ov, x1, y + h, zc, N, color, mat, nil, "Roof")
			wedge(parent, x0, y, zc, x1, y + h, z1 + ov, S, color, mat, nil, "Roof")
		else
			local xc = (x0 + x1) / 2
			wedge(parent, x0 - ov, y, z0, xc, y + h, z1, W, color, mat, nil, "Roof")
			wedge(parent, xc, y, z0, x1 + ov, y + h, z1, E, color, mat, nil, "Roof")
		end
	end
	-- Four-gabled helm for towers.
	local function helm(parent, x0, z0, x1, z1, y, h, color)
		local xc, zc = (x0 + x1) / 2, (z0 + z1) / 2
		wedge(parent, x0, y, z0, x1, y + h, zc, N, color, M.Slate, nil, "Spire")
		wedge(parent, x0, y, zc, x1, y + h, z1, S, color, M.Slate, nil, "Spire")
		wedge(parent, x0, y, z0, xc, y + h, z1, W, color, M.Slate, nil, "Spire")
		wedge(parent, xc, y, z0, x1, y + h, z1, E, color, M.Slate, nil, "Spire")
	end

	-- n windows per row on a wall plane whose outward normal is `side`, at plane coordinate c.
	local function winGrid(parent, side, c, a0, a1, n, ys, ww, wh, litChance)
		ww = ww or 3.4
		wh = wh or 6
		for _, y in ipairs(ys) do
			for i = 1, n do
				local a = a0 + (i - 0.5) * (a1 - a0) / n
				local col, mat = windowLook(litChance)
				if side == N then box(parent, a - ww / 2, y, c - 0.2, a + ww / 2, y + wh, c + 0.3, col, mat, DECO, "Window")
				elseif side == S then box(parent, a - ww / 2, y, c - 0.3, a + ww / 2, y + wh, c + 0.2, col, mat, DECO, "Window")
				elseif side == W then box(parent, c - 0.2, y, a - ww / 2, c + 0.3, y + wh, a + ww / 2, col, mat, DECO, "Window")
				else box(parent, c - 0.3, y, a - ww / 2, c + 0.2, y + wh, a + ww / 2, col, mat, DECO, "Window") end
			end
		end
	end

	local FACE = { N = Enum.NormalId.Front, S = Enum.NormalId.Back, E = Enum.NormalId.Right, W = Enum.NormalId.Left }
	local function sign(parent, x, y, z, w, h, facing, text, bg, fg)
		local p
		if facing == N or facing == S then
			p = box(parent, x - w / 2, y - h / 2, z - 0.2, x + w / 2, y + h / 2, z + 0.2, bg or P.darkwood, M.Wood, DECO, "Sign")
		else
			p = box(parent, x - 0.2, y - h / 2, z - w / 2, x + 0.2, y + h / 2, z + w / 2, bg or P.darkwood, M.Wood, DECO, "Sign")
		end
		local g = Instance.new("SurfaceGui")
		g.Name = "Text"
		g.Face = FACE[facing]
		g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		g.PixelsPerStud = 24
		g.LightInfluence = 1
		g.Parent = p
		local t = Instance.new("TextLabel")
		t.Size = UDim2.new(1, 0, 1, 0)
		t.BackgroundTransparency = 1
		t.Text = text
		t.TextScaled = true
		t.FontFace = Font.fromEnum(Enum.Font.Antique)
		t.TextColor3 = fg or C(232, 214, 168)
		t.Parent = g
		stats.signs += 1
		return p
	end

	---------------------------------------------------------------- props
	local function lamp(parent, x, z, y0)
		y0 = y0 or 0
		cylY(parent, x, y0, y0 + 11, z, 0.6, P.iron, M.Metal, { noshadow = true }, "LampPost")
		local l = box(parent, x - 0.55, y0 + 11, z - 0.55, x + 0.55, y0 + 12.4, z + 0.55, P.lit, M.Neon, DECO, "Lantern")
		l:AddTag("LiegeLamp")
		if LAMP_LIGHTS then
			local pl = Instance.new("PointLight")
			pl.Range = 22
			pl.Brightness = 0.9
			pl.Color = C(255, 190, 120)
			pl.Shadows = false
			pl.Parent = l
			stats.lights += 1
		end
	end
	local function ceilingLamp(parent, x, y, z, range)
		local l = box(parent, x - 0.6, y - 1.4, z - 0.6, x + 0.6, y, z + 0.6, P.lit, M.Neon, DECO, "Lantern")
		local pl = Instance.new("PointLight")
		pl.Range = range or 28
		pl.Brightness = 1
		pl.Color = C(255, 186, 110)
		pl.Shadows = false
		pl.Parent = l
		stats.lights += 1
	end
	-- Flickering firelight + flame on a forge / furnace / hearth part.
	local function fireGlow(part, range, brightness, flameSize)
		local pl = Instance.new("PointLight")
		pl.Name = "FireLight"
		pl.Range = range
		pl.Brightness = brightness
		pl.Color = C(255, 140, 60)
		pl.Shadows = false
		pl:SetAttribute("BaseBrightness", brightness)
		pl:AddTag("LiegeFire")
		pl.Parent = part
		local f = Instance.new("Fire")
		f.Size = flameSize
		f.Heat = 8
		f.Color = C(255, 150, 60)
		f.SecondaryColor = C(150, 50, 20)
		f.Parent = part
		stats.lights += 1
	end
	-- Chimney smoke (built-in Smoke object, no asset ids).
	local function smoke(parent, x, y, z, size, opacity, rise, color)
		local e = box(parent, x - 0.5, y - 0.5, z - 0.5, x + 0.5, y + 0.5, z + 0.5, P.coal, M.SmoothPlastic, { deco = true, t = 1 }, "SmokeEmitter")
		local s = Instance.new("Smoke")
		s.Size = size
		s.Opacity = opacity
		s.RiseVelocity = rise
		s.Color = color or C(96, 92, 88)
		s.Parent = e
		stats.smoke = (stats.smoke or 0) + 1
	end
	local function tree(parent, x, z, y0, s)
		y0 = y0 or 0
		s = s or 1
		cylY(parent, x, y0, y0 + 9 * s, z, 1.6 * s, P.darkwood, M.Wood, { noshadow = true }, "Trunk")
		ball(parent, x, y0 + 13 * s, z, 12 * s, pick(P.leaf), M.Grass, { nc = true }, "Foliage")
		ball(parent, x + 2.5 * s, y0 + 17 * s, z - 1.5 * s, 8 * s, pick(P.leaf), M.Grass, DECO, "Foliage")
	end
	local function crate(parent, x, z, y0, s)
		s = s or 3
		box(parent, x - s / 2, y0, z - s / 2, x + s / 2, y0 + s, z + s / 2, P.wood, M.WoodPlanks, { noshadow = true }, "Crate")
	end
	local function barrel(parent, x, z, y0)
		cylY(parent, x, y0, y0 + 3.4, z, 2.6, P.darkwood, M.WoodPlanks, { noshadow = true }, "Barrel")
	end
	local function cart(parent, x, z, y0, axis)
		if axis == "X" then
			box(parent, x - 4.5, y0 + 2.2, z - 2.4, x + 4.5, y0 + 3.2, z + 2.4, P.wood, M.WoodPlanks, nil, "CartBed")
			box(parent, x - 4.5, y0 + 3.2, z - 2.4, x + 4.5, y0 + 5, z - 2, P.wood, M.WoodPlanks, { noshadow = true }, "CartSide")
			box(parent, x - 4.5, y0 + 3.2, z + 2, x + 4.5, y0 + 5, z + 2.4, P.wood, M.WoodPlanks, { noshadow = true }, "CartSide")
			cylZ(parent, x, y0 + 2.2, z - 3.1, z - 2.5, 4.4, P.darkwood, M.Wood, { noshadow = true }, "Wheel")
			cylZ(parent, x, y0 + 2.2, z + 2.5, z + 3.1, 4.4, P.darkwood, M.Wood, { noshadow = true }, "Wheel")
		else
			box(parent, x - 2.4, y0 + 2.2, z - 4.5, x + 2.4, y0 + 3.2, z + 4.5, P.wood, M.WoodPlanks, nil, "CartBed")
			box(parent, x - 2.4, y0 + 3.2, z - 4.5, x - 2, y0 + 5, z + 4.5, P.wood, M.WoodPlanks, { noshadow = true }, "CartSide")
			box(parent, x + 2, y0 + 3.2, z - 4.5, x + 2.4, y0 + 5, z + 4.5, P.wood, M.WoodPlanks, { noshadow = true }, "CartSide")
			cylX(parent, x - 3.1, x - 2.5, y0 + 2.2, z, 4.4, P.darkwood, M.Wood, { noshadow = true }, "Wheel")
			cylX(parent, x + 2.5, x + 3.1, y0 + 2.2, z, 4.4, P.darkwood, M.Wood, { noshadow = true }, "Wheel")
		end
	end
	-- Market stall; the canopy drops towards `face`.
	local function stall(parent, x, z, face)
		local col = pick(P.awning)
		if face == N or face == S then
			box(parent, x - 4.5, 0, z - 1.6, x + 4.5, 3.2, z + 1.6, P.wood, M.WoodPlanks, { noshadow = true }, "Counter")
			local zb = (face == S) and (z - 2.2) or (z + 2.2)
			cylY(parent, x - 4.3, 0, 9.2, zb, 0.5, P.darkwood, M.Wood, DECO, "Post")
			cylY(parent, x + 4.3, 0, 9.2, zb, 0.5, P.darkwood, M.Wood, DECO, "Post")
			wedge(parent, x - 5, 7.2, z - 3, x + 5, 9.4, z + 3, face, col, M.Fabric, { nc = true, noshadow = true }, "Canopy")
		else
			box(parent, x - 1.6, 0, z - 4.5, x + 1.6, 3.2, z + 4.5, P.wood, M.WoodPlanks, { noshadow = true }, "Counter")
			local xb = (face == E) and (x - 2.2) or (x + 2.2)
			cylY(parent, xb, 0, 9.2, z - 4.3, 0.5, P.darkwood, M.Wood, DECO, "Post")
			cylY(parent, xb, 0, 9.2, z + 4.3, 0.5, P.darkwood, M.Wood, DECO, "Post")
			wedge(parent, x - 3, 7.2, z - 5, x + 3, 9.4, z + 5, face, col, M.Fabric, { nc = true, noshadow = true }, "Canopy")
		end
	end
	local function well(parent, x, z, y0)
		cylY(parent, x, y0, y0 + 3, z, 6, P.stone, M.Cobblestone, nil, "Well")
		cylY(parent, x, y0 + 2.6, y0 + 3.05, z, 4.6, C(20, 26, 30), M.SmoothPlastic, DECO, "WellWater")
		cylY(parent, x - 2.6, y0 + 3, y0 + 8, z, 0.5, P.darkwood, M.Wood, DECO, "Post")
		cylY(parent, x + 2.6, y0 + 3, y0 + 8, z, 0.5, P.darkwood, M.Wood, DECO, "Post")
		box(parent, x - 3.4, y0 + 8, z - 1.6, x + 3.4, y0 + 8.6, z + 1.6, P.slate[1], M.Slate, DECO, "WellRoof")
	end
	local function heap(parent, x0, z0, x1, z1, y0, h, color, mat)
		local xc = (x0 + x1) / 2
		wedge(parent, x0, y0, z0, xc, y0 + h, z1, W, color, mat, nil, "Heap")
		wedge(parent, xc, y0, z0, x1, y0 + h, z1, E, color, mat, nil, "Heap")
	end
	local function cannon(parent, x, z, y0, dir)
		local dx, dz = 0, 0
		if dir == E then dx = 1 elseif dir == W then dx = -1 elseif dir == S then dz = 1 else dz = -1 end
		if dx ~= 0 then
			cylX(parent, x - 3 + dx * 2, x + 3 + dx * 2, y0 + 3, z, 1.5, P.iron, M.Metal, { noshadow = true }, "CannonBarrel")
			box(parent, x - 3, y0 + 1, z - 1.1, x + 3, y0 + 2.4, z + 1.1, P.darkwood, M.Wood, { noshadow = true }, "Carriage")
			cylZ(parent, x, y0 + 1.8, z - 1.9, z - 1.3, 3.6, P.darkwood, M.Wood, DECO, "Wheel")
			cylZ(parent, x, y0 + 1.8, z + 1.3, z + 1.9, 3.6, P.darkwood, M.Wood, DECO, "Wheel")
		else
			cylZ(parent, x, y0 + 3, z - 3 + dz * 2, z + 3 + dz * 2, 1.5, P.iron, M.Metal, { noshadow = true }, "CannonBarrel")
			box(parent, x - 1.1, y0 + 1, z - 3, x + 1.1, y0 + 2.4, z + 3, P.darkwood, M.Wood, { noshadow = true }, "Carriage")
			cylX(parent, x - 1.9, x - 1.3, y0 + 1.8, z, 3.6, P.darkwood, M.Wood, DECO, "Wheel")
			cylX(parent, x + 1.3, x + 1.9, y0 + 1.8, z, 3.6, P.darkwood, M.Wood, DECO, "Wheel")
		end
	end
	local function scatter(parent, x0, z0, x1, z1, n, y0)
		y0 = y0 or 0
		for _ = 1, n do
			local x, z = x0 + rnd() * (x1 - x0), z0 + rnd() * (z1 - z0)
			local k = rint(1, 4)
			if k == 1 then
				crate(parent, x, z, y0, 3)
				if rnd() < 0.5 then crate(parent, x + 3.1, z + 0.4, y0, 3) end
			elseif k == 2 then
				barrel(parent, x, z, y0)
				barrel(parent, x + 2.8, z + 0.6, y0)
			elseif k == 3 then
				crate(parent, x, z, y0, 4)
				crate(parent, x + 0.4, z - 0.3, y0 + 4, 3)
			else
				cart(parent, x, z, y0, rnd() < 0.5 and "X" or "Z")
			end
		end
	end

	---------------------------------------------------------------- row houses
	-- A row is a rectangle filled with terraced houses whose fronts look towards `face`.
	local function frame(x0, z0, x1, z1, face)
		local f = { face = face }
		if face == S then
			f.L, f.D = x1 - x0, z1 - z0
			f.map = function(u, v) return x0 + u, z1 - v end
		elseif face == N then
			f.L, f.D = x1 - x0, z1 - z0
			f.map = function(u, v) return x0 + u, z0 + v end
		elseif face == E then
			f.L, f.D = z1 - z0, x1 - x0
			f.map = function(u, v) return x1 - v, z0 + u end
		else
			f.L, f.D = z1 - z0, x1 - x0
			f.map = function(u, v) return x0 + v, z0 + u end
		end
		return f
	end
	local function lbox(f, parent, u0, v0, y0, u1, v1, y1, color, mat, o, name)
		local xa, za = f.map(u0, v0)
		local xb, zb = f.map(u1, v1)
		return box(parent, xa, y0, za, xb, y1, zb, color, mat, o, name)
	end
	local function lwedge(f, parent, u0, v0, y0, u1, v1, y1, toFront, color, mat, o, name)
		local xa, za = f.map(u0, v0)
		local xb, zb = f.map(u1, v1)
		return wedge(parent, xa, y0, za, xb, y1, zb, toFront and f.face or OPP[f.face], color, mat, o, name)
	end

	local FLOOR = 11
	local function house(f, m, u0, u1, floors, o, exposedA, exposedB)
		local D = f.D
		local w = u1 - u0
		local H = floors * FLOOR + 1.5
		local wallC, wallM
		if rnd() < 0.55 then wallC, wallM = pick(P.brick), M.Brick else wallC, wallM = pick(P.plaster), M.Plaster end
		lbox(f, m, u0, 0, 0, u1, D, H, wallC, wallM, nil, "Wall")

		local rh = min(D * 0.38, 12)
		local roofC, roofM = pick(P.slate), M.Slate
		if rnd() < 0.2 then roofC, roofM = P.tile, M.Slate end
		local bo = o.back and 0.8 or 0
		lwedge(f, m, u0, -0.8, H, u1, D / 2, H + rh, true, roofC, roofM, nil, "Roof")
		lwedge(f, m, u0, D / 2, H, u1, D + bo, H + rh, false, roofC, roofM, nil, "Roof")
		lbox(f, m, u0 + 1, D / 2 - 1.5, H + rh - 4, u0 + 4, D / 2 + 1.5, H + rh + 4, P.brick[4], M.Brick, DECO, "Chimney")

		local bays = max(2, floor(w / 7))
		local bw = w / bays
		local doorBay = rint(1, bays)
		local shop = o.shops and rnd() < o.shops
		if shop then
			lbox(f, m, u0 + 0.5, -0.4, 9, u1 - 0.5, 0, 10.8, pick(P.awning), M.Wood, DECO, "ShopSign")
			if rnd() < 0.4 then
				lwedge(f, m, u0 + 1, -5, 8, u1 - 1, -0.4, 10, true, pick(P.awning), M.Fabric, DECO, "Awning")
			end
		else
			lbox(f, m, u0, -0.3, FLOOR + 0.5, u1, 0, FLOOR + 1.5, P.stone, M.Limestone, DECO, "Band")
		end
		for fl = 0, floors - 1 do
			local yb = fl * FLOOR + 1.5
			for b = 1, bays do
				local uc = u0 + (b - 0.5) * bw
				if fl == 0 and b == doorBay then
					lbox(f, m, uc - 2.2, -0.25, 0, uc + 2.2, 0.25, 8, P.darkwood, M.Wood, DECO, "Door")
				elseif fl == 0 and shop then
					lbox(f, m, uc - bw / 2 + 0.8, -0.2, 1.8, uc + bw / 2 - 0.8, 0.3, 8.2, P.glass, M.Glass, DECO, "ShopWindow")
				else
					local col, mat = windowLook()
					lbox(f, m, uc - 1.9, -0.2, yb + 2.5, uc + 1.9, 0.3, yb + 8, col, mat, DECO, "Window")
				end
			end
		end
		if o.back then
			for fl = 0, floors - 1 do
				local yb = fl * FLOOR + 1.5
				for b = 1, 2 do
					local uc = u0 + (b * 2 - 1) * w / 4
					if fl == 0 and b == 1 then
						lbox(f, m, uc - 2, D - 0.25, 0, uc + 2, D + 0.25, 7.5, P.darkwood, M.Wood, DECO, "Door")
					else
						local col, mat = windowLook()
						lbox(f, m, uc - 1.7, D - 0.3, yb + 2.5, uc + 1.7, D + 0.2, yb + 8, col, mat, DECO, "Window")
					end
				end
			end
		end
		local function side(ue, sgn)
			for fl = 0, floors - 1 do
				local yb = fl * FLOOR + 1.5
				for _, vc in ipairs({ D * 0.3, D * 0.7 }) do
					local col, mat = windowLook()
					lbox(f, m, ue - 0.25, vc - 1.7, yb + 2.5, ue + 0.25, vc + 1.7, yb + 8, col, mat, DECO, "Window")
				end
			end
			-- raised gable so the exposed end reads as wall, not roof
			lwedge(f, m, ue - 0.3, -0.8, H, ue + 0.3, D / 2, H + rh + 0.5, true, wallC, wallM, DECO, "Gable")
			lwedge(f, m, ue - 0.3, D / 2, H, ue + 0.3, D + bo, H + rh + 0.5, false, wallC, wallM, DECO, "Gable")
		end
		if exposedA then side(u0, -1) end
		if exposedB then side(u1, 1) end
	end

	local FLOORS = { 2, 2, 3, 3, 3, 4 }
	local function row(parent, name, x0, z0, x1, z1, face, o)
		o = o or {}
		local f = frame(x0, z0, x1, z1, face)
		local m = model(parent, name, true)
		local n = max(1, floor(f.L / 21 + 0.5))
		local base = f.L / n
		local cuts = { 0 }
		for i = 1, n - 1 do
			cuts[#cuts + 1] = i * base + (rnd() - 0.5) * min(5, base * 0.25)
		end
		cuts[#cuts + 1] = f.L
		for i = 1, n do
			local fl = pick(FLOORS)
			if o.fmin then fl = max(fl, o.fmin) end
			if o.fmax then fl = min(fl, o.fmax) end
			house(f, m, cuts[i], cuts[i + 1], fl, o, o.sideA and i == 1, o.sideB and i == n)
		end
		return m
	end

	-- Upper storeys bridging an alley mouth.
	local function archway(parent, x0, z0, x1, z1)
		local c = pick(P.plaster)
		box(parent, x0, 10, z0, x1, 21, z1, c, M.Plaster, nil, "Archway")
		box(parent, x0 - 0.4, 21, z0 - 0.4, x1 + 0.4, 22, z1 + 0.4, P.slate[1], M.Slate, { noshadow = true }, "ArchwayRoof")
	end

	---------------------------------------------------------------- root
	local root = model(nil, "Liege1800s")
	local ground = model(root, "Ground")
	local westBank = folder(root, "WestBank")
	local eastBank = folder(root, "EastBank")
	local riverF = folder(root, "Meuse")
	local propsF = folder(root, "StreetProps")

	---------------------------------------------------------------- ground, river, limits
	do
		box(ground, -500, -14, -500, 106, 0, 500, P.cobble, M.Cobblestone, nil, "WestBankGround")
		box(ground, 234, -14, -500, 500, 0, 500, P.cobble, M.Cobblestone, nil, "EastBankGround")
		box(ground, 106, -14, -500, 110, 0, 500, P.stone, M.Limestone, nil, "QuayWallWest")
		box(ground, 230, -14, -500, 234, 0, 500, P.stone, M.Limestone, nil, "QuayWallEast")
		box(ground, 110, -14, -500, 230, -11, 500, P.mud, M.Mud, nil, "RiverBed")
		-- Waist-deep, wadeable.  Non-colliding so players walk the bed; swap for Terrain water if you prefer swimming.
		box(ground, 110, -11, -500, 230, -8, 500, P.water, M.SmoothPlastic, { nc = true, noshadow = true, t = 0.35, refl = 0.15 }, "MeuseWater")
			.CanQuery = false

		local pv = { noshadow = true }
		box(ground, -240, 0, -130, -76, 0.2, -56, P.paving, M.Pavement, pv, "PlaceDuMarche")
		box(ground, -330, 0, -56, -200, 0.2, 124, P.paving, M.Pavement, pv, "PlaceSaintLambert")
		box(ground, -360, 0, 156, -104, 0.2, 236, P.paving, M.Pavement, pv, "PlaceCathedrale")
		box(ground, -360, 0, 90, -330, 0.2, 156, P.paving, M.Pavement, pv, "PlaceDuTheatre")
		box(ground, 262, 0, 300, 470, 0.2, 372, P.paving, M.Pavement, pv, "PlaceDeLaGare")
		box(ground, 70, 0, -446, 106, 0.2, 440, C(118, 114, 106), M.Pavement, pv, "QuaiWest")
		box(ground, 234, 0, -446, 262, 0.2, 440, C(118, 114, 106), M.Pavement, pv, "QuaiEast")

		local lim = folder(root, "MapLimits")
		local inv = { t = 1, noshadow = true }
		box(lim, -500, -14, -500, 500, 240, -499, P.stone, M.SmoothPlastic, inv, "LimitN").CanQuery = false
		box(lim, -500, -14, 499, 500, 240, 500, P.stone, M.SmoothPlastic, inv, "LimitS").CanQuery = false
		box(lim, -500, -14, -499, -499, 240, 499, P.stone, M.SmoothPlastic, inv, "LimitW").CanQuery = false
		box(lim, 499, -14, -499, 500, 240, 499, P.stone, M.SmoothPlastic, inv, "LimitE").CanQuery = false
	end

	---------------------------------------------------------------- west bank: row houses
	do
		local rows = folder(westBank, "Houses")
		local SH = 0.5 -- shop chance on trading streets

		-- north perimeter + Hors-Château (west side backs onto the hillside terraces)
		row(rows, "RueSaintLeonard_N", -276, -500, 30, -470, S, { shops = 0.3, sideB = true })
		row(rows, "HorsChateau_W1", -276, -446, -240, -360, E, { sideA = true })
		row(rows, "HorsChateau_W2", -276, -352, -240, -272, E)
		row(rows, "HorsChateau_W3", -276, -264, -240, -192, E, { sideB = true })
		row(rows, "HorsChateau_W4", -276, -168, -240, -96, E, { sideA = true, sideB = true })

		-- N-S rows between the hill and the river, cut by Rue de la Clef and two alleys
		local segs = { { -446, -380, true, false }, { -370, -300, false, true }, { -280, -196, true, false } }
		for i, s in ipairs(segs) do
			local a, b, sa, sb = s[1], s[2], s[3], s[4]
			row(rows, "HorsChateau_E" .. i, -212, a, -180, b, W, { back = true, sideA = sa, sideB = sb })
			row(rows, "Feronstree_W" .. i, -136, a, -104, b, E, { back = true, shops = SH, sideA = sa, sideB = sb })
			row(rows, "Feronstree_E" .. i, -76, a, -44, b, W, { shops = SH, sideA = sa, sideB = sb })
			row(rows, "EnNeuvice_W" .. i, -44, a, -12, b, E, { shops = 0.3, sideA = sa, sideB = sb })
			row(rows, "EnNeuvice_E" .. i, 2, a, 34, b, W, { shops = 0.3, sideA = sa, sideB = sb })
			if i < 3 then
				row(rows, "QuaiDeLaBatte_" .. i, 34, a, 70, b, E, { shops = SH, sideA = sa, sideB = sb, fmin = 3 })
			end
		end
		row(rows, "HorsChateau_E4", -212, -184, -180, -162, W, { back = true })
		row(rows, "Feronstree_W4", -136, -184, -104, -162, E, { back = true, shops = SH })
		for _, r in ipairs({ { "Feronstree_E", -76, -44, W }, { "EnNeuvice_W", -44, -12, E }, { "EnNeuvice_E", 2, 34, W }, { "QuaiDeLaBatte_", 34, 70, E } }) do
			row(rows, r[1] .. "4", r[2], -184, r[3], -100, r[4], { shops = SH })
			row(rows, r[1] .. "5", r[2], -90, r[3], -48, r[4], { shops = SH })
		end

		-- Place du Marché north side, Rue Léopold, Place Saint-Lambert
		row(rows, "Marche_N1", -212, -162, -164, -130, S, { back = true, shops = 0.7, sideA = true, fmin = 3 })
		row(rows, "Marche_N2", -152, -162, -104, -130, S, { back = true, shops = 0.7, sideB = true, fmin = 3 })
		row(rows, "RueLeopold_N1", -76, -48, -12, -16, S, { shops = 0.7, sideA = true, sideB = true, fmin = 3 })
		row(rows, "RueLeopold_N2", 2, -48, 70, -16, S, { shops = 0.7, sideA = true, sideB = true, fmin = 3 })
		row(rows, "RueLeopold_S1", -200, 16, -104, 48, N, { back = true, shops = 0.7, sideA = true, sideB = true, fmin = 3 })
		row(rows, "RueLeopold_S2", -76, 16, -12, 48, N, { shops = 0.7, sideA = true, sideB = true, fmin = 3 })
		row(rows, "RueLeopold_S3", 2, 16, 70, 48, N, { shops = 0.7, sideA = true, sideB = true, fmin = 3 })
		row(rows, "SaintLambert_N", -330, -84, -240, -56, S, { shops = 0.5, sideB = true, fmin = 3 })
		row(rows, "SaintLambert_S", -330, 124, -200, 140, N, { shops = 0.5, sideA = true })
		row(rows, "Cathedrale_N1", -330, 140, -200, 156, S, { sideA = true })

		-- block between Place Saint-Lambert and Vinâve d'Île (courtyard inside)
		row(rows, "SaintLambert_E1", -200, 48, -168, 82, W, { back = true, shops = 0.4 })
		row(rows, "SaintLambert_E2", -200, 90, -168, 124, W, { back = true, shops = 0.4 })
		row(rows, "VinaveDIle_W1", -136, 48, -104, 82, E, { back = true, shops = SH })
		row(rows, "VinaveDIle_W2", -136, 90, -104, 124, E, { back = true, shops = SH })
		row(rows, "Cathedrale_N2", -200, 124, -104, 156, S, { back = true, sideB = true })

		-- southern town
		for _, s in ipairs({ { 48, 92, 98 }, { 112, 156, 106 }, { 178, 250 }, { 258, 298 } }) do
			local a, b = s[1], s[2]
			local i = tostring(a)
			local sideA, sideB = (a == 178), (b == 156)
			row(rows, "VinaveDIle_E" .. i, -76, a, -44, b, W, { shops = SH, sideA = sideA, sideB = sideB, fmin = 3 })
			row(rows, "SouverainPont_W" .. i, -44, a, -12, b, E, { sideA = sideA, sideB = sideB, fmin = 3 })
			-- the eastern pair has a plain alley instead of the wide Passage Lemonnier gap
			local a2, b2 = a, b
			if a == 48 then b2 = 98 elseif a == 112 then a2 = 106 end
			row(rows, "SouverainPont_E" .. i, 2, a2, 34, b2, W, { sideA = sideA, sideB = sideB })
			row(rows, "QuaiSurMeuse_" .. i, 34, a2, 70, b2, E, { shops = 0.3, sideA = sideA, sideB = sideB })
		end
		row(rows, "Sauveniere_N1", -76, 298, -12, 330, S, { sideA = true, sideB = true })
		row(rows, "Sauveniere_N2", 2, 298, 70, 330, S, { sideA = true, sideB = true })
		row(rows, "PlaceDuTheatre_S", -392, 250, -360, 330, E, { sideB = true })
		row(rows, "Sauveniere_S1", -392, 352, -250, 384, N, { back = true, sideB = true })
		row(rows, "Sauveniere_S2", -238, 352, -90, 384, N, { back = true, sideA = true, sideB = true })
		row(rows, "Sauveniere_S3", -78, 352, 10, 384, N, { back = true, sideA = true, sideB = true })
		row(rows, "Sauveniere_S4", 22, 352, 70, 384, N, { back = true, sideA = true, sideB = true })
		row(rows, "Guillemins_Backdrop", -392, 468, 106, 500, N, { fmin = 3 })

		-- alley mouths ("impasses")
		local arches = model(rows, "Archways", true)
		for _, z in ipairs({ { -380, -370 }, { -196, -184 } }) do
			archway(arches, -212, z[1], -202, z[2])
			archway(arches, -114, z[1], -104, z[2])
			archway(arches, -76, z[1], -66, z[2])
			archway(arches, 60, z[1], 70, z[2])
		end
		archway(arches, -164, -162, -152, -152) -- Marché -> back yards
		archway(arches, -250, -360, -240, -352) -- Impasse des Ursulines
		archway(arches, -250, -272, -240, -264) -- Impasse de l'Ange
		archway(arches, -76, -100, -66, -90)
		archway(arches, 60, -100, 70, -90)
		archway(arches, -200, 82, -190, 90)
		archway(arches, -114, 82, -104, 90)
		archway(arches, 60, 98, 70, 106)
		archway(arches, -76, 250, -66, 258)
		archway(arches, 60, 250, 70, 258)
		sign(arches, -239.7, 12.5, -356, 9, 1.6, E, "IMPASSE DES URSULINES")
		sign(arches, -239.7, 12.5, -268, 9, 1.6, E, "IMPASSE DE L'ANGE")
	end

	---------------------------------------------------------------- hillside terraces, stairs, citadel
	do
		local hill = folder(westBank, "CoteauxEtCitadelle")
		local body = model(hill, "Terraces", true)
		local wallC = C(124, 104, 88)
		-- terraces T1..T3 and the plateau, retaining walls in rough stone
		box(body, -307, 0, -500, -276, 16, -96, wallC, M.Cobblestone, nil, "Terrace1")
		box(body, -338, 0, -500, -307, 32, -96, wallC, M.Cobblestone, nil, "Terrace2")
		box(body, -369, 0, -500, -338, 48, -96, wallC, M.Cobblestone, nil, "Terrace3")
		box(body, -500, 0, -500, -369, 64, -96, wallC, M.Cobblestone, nil, "Plateau")
		box(body, -500, 0, -96, -392, 64, -84, wallC, M.Cobblestone, nil, "PlateauSpur")
		local g = { noshadow = true }
		box(body, -307, 16, -500, -276, 16.3, -96, P.grass, M.Grass, g, "Grass1")
		box(body, -338, 32, -500, -307, 32.3, -96, P.grass, M.Grass, g, "Grass2")
		box(body, -369, 48, -500, -338, 48.3, -96, P.grass, M.Grass, g, "Grass3")
		box(body, -400, 64, -500, -369, 64.3, -96, P.grass, M.Grass, g, "Glacis")
		box(body, -500, 64, -494, -414, 64.3, -102, P.sand, M.Sand, g, "ParadeGround")

		-- three ways up: each is four flights with a landing on every terrace
		local function hillStair(name, z0, z1)
			local m = model(hill, name, true)
			stairs(m, -276, z0, -244, z1, 0, 16, W, 0, P.stone, M.Limestone)
			for k = 1, 3 do
				local xTop = -276 - 31 * k
				stairs(m, xTop, z0, xTop + 25, z1, 16 * k, 16 * (k + 1), W, 16 * k, P.stone, M.Limestone)
			end
			return m
		end
		local bueren = hillStair("MontagneDeBueren", -191, -169)
		lamp(bueren, -279, -193, 16)
		lamp(bueren, -310, -167, 32)
		lamp(bueren, -341, -193, 48)
		sign(bueren, -240.2, 13, -197, 12, 1.8, E, "MONTAGNE DE BUEREN")
		hillStair("EscaliersDePierreuse", -470, -448)

		local deg = model(hill, "DegresDesBegards", true)
		stairs(deg, -276, -96, -244, -84, 0, 16, W, 0, P.stone, M.Limestone)
		box(deg, -284, 0, -96, -276, 16, -84, P.stone, M.Limestone, nil, "Landing")
		stairs(deg, -312, -96, -284, -84, 16, 32, W, 0, P.stone, M.Limestone)
		box(deg, -320, 0, -96, -312, 32, -84, P.stone, M.Limestone, nil, "Landing")
		stairs(deg, -346, -96, -320, -84, 32, 48, W, 0, P.stone, M.Limestone)
		box(deg, -354, 0, -96, -346, 48, -84, P.stone, M.Limestone, nil, "Landing")
		stairs(deg, -380, -96, -354, -84, 48, 64, W, 0, P.stone, M.Limestone)
		box(deg, -392, 0, -96, -380, 64, -84, P.stone, M.Limestone, nil, "Landing")

		-- stair-alleys climbing from Hors-Château to the first terrace
		local imp = model(hill, "Impasses", true)
		stairs(imp, -276, -360, -244, -352, 0, 16, W, 0, P.darkstone, M.Cobblestone)
		stairs(imp, -276, -272, -244, -264, 0, 16, W, 0, P.darkstone, M.Cobblestone)

		-- terrace gardens
		local gard = model(hill, "Gardens", true)
		for k = 1, 3 do
			local x0, y = -276 - 31 * k, 16 * k
			for _, z in ipairs({ -420, -390, -330, -300, -240, -215, -145, -120 }) do
				if rnd() < 0.8 then
					box(gard, x0 + 2, y, z - 0.6, x0 + 20, y + 4.5, z + 0.6, wallC, M.Cobblestone, { noshadow = true }, "GardenWall")
				end
			end
			for _, z in ipairs({ -435, -405, -372, -345, -315, -285, -255, -228, -205, -157, -132, -108 }) do
				local r = rnd()
				if r < 0.45 then
					tree(gard, x0 + 8 + rnd() * 14, z, y, 0.8 + rnd() * 0.4)
				elseif r < 0.65 then
					for i = 0, 2 do
						box(gard, x0 + 4, y, z - 5 + i * 5, x0 + 22, y + 2.2, z - 4 + i * 5, C(84, 104, 56), M.Grass, DECO, "Vines")
					end
				elseif r < 0.8 then
					box(gard, x0 + 2, y, z - 4, x0 + 10, y + 7, z + 4, pick(P.plaster), M.Plaster, nil, "Pavilion")
					wedge(gard, x0 + 1.5, y + 7, z - 4.5, x0 + 10.5, y + 10, z + 4.5, E, P.tile, M.Slate, { noshadow = true }, "PavilionRoof")
				end
			end
		end
		for _, z in ipairs({ -430, -350, -290, -230, -140, -110 }) do
			tree(gard, -384 + rnd() * 8, z, 64, 1)
		end

		-- citadel: rampart you can walk on, gate at the head of the Bueren stairs
		local cit = model(hill, "Citadelle", true)
		local rc = C(140, 96, 80)
		box(cit, -414, 64, -494, -400, 76, -188, rc, M.Brick, nil, "Rampart")
		box(cit, -414, 64, -172, -400, 76, -102, rc, M.Brick, nil, "Rampart")
		box(cit, -414, 73, -188, -400, 76, -172, rc, M.Brick, nil, "GateLintel")
		box(cit, -500, 64, -500, -400, 76, -494, rc, M.Brick, nil, "RampartN")
		box(cit, -500, 64, -102, -400, 76, -96, rc, M.Brick, nil, "RampartS")
		box(cit, -400.5, 64, -190, -399.5, 74.5, -188, P.stone, M.Limestone, DECO, "GateJamb")
		box(cit, -400.5, 64, -172, -399.5, 74.5, -170, P.stone, M.Limestone, DECO, "GateJamb")
		sign(cit, -399.7, 74.6, -180, 16, 1.8, E, "CITADELLE DE LIÈGE", P.stone, C(40, 36, 32))
		-- parapet with embrasures
		-- (left open where the two bastions join the wall-walk)
		local zs = { -494, -462, -456, -424, -380, -348, -342, -310, -304, -272, -266, -234, -228, -196, -190, -170, -164, -152, -112, -102 }
		for i = 1, #zs, 2 do
			box(cit, -402, 76, zs[i], -400, 79.5, zs[i + 1], rc, M.Brick, { noshadow = true }, "Parapet")
		end
		for _, z in ipairs({ -459, -345, -307, -231, -193 }) do
			cannon(cit, -404.5, z, 76, E)
		end
		-- bastions thrust out over the glacis
		for _, z in ipairs({ { -420, -384 }, { -150, -114 } }) do
			box(cit, -400, 64, z[1], -384, 76, z[2], rc, M.Brick, nil, "Bastion")
			local zm = (z[1] + z[2]) / 2
			box(cit, -386, 76, z[1], -384, 79.5, zm - 3, rc, M.Brick, { noshadow = true }, "Parapet")
			box(cit, -386, 76, zm + 3, -384, 79.5, z[2], rc, M.Brick, { noshadow = true }, "Parapet")
			cannon(cit, -389.5, zm, 76, E)
			box(cit, -400, 76, z[1], -386, 79.5, z[1] + 2, rc, M.Brick, { noshadow = true }, "Parapet")
			box(cit, -400, 76, z[2] - 2, -386, 79.5, z[2], rc, M.Brick, { noshadow = true }, "Parapet")
		end
		-- ramps up to the wall-walk
		for _, z in ipairs({ { -440, -430 }, { -250, -240 }, { -124, -114 } }) do
			wedge(cit, -438, 64, z[1], -414, 76, z[2], W, P.sand, M.Sand, nil, "RampartRamp")
		end
		-- barracks, magazine, flag
		box(cit, -499, 64, -480, -476, 88, -116, P.brick[2], M.Brick, nil, "Barracks")
		gableRoof(cit, -499, -480, -476, -116, 88, 9, "Z", P.slate[1], M.Slate, 0.8)
		winGrid(cit, E, -476, -476, -120, 22, { 68, 79 }, 3.2, 5.5)
		for _, z in ipairs({ -400, -298, -196 }) do
			box(cit, -476.3, 64, z - 3, -475.8, 72.5, z + 3, P.darkwood, M.Wood, DECO, "Door")
		end
		box(cit, -462, 64, -330, -440, 76, -300, P.darkstone, M.Cobblestone, nil, "PowderMagazine")
		gableRoof(cit, -462, -330, -440, -300, 76, 6, "Z", P.slate[3], M.Slate, 0.5)
		box(cit, -439.7, 64, -318, -439.3, 71, -312, P.iron, M.Metal, DECO, "MagazineDoor")
		cylY(cit, -450, 64, 100, -214, 0.7, P.lime, M.Wood, { noshadow = true }, "Flagpole")
		box(cit, -450, 91, -214, -447, 99, -213.8, C(20, 20, 20), M.Fabric, DECO, "FlagBlack")
		box(cit, -447, 91, -214, -444, 99, -213.8, C(232, 190, 40), M.Fabric, DECO, "FlagYellow")
		box(cit, -444, 91, -214, -441, 99, -213.8, C(190, 40, 44), M.Fabric, DECO, "FlagRed")
		for _, p in ipairs({ { -430, -206 }, { -430, -154 }, { -452, -360 } }) do
			ball(cit, p[1], 65, p[2], 2, P.iron, M.Metal, DECO, "Shot")
			ball(cit, p[1] + 2, 65, p[2], 2, P.iron, M.Metal, DECO, "Shot")
			ball(cit, p[1] + 1, 66.6, p[2], 2, P.iron, M.Metal, DECO, "Shot")
		end
		scatter(cit, -470, -470, -420, -120, 10, 64)
		lamp(cit, -418, -194, 64)
		lamp(cit, -418, -166, 64)
	end

	---------------------------------------------------------------- Place du Marché: Perron + Hôtel de Ville
	do
		local m = model(westBank, "HotelDeVille_LaViolette", true)
		local wc = P.brick[1]
		box(m, -200, 0, -56, -116, 30, -16, wc, M.Brick, nil, "Body")
		box(m, -200.3, 0, -56.3, -115.7, 3, -15.7, P.stone, M.Limestone, { noshadow = true }, "Plinth")
		box(m, -200.4, 29, -56.4, -115.6, 30.6, -15.6, P.lime, M.Limestone, { noshadow = true }, "Cornice")
		gableRoof(m, -200, -56, -116, -16, 30.6, 12, "X", P.slate[1], M.Slate, 0.6)
		box(m, -172, 0, -59, -144, 31, -56, P.lime, M.Limestone, nil, "AvantCorps")
		wedge(m, -172, 31, -59.4, -158, 38, -56, W, P.lime, M.Limestone, { noshadow = true }, "Pediment")
		wedge(m, -158, 31, -59.4, -144, 38, -56, E, P.lime, M.Limestone, { noshadow = true }, "Pediment")
		box(m, -168, 0, -69, -148, 5, -59, P.stone, M.Limestone, nil, "PerronLanding")
		stairs(m, -178, -69, -168, -59, 0, 5, E, 0, P.stone, M.Limestone)
		stairs(m, -148, -69, -138, -59, 0, 5, W, 0, P.stone, M.Limestone)
		box(m, -161.5, 5, -59.3, -154.5, 14, -58.8, P.darkwood, M.Wood, DECO, "Door")
		winGrid(m, N, -59, -170, -146, 3, { 18 }, 3.6, 7)
		winGrid(m, N, -56, -198, -174, 3, { 6, 18 }, 3.6, 7)
		winGrid(m, N, -56, -142, -118, 3, { 6, 18 }, 3.6, 7)
		winGrid(m, S, -16, -198, -118, 9, { 6, 18 }, 3.6, 7)
		winGrid(m, W, -200, -54, -18, 4, { 6, 18 }, 3.6, 7)
		winGrid(m, E, -116, -54, -18, 4, { 6, 18 }, 3.6, 7)
		box(m, -162, 41, -40, -154, 48, -32, P.lime, M.Limestone, { noshadow = true }, "BellTurret")
		ball(m, -158, 50, -36, 6, P.slate[1], M.Slate, DECO, "TurretDome")
		sign(m, -158, 16.2, -59.5, 14, 1.8, N, "HÔTEL DE VILLE", P.lime, C(40, 36, 32))

		local pr = model(westBank, "LePerron", true)
		local px, pz = -158, -96
		box(pr, px - 8, 0, pz - 8, px + 8, 1.2, pz + 8, P.stone, M.Limestone, nil, "Step")
		box(pr, px - 6, 1.2, pz - 6, px + 6, 2.4, pz + 6, P.stone, M.Limestone, nil, "Step")
		cylY(pr, px, 2.4, 5, pz, 9, P.stone, M.Limestone, nil, "Basin")
		box(pr, px - 2, 5, pz - 2, px + 2, 8, pz + 2, P.lime, M.Limestone, nil, "Pedestal")
		cylY(pr, px, 8, 22, pz, 1.8, P.lime, M.Limestone, { noshadow = true }, "Column")
		box(pr, px - 1.4, 22, pz - 1.4, px + 1.4, 23, pz + 1.4, P.lime, M.Limestone, DECO, "Capital")
		ball(pr, px, 24.3, pz, 2.8, P.brass, M.Metal, DECO, "PineCone")
		box(pr, px - 0.2, 25.5, pz - 0.2, px + 0.2, 28.5, pz + 0.2, P.brass, M.Metal, DECO, "Cross")
		box(pr, px - 1, 27, pz - 0.2, px + 1, 27.4, pz + 0.2, P.brass, M.Metal, DECO, "Cross")
		for _, d in ipairs({ { 3, 3 }, { -3, 3 }, { 3, -3 }, { -3, -3 } }) do
			box(pr, px + d[1] - 0.8, 5, pz + d[2] - 0.8, px + d[1] + 0.8, 6.6, pz + d[2] + 0.8, P.lime, M.Limestone, DECO, "Lion")
		end

		local mk = model(westBank, "MarcheStalls", true)
		for _, p in ipairs({ { -222, -118, S }, { -196, -118, S }, { -122, -118, S }, { -96, -118, S }, { -216, -72, N }, { -100, -74, N } }) do
			stall(mk, p[1], p[2], p[3])
		end
		scatter(mk, -230, -112, -180, -80, 3)
		scatter(mk, -136, -112, -86, -80, 3)
	end

	---------------------------------------------------------------- Palais des Princes-Évêques
	do
		local m = model(westBank, "PalaisDesPrincesEveques", true)
		local wc, wm = P.lime, M.Limestone
		box(m, -499, 0, -84, -330, 30, -56, wc, wm, nil, "WingN")
		box(m, -499, 0, 62, -416, 30, 90, wc, wm, nil, "WingS")
		box(m, -404, 0, 62, -330, 30, 90, wc, wm, nil, "WingS")
		box(m, -416, 14, 62, -404, 30, 90, wc, wm, nil, "PassageLintel")
		box(m, -499, 0, -56, -472, 30, 62, wc, wm, nil, "WingW")
		box(m, -358, 0, -56, -330, 30, -5, wc, wm, nil, "WingE")
		box(m, -358, 0, 13, -330, 30, 62, wc, wm, nil, "WingE")
		box(m, -358, 15, -5, -330, 30, 13, wc, wm, nil, "GateLintel")
		gableRoof(m, -499, -84, -330, -56, 30, 10, "X", P.slate[1])
		gableRoof(m, -499, 62, -330, 90, 30, 10, "X", P.slate[1])
		gableRoof(m, -499, -56, -472, 62, 30, 10, "Z", P.slate[1])
		gableRoof(m, -358, -56, -330, 62, 30, 10, "Z", P.slate[1])
		box(m, -472, 0, -56, -358, 0.2, 62, P.paving, M.Pavement, { noshadow = true }, "CourtPaving")
		-- arcaded gallery round the first court
		box(m, -472, 13, -56, -358, 14.5, -46, wc, wm, nil, "Gallery")
		box(m, -472, 13, 52, -358, 14.5, 62, wc, wm, nil, "Gallery")
		box(m, -472, 13, -46, -462, 14.5, 52, wc, wm, nil, "Gallery")
		box(m, -368, 13, -46, -358, 14.5, 52, wc, wm, nil, "Gallery")
		for i = 0, 8 do
			local x = -463 + i * 12
			cylY(m, x, 0, 13, -47, 2.4, P.stone, wm, { noshadow = true })
			cylY(m, x, 0, 13, 53, 2.4, P.stone, wm, { noshadow = true })
		end
		for i = 1, 7 do
			local z = -47 + i * 12.5
			cylY(m, -463, 0, 13, z, 2.4, P.stone, wm, { noshadow = true })
			if z < -8 or z > 16 then cylY(m, -367, 0, 13, z, 2.4, P.stone, wm, { noshadow = true }) end
		end
		winGrid(m, S, -56, -468, -362, 9, { 18 }, 3.6, 7)
		winGrid(m, N, 62, -468, -362, 9, { 18 }, 3.6, 7)
		winGrid(m, E, -472, -52, 58, 9, { 18 }, 3.6, 7)
		winGrid(m, W, -358, -52, 58, 9, { 18 }, 3.6, 7)
		winGrid(m, E, -330, -82, -8, 6, { 5, 18 }, 3.6, 7)
		winGrid(m, E, -330, 16, 88, 6, { 5, 18 }, 3.6, 7)
		winGrid(m, S, 90, -496, -420, 6, { 5, 18 }, 3.6, 7)
		winGrid(m, S, 90, -400, -334, 5, { 5, 18 }, 3.6, 7)
		sign(m, -329.7, 17.5, 4, 17, 2, E, "PALAIS DES PRINCES-ÉVÊQUES", wc, C(40, 36, 32))
		well(m, -415, 3, 0)
		tree(m, -445, -30, 0, 1)
		tree(m, -385, -30, 0, 1)
		tree(m, -445, 36, 0, 1)
		tree(m, -385, 36, 0, 1)
		scatter(m, -450, -20, -380, 30, 4)
		ceilingLamp(m, -344, 15, 4, 26)
		ceilingLamp(m, -410, 14, 76, 26)
	end

	---------------------------------------------------------------- Théâtre Royal + west gate
	do
		local m = model(westBank, "TheatreRoyal", true)
		box(m, -499, 0, 112, -372, 36, 250, P.plaster[4], M.Plaster, nil, "Body")
		gableRoof(m, -499, 112, -372, 250, 36, 14, "X", P.slate[2], M.Slate, 0.6)
		box(m, -372, 0, 140, -362, 2, 222, P.lime, M.Limestone, nil, "Podium")
		box(m, -362, 0, 140, -360, 1, 222, P.lime, M.Limestone, nil, "Step")
		for i = 0, 5 do
			cylY(m, -365.5, 2, 26, 148 + i * 13.2, 3, P.lime, M.Limestone, { noshadow = true })
		end
		box(m, -372, 26, 140, -361, 30, 222, P.lime, M.Limestone, nil, "Entablature")
		wedge(m, -372, 30, 140, -361, 39, 181, N, P.lime, M.Limestone, nil, "Pediment")
		wedge(m, -372, 30, 181, -361, 39, 222, S, P.lime, M.Limestone, nil, "Pediment")
		for i = 0, 4 do
			box(m, -372.3, 2, 151.6 + i * 13.2, -371.8, 13, 157.6 + i * 13.2, P.darkwood, M.Wood, DECO, "Door")
		end
		winGrid(m, E, -372, 150, 214, 5, { 16 }, 4, 7)
		winGrid(m, N, 112, -496, -376, 8, { 6, 20 }, 4, 8)
		sign(m, -360.7, 28, 181, 30, 2.2, E, "THÉÂTRE ROYAL", P.lime, C(40, 36, 32))

		local g = model(westBank, "PorteSainteMarguerite", true)
		box(g, -499, 0, 90, -494, 26, 112, P.stone, M.Limestone, nil, "GateWall")
		box(g, -494.3, 0, 94, -493.8, 16, 108, P.darkwood, M.WoodPlanks, DECO, "GateDoors")
		box(g, -494.5, 16, 92, -493.5, 18, 110, P.lime, M.Limestone, DECO, "GateLintel")
	end

	---------------------------------------------------------------- Cathédrale Saint-Paul (enterable nave)
	do
		local m = model(westBank, "CathedraleSaintPaul", true)
		local wc, wm = C(150, 146, 138), M.Limestone
		box(m, -320, 0, 266, -290, 72, 296, wc, wm, nil, "Tower")
		helm(m, -321, 265, -289, 297, 72, 42, P.slate[3])
		for _, s in ipairs({ { N, 266 }, { S, 296 } }) do
			winGrid(m, s[1], s[2], -316, -294, 2, { 52 }, 4, 11, 0)
		end
		winGrid(m, W, -320, 270, 292, 2, { 52 }, 4, 11, 0)
		box(m, -320.3, 0, 276, -319.8, 13, 286, P.darkwood, M.Wood, DECO, "TowerDoor")
		local win = {}
		for _, sd in ipairs({ N, S }) do
			win[#win + 1] = { sd, -226, -214, 0, 14 }
			for _, x in ipairs({ -272, -250, -190, -168 }) do
				win[#win + 1] = { sd, x - 3, x + 3, 10, 30 }
			end
		end
		win[#win + 1] = { E, 266, 296, 0, 30 }
		walls(m, -290, 250, -150, 312, 0, 40, 3, wc, wm, win)
		walls(m, -150, 262, -112, 300, 0, 34, 3, wc, wm, { { E, 276, 286, 10, 28 }, { S, -136, -130, 0, 9 } }, "NSE")
		box(m, -290, 0, 250, -112, 0.2, 312, C(110, 108, 104), M.Marble, { noshadow = true }, "Floor")
		gableRoof(m, -291, 249, -149, 313, 40, 20, "X", P.slate[3], M.Slate, 1)
		gableRoof(m, -150, 261, -111, 301, 34, 14, "X", P.slate[3], M.Slate, 1)
		for i = 0, 4 do
			local x = -270 + i * 25
			cylY(m, x, 0, 40, 268, 4, wc, wm, { noshadow = true })
			cylY(m, x, 0, 40, 294, 4, wc, wm, { noshadow = true })
		end
		for i = 0, 8 do
			local x = -265 + i * 10
			if x < -228 or x > -212 then
				box(m, x, 0, 272, x + 1.4, 3.2, 279, P.darkwood, M.Wood, { noshadow = true }, "Pew")
				box(m, x, 0, 283, x + 1.4, 3.2, 290, P.darkwood, M.Wood, { noshadow = true }, "Pew")
			end
		end
		box(m, -128, 0, 275, -122, 4, 287, P.lime, M.Marble, nil, "Altar")
		box(m, -125.3, 4, 280.6, -124.7, 11, 281.4, P.brass, M.Metal, DECO, "AltarCross")
		box(m, -125.3, 8, 279, -124.7, 8.8, 283, P.brass, M.Metal, DECO, "AltarCross")
		for _, x in ipairs({ -283, -261, -238, -202, -179, -157 }) do
			box(m, x - 2, 0, 246.5, x + 2, 30, 250, wc, wm, { noshadow = true }, "Buttress")
			box(m, x - 2, 0, 312, x + 2, 30, 315.5, wc, wm, { noshadow = true }, "Buttress")
		end
		ceilingLamp(m, -245, 30, 281, 40)
		ceilingLamp(m, -195, 30, 281, 40)
		ceilingLamp(m, -135, 26, 281, 30)
		tree(m, -340, 300, 0, 1.1)
		tree(m, -128, 240, 0, 1)
	end

	---------------------------------------------------------------- Passage Lemonnier (covered arcade)
	do
		local m = model(westBank, "PassageLemonnier", true)
		local wc = P.plaster[4]
		box(m, -76, 0, 92, -12, 26, 94, wc, M.Plaster, nil, "SideWall")
		box(m, -76, 0, 110, -12, 26, 112, wc, M.Plaster, nil, "SideWall")
		box(m, -76, 0, 94, -12, 0.2, 110, C(196, 190, 176), M.Marble, { noshadow = true }, "Floor")
		for _, z in ipairs({ { 94, 94.4 }, { 109.6, 110 } }) do
			box(m, -72, 1.5, z[1], -46, 8.5, z[2], P.glass, M.Glass, DECO, "ShopFront")
			box(m, -42, 1.5, z[1], -16, 8.5, z[2], P.glass, M.Glass, DECO, "ShopFront")
			box(m, -74, 9, z[1], -14, 10.6, z[2], P.awning[2], M.Wood, DECO, "ShopFascia")
			for _, x in ipairs({ -74, -44, -14 }) do
				box(m, x - 1, 0, z[1] - 0.1, x + 1, 24, z[2] + 0.1, P.lime, M.Limestone, DECO, "Pilaster")
			end
			winGrid(m, z[1] < 100 and S or N, z[1] < 100 and 94 or 110, -72, -16, 7, { 13.5 }, 3.2, 6, 0.4)
		end
		box(m, -76, 24, 94, -12, 24.6, 110, C(170, 190, 196), M.Glass, { t = 0.6, noshadow = true, nc = true }, "GlassRoof")
		for _, x in ipairs({ -76, -60, -44, -28, -12.6 }) do
			box(m, x, 23.6, 94, x + 0.6, 25.2, 110, P.iron, M.Metal, DECO, "RoofRib")
		end
		for _, x in ipairs({ -76, -14 }) do
			box(m, x, 15, 94, x + 2, 26, 110, wc, M.Plaster, nil, "EntranceArch")
		end
		sign(m, -76.2, 19.5, 102, 14, 2, W, "PASSAGE LEMONNIER", P.lime, C(40, 36, 32))
		sign(m, -11.8, 19.5, 102, 14, 2, E, "PASSAGE LEMONNIER", P.lime, C(40, 36, 32))
		ceilingLamp(m, -60, 23, 102, 26)
		ceilingLamp(m, -28, 23, 102, 26)
	end

	---------------------------------------------------------------- Maison Curtius (arms merchant's house on the quay)
	do
		local m = model(westBank, "MaisonCurtius", true)
		local wc = P.brick[1]
		box(m, 34, 0, -280, 70, 46, -232, wc, M.Brick, nil, "Body")
		for _, y in ipairs({ 11.5, 23, 34.5, 45 }) do
			box(m, 33.7, y, -280.3, 70.3, y + 1, -231.7, P.lime, M.Limestone, DECO, "Band")
		end
		gableRoof(m, 34, -280, 70, -232, 46, 20, "Z", P.slate[1], M.Slate, 0.8)
		box(m, 58, 0, -292, 70, 62, -280, wc, M.Brick, nil, "Tower")
		helm(m, 57.5, -292.5, 70.5, -279.5, 62, 16, P.slate[1])
		winGrid(m, E, 70, -278, -234, 5, { 3, 14.5, 26, 37.5 }, 3.6, 6.5)
		winGrid(m, N, -280, 36, 56, 3, { 3, 14.5, 26, 37.5 }, 3.6, 6.5)
		winGrid(m, W, 34, -278, -234, 5, { 14.5, 26, 37.5 }, 3.6, 6.5)
		winGrid(m, E, 70, -290, -282, 1, { 14.5, 26, 37.5, 50 }, 3, 6)
		box(m, 69.8, 0, -259, 70.3, 9, -253, P.darkwood, M.Wood, DECO, "Door")
		sign(m, 70.3, 11, -256, 12, 1.6, E, "MAISON CURTIUS", P.lime, C(40, 36, 32))
	end

	---------------------------------------------------------------- Halle aux Viandes (old meat hall on the quay) — enterable
	do
		local m = model(westBank, "HalleAuxViandes", true)
		local wc = P.brick[3]
		walls(m, 34, -232, 70, -196, 0, 20, 2, wc, M.Brick, {
			{ E, -218, -210, 0, 10 }, { E, -230, -222, 4, 12 }, { E, -206, -198, 4, 12 },
			{ S, 44, 52, 0, 10 }, { S, 57, 65, 4, 12 },
		})
		box(m, 34, 0, -232, 70, 0.15, -196, C(120, 112, 100), M.Pavement, { noshadow = true }, "Floor")
		box(m, 33.7, 19, -232.3, 70.3, 20.4, -195.7, P.lime, M.Limestone, { noshadow = true }, "Cornice")
		gableRoof(m, 34, -232, 70, -196, 20.4, 15, "Z", P.slate[1], M.Slate, 0.8)
		for _, p in ipairs({ { 46, -222 }, { 58, -222 }, { 46, -206 }, { 58, -206 } }) do
			cylY(m, p[1], 0, 20, p[2], 2, P.stone, M.Limestone, { noshadow = true })
		end
		box(m, 37, 0, -229, 40, 3.4, -214, P.wood, M.WoodPlanks, nil, "ButcherBlock")
		box(m, 37, 0, -209, 40, 3.4, -199, P.wood, M.WoodPlanks, nil, "ButcherBlock")
		box(m, 44, 0, -229.5, 66, 3.4, -227, P.wood, M.WoodPlanks, nil, "ButcherBlock")
		box(m, 36.2, 8, -229, 36.8, 8.6, -199, P.iron, M.Metal, DECO, "MeatRail")
		barrel(m, 64, -201, 0)
		barrel(m, 66.5, -203.5, 0)
		ceilingLamp(m, 52, 20, -214, 30)
		sign(m, 70.3, 13.5, -214, 16, 1.8, E, "HALLE AUX VIANDES", P.lime, C(40, 36, 32))
	end

	---------------------------------------------------------------- back yards between Hors-Château and Féronstrée
	do
		local y = model(westBank, "BackYards", true)
		local function yard(z0, z1)
			box(y, -180, 0, z0, -136, 0.15, z1, P.dirt, M.Ground, { noshadow = true }, "YardGround")
			local z = z0 + 11
			while z < z1 - 8 do
				for _, xs in ipairs({ { -180, -165 }, { -151, -136 } }) do
					box(y, xs[1], 0, z - 0.5, xs[2], 5.5, z + 0.5, C(120, 100, 86), M.Brick, { noshadow = true }, "YardWall")
					local xc, zc = (xs[1] + xs[2]) / 2, z + 10
					if zc < z1 - 5 then
						local r = rnd()
						if r < 0.3 then
							box(y, xc - 6, 0, zc - 4, xc + 6, 8, zc + 4, pick(P.brick), M.Brick, nil, "Workshop")
							wedge(y, xc - 6.5, 8, zc - 4.5, xc + 6.5, 11, zc + 4.5, xs[1] < -160 and E or W, P.tile, M.Slate, { noshadow = true }, "WorkshopRoof")
						elseif r < 0.5 then
							tree(y, xc, zc, 0, 0.9)
						elseif r < 0.7 then
							crate(y, xc, zc, 0, 4)
							crate(y, xc + 4.2, zc + 1, 0, 3)
							barrel(y, xc - 3.5, zc - 2, 0)
						elseif r < 0.82 then
							well(y, xc, zc, 0)
						else
							cart(y, xc, zc, 0, "Z")
						end
					end
				end
				z += 21
			end
		end
		yard(-446, -380)
		yard(-370, -300)
		yard(-280, -196)
		yard(-184, -162)
		for _, z in ipairs({ -446, -301, -280 }) do
			box(y, -180, 0, z, -164, 8, z + 1, C(120, 100, 86), M.Brick, nil, "YardGateWall")
			box(y, -152, 0, z, -136, 8, z + 1, C(120, 100, 86), M.Brick, nil, "YardGateWall")
		end
		-- courtyard of the Saint-Lambert / Vinâve block
		box(y, -168, 0, 48, -136, 0.15, 124, P.dirt, M.Ground, { noshadow = true }, "YardGround")
		well(y, -152, 104, 0)
		tree(y, -152, 64, 0, 1)
		scatter(y, -164, 52, -140, 120, 4)
		-- goods yard along the railway
		box(y, -392, 0, 384, 70, 0.15, 440, P.dirt, M.Ground, { noshadow = true }, "GoodsYardGround")
		for _, x in ipairs({ -360, -300, -190, -130, -40 }) do
			local wcol = pick(P.brick)
			box(y, x, 0, 400, x + 40, 14, 430, wcol, M.Brick, nil, "GoodsShed")
			gableRoof(y, x, 400, x + 40, 430, 14, 7, "X", P.slate[2], M.Slate, 1)
			box(y, x + 14, 0, 399.7, x + 26, 10, 400.2, P.darkwood, M.WoodPlanks, DECO, "ShedDoor")
		end
		scatter(y, -380, 388, 60, 398, 12)
		scatter(y, -255, 404, -200, 436, 3)
		scatter(y, -84, 404, -46, 436, 2)
		heap(y, 12, 404, 44, 428, 0, 8, P.coal, M.Slate)
	end

	---------------------------------------------------------------- Publémont hill + railway tunnel (south-west backdrop)
	do
		local m = model(westBank, "Publemont", true)
		local wallC = C(112, 100, 88)
		box(m, -499, 0, 250, -392, 44, 440, wallC, M.Cobblestone, nil, "Hill")
		box(m, -499, 0, 468, -392, 44, 499, wallC, M.Cobblestone, nil, "Hill")
		box(m, -499, 16, 440, -392, 44, 468, wallC, M.Cobblestone, nil, "TunnelCrown")
		box(m, -499, 0, 440, -398, 16, 468, C(12, 12, 14), M.SmoothPlastic, { noshadow = true }, "TunnelDark")
		box(m, -393, 0, 438, -391, 20, 441, P.stone, M.Limestone, nil, "PortalPier")
		box(m, -393, 0, 467, -391, 20, 470, P.stone, M.Limestone, nil, "PortalPier")
		box(m, -393, 16, 438, -391, 21, 470, P.stone, M.Limestone, nil, "PortalLintel")
		box(m, -499, 44, 250, -392, 44.3, 499, P.grass, M.Grass, { noshadow = true }, "HillGrass")
		for _ = 1, 12 do
			tree(m, -490 + rnd() * 90, 262 + rnd() * 226, 44, 0.9 + rnd() * 0.5)
		end
		-- Basilique Saint-Martin on the crest
		box(m, -470, 44, 300, -430, 74, 380, C(150, 146, 138), M.Limestone, nil, "SaintMartinNave")
		gableRoof(m, -470, 300, -430, 380, 74, 14, "Z", P.slate[3], M.Slate, 0.8)
		box(m, -462, 44, 276, -438, 104, 300, C(150, 146, 138), M.Limestone, nil, "SaintMartinTower")
		helm(m, -463, 275, -437, 301, 104, 14, P.slate[3])
		winGrid(m, E, -430, 306, 376, 5, { 52 }, 4, 14, 0)
	end

	---------------------------------------------------------------- the Meuse: bridges, water gate, quay stairs, barges
	do
		-- upside-down wedges under a deck read as shallow arches
		local function haunches(parent, xa, xb, z0, z1, yTop, rise, run, color, mat)
			wedge(parent, xa, yTop - rise, z0, xa + run, yTop, z1, E, color, mat, { flip = true, noshadow = true }, "ArchHaunch")
			wedge(parent, xb - run, yTop - rise, z0, xb, yTop, z1, W, color, mat, { flip = true, noshadow = true }, "ArchHaunch")
		end

		local pa = model(riverF, "PontDesArches", true)
		box(pa, 106, -2.5, -16, 234, 0, 16, P.stone, M.Limestone, nil, "Deck")
		box(pa, 106, 0, -16, 234, 0.2, 16, P.cobble, M.Cobblestone, { noshadow = true }, "Roadway")
		local prev = 110
		for _, x in ipairs({ 140, 170, 200, 230 }) do
			if x < 230 then box(pa, x - 3, -14, -17.5, x + 3, -2.5, 17.5, P.stone, M.Limestone, nil, "Pier") end
			haunches(pa, prev, (x < 230) and (x - 3) or 230, -16, 16, -2.5, 6, 9, P.stone, M.Limestone)
			prev = x + 3
		end
		box(pa, 110, 0, -16, 230, 3.2, -14.6, P.stone, M.Limestone, nil, "Parapet")
		box(pa, 110, 0, 14.6, 230, 3.2, 16, P.stone, M.Limestone, nil, "Parapet")
		for _, x in ipairs({ 125, 185 }) do
			lamp(pa, x, -15.3, 3.2)
			lamp(pa, x + 30, 15.3, 3.2)
		end
		sign(pa, 112, 4.6, -15.3, 14, 1.6, S, "PONT DES ARCHES", P.stone, C(40, 36, 32))

		local ps = model(riverF, "LaPasserelle", true)
		box(ps, 106, -1, 160, 234, 0, 174, P.wood, M.WoodPlanks, nil, "Deck")
		box(ps, 110, -2.2, 160, 230, -1, 161, P.iron, M.Metal, { noshadow = true }, "Girder")
		box(ps, 110, -2.2, 173, 230, -1, 174, P.iron, M.Metal, { noshadow = true }, "Girder")
		for _, x in ipairs({ 150, 190 }) do
			cylY(ps, x, -14, -2.2, 162, 2.6, P.iron, M.Metal, { noshadow = true }, "Pier")
			cylY(ps, x, -14, -2.2, 172, 2.6, P.iron, M.Metal, { noshadow = true }, "Pier")
		end
		for _, z in ipairs({ 160.3, 173.7 }) do
			box(ps, 110, 3.4, z - 0.25, 230, 3.9, z + 0.25, P.iron, M.Metal, { noshadow = true }, "Rail")
			for i = 0, 10 do
				box(ps, 110 + i * 12 - 0.2, 0, z - 0.2, 110 + i * 12 + 0.2, 3.4, z + 0.2, P.iron, M.Metal, DECO, "Baluster")
			end
			-- shallow bowstring arch
			plank(ps, 110, 3.9, z, 150, 9, z, 0.5, 0.6, P.iron, M.Metal, DECO, "Bowstring")
			box(ps, 150, 8.7, z - 0.25, 190, 9.3, z + 0.25, P.iron, M.Metal, DECO, "Bowstring")
			plank(ps, 190, 9, z, 230, 3.9, z, 0.5, 0.6, P.iron, M.Metal, DECO, "Bowstring")
		end
		lamp(ps, 108, 158.6, 0)
		lamp(ps, 232, 175.4, 0)

		-- north limit: fortified water gate with a wall-walk crossing
		local wg = model(riverF, "PorteDEau", true)
		local wc = C(120, 116, 110)
		for _, x in ipairs({ 110, 138, 166, 194, 222 }) do
			box(wg, x, -14, -492, x + 8, 6, -472, wc, M.Cobblestone, nil, "Pier")
		end
		for _, x in ipairs({ 118, 146, 174, 202 }) do
			haunches(wg, x, x + 20, -492, -472, 6, 6, 7, wc, M.Cobblestone)
			box(wg, x, -14, -484, x + 20, 6, -482.5, C(16, 17, 20), M.Metal, { noshadow = true }, "Portcullis")
		end
		box(wg, 110, 6, -492, 230, 22, -472, wc, M.Cobblestone, nil, "Curtain")
		box(wg, 110, 22, -492, 230, 27.5, -490, wc, M.Cobblestone, nil, "ParapetN")
		for i = 0, 11 do
			box(wg, 110 + i * 10, 22, -474, 116 + i * 10, 25, -472, wc, M.Cobblestone, { noshadow = true }, "Merlon")
		end
		for _, t in ipairs({ { 48, 110, 92, 110, 48, 92, E }, { 230, 292, 230, 248, 248, 292, W } }) do
			box(wg, t[1], 0, -499, t[2], 22, -486, wc, M.Cobblestone, nil, "Bastion")
			box(wg, t[3], 0, -486, t[4], 22, -470, wc, M.Cobblestone, nil, "StairHead")
			stairs(wg, t[5], -486, t[6], -470, 0, 22, t[7], 0, wc, M.Cobblestone)
			box(wg, t[1], 22, -499, t[2], 27.5, -497, wc, M.Cobblestone, { noshadow = true }, "ParapetN")
			box(wg, t[3], 22, -499, t[4], 40, -488, wc, M.Cobblestone, nil, "Turret")
			helm(wg, t[3] - 0.6, -499.4, t[4] + 0.6, -487.4, 40, 12, P.slate[3])
			winGrid(wg, S, -488, t[3] + 2, t[4] - 2, 2, { 30 }, 2, 5, 0.5)
		end
		box(wg, 92, 22, -471.5, 110, 25, -470, wc, M.Cobblestone, { noshadow = true }, "ParapetS")
		box(wg, 230, 22, -471.5, 248, 25, -470, wc, M.Cobblestone, { noshadow = true }, "ParapetS")
		lamp(wg, 108, -480, 22)
		lamp(wg, 232, -480, 22)

		-- south limit: railway bridge (Val-Benoît line into the Longdoz yard)
		local rb = model(riverF, "PontDuChemindeFer", true)
		box(rb, 106, -3, 440, 234, 0, 468, P.darkstone, M.Limestone, nil, "Deck")
		prev = 110
		for _, x in ipairs({ 140, 170, 200, 230 }) do
			if x < 230 then box(rb, x - 3, -14, 439, x + 3, -3, 469, P.darkstone, M.Limestone, nil, "Pier") end
			haunches(rb, prev, (x < 230) and (x - 3) or 230, 440, 468, -3, 6, 9, P.darkstone, M.Limestone)
			prev = x + 3
		end
		box(rb, 106, 0, 466.5, 234, 11, 468, P.iron, M.Metal, nil, "PlateGirder")
		for i = 0, 8 do
			box(rb, 110 + i * 15 - 0.4, 0, 466.1, 110 + i * 15 + 0.4, 11, 466.5, P.iron, M.Metal, DECO, "Stiffener")
		end
		box(rb, 110, 0, 440, 230, 3, 440.5, P.iron, M.Metal, { noshadow = true }, "Railing")
		box(rb, 106, 0, 468, 234, 14, 499, C(14, 15, 18), M.SmoothPlastic, { t = 1, noshadow = true }, "LimitBehindBridge").CanQuery = false

		-- stairs down to the water on both quays
		local qs = model(riverF, "QuayStairs", true)
		for _, s in ipairs({ { -330, -308, N }, { -60, -38, S }, { 100, 122, N }, { 300, 322, S } }) do
			stairs(qs, 110, s[1], 116, s[2], -11, 0, s[3], -14, P.stone, M.Limestone)
		end
		for _, s in ipairs({ { -420, -398, N }, { -300, -278, S }, { 30, 52, N }, { 200, 222, S } }) do
			stairs(qs, 224, s[1], 230, s[2], -11, 0, s[3], -14, P.stone, M.Limestone)
		end

		-- coal and grain barges: bow ramps let waders climb aboard, gangplanks reach the quay
		local function barge(name, x0, x1, z0, z1, quayX, cargo)
			local b = model(riverF, name, true)
			local hc = C(52, 40, 32)
			box(b, x0, -10.6, z0 + 8, x1, -5, z1 - 8, hc, M.WoodPlanks, nil, "Hull")
			wedge(b, x0, -10.6, z0, x1, -5, z0 + 8, N, hc, M.WoodPlanks, nil, "Bow")
			wedge(b, x0, -10.6, z1 - 8, x1, -5, z1, S, hc, M.WoodPlanks, nil, "Stern")
			box(b, x0 + 2, -5, z1 - 20, x1 - 2, 0.5, z1 - 10, P.plaster[5], M.WoodPlanks, nil, "Cabin")
			box(b, x0 + 1.5, 0.5, z1 - 20.5, x1 - 1.5, 1.1, z1 - 9.5, hc, M.WoodPlanks, { noshadow = true }, "CabinRoof")
			if cargo == "coal" then
				heap(b, x0 + 2, z0 + 12, x1 - 2, z1 - 24, -5, 4, P.coal, M.Slate)
			else
				for i = 0, 3 do
					crate(b, (x0 + x1) / 2 - 3 + (i % 2) * 6, z0 + 14 + i * 5, -5, 4)
				end
			end
			local zc = z0 + 11
			plank(b, quayX, 0.1, zc, (quayX < x0) and (x0 + 2) or (x1 - 2), -4.9, zc, 4, 0.4, P.wood, M.WoodPlanks, nil, "Gangplank")
			cylY(b, (x0 + x1) / 2, -5, 9, z0 + 10, 0.7, P.darkwood, M.Wood, DECO, "Mast")
		end
		barge("Barge_LaBatte", 116, 132, -270, -212, 110, "crates")
		barge("Barge_QuaiSurMeuse", 116, 132, 40, 96, 110, "coal")
		barge("Barge_Tanneurs", 208, 224, -200, -144, 230, "coal")
		barge("Barge_Longdoz", 208, 224, 236, 292, 230, "crates")
		-- a few rowing boats as stepping stones mid-river
		local boats = model(riverF, "RowingBoats", true)
		for _, p in ipairs({ { 160, -330 }, { 176, -120 }, { 150, 100 }, { 184, 330 }, { 168, 232 } }) do
			box(boats, p[1] - 2.5, -9, p[2] - 6, p[1] + 2.5, -6.6, p[2] + 6, P.wood, M.WoodPlanks, { noshadow = true }, "RowingBoat")
			wedge(boats, p[1] - 2.5, -9, p[2] - 9, p[1] + 2.5, -6.6, p[2] - 6, N, P.wood, M.WoodPlanks, { noshadow = true }, "BoatBow")
		end
	end

	---------------------------------------------------------------- railway: track, trains
	do
		local rail = model(root, "Railway", true)
		box(rail, -392, 0, 440, 470, 0.15, 468, C(92, 86, 78), M.Pebble, { noshadow = true }, "Ballast")
		for _, zc in ipairs({ 447, 459 }) do
			box(rail, -398, 0.15, zc - 3.4, 472, 0.3, zc + 3.4, C(66, 50, 38), M.WoodPlanks, { noshadow = true }, "Sleepers")
			box(rail, -398, 0.3, zc - 2.6, 472, 0.75, zc - 2.2, P.iron, M.Metal, { noshadow = true }, "RailL")
			box(rail, -398, 0.3, zc + 2.2, 472, 0.75, zc + 2.6, P.iron, M.Metal, { noshadow = true }, "RailR")
		end

		local function wheels(m, xs, zc, d)
			for _, x in ipairs(xs) do
				cylZ(m, x, 0.75 + d / 2, zc - 3.3, zc - 2.5, d, P.iron, M.Metal, DECO, "Wheel")
				cylZ(m, x, 0.75 + d / 2, zc + 2.5, zc + 3.3, d, P.iron, M.Metal, DECO, "Wheel")
			end
		end
		local function wagon(parent, x0, zc, kind)
			local m = model(parent, "Wagon_" .. kind)
			box(m, x0, 2.6, zc - 3, x0 + 20, 3.6, zc + 3, P.darkwood, M.WoodPlanks, nil, "Frame")
			wheels(m, { x0 + 4, x0 + 16 }, zc, 3.4)
			if kind == "van" then
				box(m, x0 + 0.4, 3.6, zc - 3.1, x0 + 19.6, 11.5, zc + 3.1, C(110, 66, 50), M.WoodPlanks, nil, "Body")
				box(m, x0, 11.5, zc - 3.4, x0 + 20, 12.1, zc + 3.4, P.slate[2], M.Metal, { noshadow = true }, "Roof")
			elseif kind == "coal" then
				box(m, x0 + 0.4, 3.6, zc - 3.1, x0 + 19.6, 7.4, zc + 3.1, C(70, 62, 56), M.WoodPlanks, nil, "Body")
				box(m, x0 + 1, 7.4, zc - 2.6, x0 + 19, 8.4, zc + 2.6, P.coal, M.Slate, { noshadow = true }, "Coal")
			else
				crate(m, x0 + 5, zc, 3.6, 4)
				crate(m, x0 + 14, zc - 0.5, 3.6, 4)
			end
		end
		local function loco(parent, x0, zc)
			local m = model(parent, "Locomotive")
			local green = C(40, 66, 52)
			box(m, x0, 2.4, zc - 3, x0 + 44, 3.4, zc + 3, P.iron, M.Metal, nil, "Frame")
			cylX(m, x0 + 2, x0 + 24, 6.8, zc, 6.6, green, M.Metal, nil, "Boiler")
			cylX(m, x0 + 1, x0 + 2.4, 6.8, zc, 7, P.iron, M.Metal, { noshadow = true }, "Smokebox")
			cylY(m, x0 + 4.5, 9.8, 15, zc, 2, P.iron, M.Metal, { noshadow = true }, "Chimney")
			smoke(m, x0 + 4.5, 15.6, zc, 3, 0.3, 6, C(214, 214, 214))
			cylY(m, x0 + 13, 9.8, 12, zc, 2.6, P.brass, M.Metal, DECO, "Dome")
			box(m, x0 + 24, 3.4, zc - 3.3, x0 + 31, 12.5, zc + 3.3, green, M.Metal, nil, "Cab")
			box(m, x0 + 23.4, 12.5, zc - 3.7, x0 + 32, 13.1, zc + 3.7, P.iron, M.Metal, { noshadow = true }, "CabRoof")
			wheels(m, { x0 + 8, x0 + 14, x0 + 20 }, zc, 5)
			box(m, x0 + 33, 3.4, zc - 3, x0 + 44, 9, zc + 3, green, M.Metal, nil, "Tender")
			box(m, x0 + 34, 9, zc - 2.5, x0 + 43, 10, zc + 2.5, P.coal, M.Slate, { noshadow = true }, "Coal")
			wheels(m, { x0 + 35.5, x0 + 41.5 }, zc, 3.4)
		end
		local trains = model(rail, "Trains", true)
		loco(trains, 300, 447)
		wagon(trains, 346, 447, "van")
		wagon(trains, 368, 447, "flat")
		wagon(trains, 390, 447, "van")
		local kinds = { "coal", "coal", "van", "coal", "van", "flat", "coal", "van", "coal", "coal", "van" }
		for i, k in ipairs(kinds) do
			wagon(trains, 92 + (i - 1) * 22, 459, k)
		end
		wagon(trains, -300, 459, "van")
		wagon(trains, -278, 459, "coal")
		wagon(trains, -120, 447, "flat")
		wagon(trains, -98, 447, "van")
	end

	---------------------------------------------------------------- east bank: Outremeuse + Longdoz
	do
		local rows = folder(eastBank, "Houses")
		row(rows, "RueSaintLeonard_NE", 310, -500, 499, -470, S, { shops = 0.2, sideA = true })
		row(rows, "Derivation_Backdrop_N", 470, -470, 499, -16, W, { fmin = 3 })
		row(rows, "Derivation_Backdrop_S", 470, 16, 499, 430, W, { fmin = 3 })
		row(rows, "Longdoz_Backdrop", 234, 468, 499, 499, N, { fmin = 3 })

		for i, s in ipairs({ { -446, -380 }, { -370, -250 }, { -230, -126 } }) do
			row(rows, "QuaiDesTanneurs_" .. i, 262, s[1], 294, s[2], W, { back = true, shops = 0.3, sideA = true, sideB = true })
			row(rows, "PuitsEnSock_W" .. i, 308, s[1], 340, s[2], E, { back = true, shops = 0.5, sideA = true, sideB = true })
		end
		row(rows, "PuitsEnSock_E1", 366, -446, 398, -356, W, { back = true, shops = 0.4, sideA = true })
		row(rows, "PuitsEnSock_E2", 366, -344, 398, -250, W, { back = true, shops = 0.4, sideB = true })
		row(rows, "PuitsEnSock_E3", 366, -230, 398, -170, W, { back = true, shops = 0.4, sideA = true })
		row(rows, "PuitsEnSock_E4", 366, -116, 398, -16, W, { back = true, shops = 0.4, sideA = true, sideB = true })
		row(rows, "QuaiDeLongdoz_1", 262, 56, 294, 156, W, { back = true, sideB = true })
		row(rows, "QuaiDeLongdoz_2", 262, 178, 294, 300, W, { back = true, sideA = true, sideB = true })
		row(rows, "PuitsEnSock_W4", 308, 16, 340, 156, E, { back = true, shops = 0.4, sideA = true, sideB = true })
		row(rows, "PuitsEnSock_W5", 308, 178, 340, 300, E, { back = true, sideA = true, sideB = true })

		local arches = model(rows, "Archways", true)
		archway(arches, 366, -356, 376, -344)
		archway(arches, 262, -380, 272, -370)
		archway(arches, 330, -380, 340, -370)
		sign(arches, 365.7, 12.5, -350, 10, 1.6, W, "BANC D'ÉPREUVES")

		-- yard lane between the two Outremeuse rows
		local yards = model(eastBank, "Yards", true)
		box(yards, 294, 0, -446, 308, 0.15, -126, P.dirt, M.Ground, { noshadow = true }, "LaneGround")
		box(yards, 294, 0, 56, 308, 0.15, 300, P.dirt, M.Ground, { noshadow = true }, "LaneGround")
		box(yards, 398, 0, -446, 470, 0.15, -16, P.dirt, M.Ground, { noshadow = true }, "YardGround")
		for _, z in ipairs({ -420, -340, -300, -200, -160, 90, 130, 210, 260 }) do
			if rnd() < 0.5 then barrel(yards, 296.5, z, 0) else crate(yards, 305, z, 0, 3) end
			-- washing lines
			box(yards, 294, 13, z + 6, 308, 13.15, z + 6.15, P.lime, M.Fabric, DECO, "Line")
			box(yards, 297, 10, z + 6, 300, 13, z + 6.1, pick(P.plaster), M.Fabric, DECO, "Washing")
			box(yards, 302, 10.6, z + 6, 304.5, 13, z + 6.1, pick(P.plaster), M.Fabric, DECO, "Washing")
		end
		-- gunmakers' back-yard workshops (work was farmed out house to house)
		for _, p in ipairs({ { 404, -446, 430, -424 }, { 440, -446, 468, -420 }, { 404, -290, 426, -262 }, { 444, -286, 468, -256 },
			{ 404, -228, 428, -200 }, { 446, -220, 468, -186 }, { 404, -104, 430, -78 }, { 440, -70, 468, -36 }, { 404, -56, 424, -26 } }) do
			local c = pick(P.brick)
			box(yards, p[1], 0, p[2], p[3], 10, p[4], c, M.Brick, nil, "Workshop")
			gableRoof(yards, p[1], p[2], p[3], p[4], 10, 5, "X", rnd() < 0.5 and P.tile or P.slate[2], M.Slate, 0.6)
			box(yards, p[1] + 3, 0, p[4] - 0.2, p[1] + 7, 7.5, p[4] + 0.25, P.darkwood, M.Wood, DECO, "Door")
			winGrid(yards, S, p[4], p[1] + 9, p[3] - 1, 2, { 3 }, 3.4, 4.5, 0.3)
			box(yards, p[3] - 4, 10, p[2] + 2, p[3] - 1.5, 19, p[2] + 4.5, P.brick[4], M.Brick, DECO, "ForgeChimney")
			if rnd() < 0.5 then smoke(yards, p[3] - 2.75, 20, p[2] + 3.25, 2.5, 0.2, 3.5) end
		end
		for _, z in ipairs({ -250, -172, -116 }) do
			box(yards, 398, 0, z, 420, 6, z + 1, C(120, 100, 86), M.Brick, { noshadow = true }, "YardWall")
			box(yards, 432, 0, z, 470, 6, z + 1, C(120, 100, 86), M.Brick, { noshadow = true }, "YardWall")
		end
		tree(yards, 436, -238, 0, 1)
		tree(yards, 452, -150, 0, 1.1)
		tree(yards, 416, -140, 0, 0.9)
		well(yards, 436, -130, 0)
		scatter(yards, 402, -420, 466, -30, 16)

		-- Église Saint-Pholien at the bridgehead
		local ch = model(eastBank, "EgliseSaintPholien", true)
		local sc = C(156, 150, 140)
		box(ch, 268, 0, -84, 290, 56, -56, sc, M.Limestone, nil, "Tower")
		helm(ch, 267, -85, 291, -55, 56, 28, P.slate[3])
		box(ch, 290, 0, -96, 336, 30, -44, sc, M.Limestone, nil, "Nave")
		gableRoof(ch, 290, -96, 336, -44, 30, 16, "X", P.slate[3], M.Slate, 0.8)
		winGrid(ch, N, -96, 294, 332, 4, { 8 }, 4, 15, 0.3)
		winGrid(ch, S, -44, 294, 332, 4, { 8 }, 4, 15, 0.3)
		winGrid(ch, W, 268, -80, -60, 1, { 38 }, 4, 9, 0)
		box(ch, 267.7, 0, -75, 268.2, 12, -65, P.darkwood, M.Wood, DECO, "Door")
		box(ch, 262, 0, -116, 340, 0.15, -16, P.grass, M.Grass, { noshadow = true }, "Churchyard")
		box(ch, 262, 0, -117, 300, 4, -116, sc, M.Cobblestone, { noshadow = true }, "ChurchyardWall")
		box(ch, 312, 0, -117, 340, 4, -116, sc, M.Cobblestone, { noshadow = true }, "ChurchyardWall")
		tree(ch, 276, -104, 0, 1)
		tree(ch, 322, -30, 0, 1.1)
		tree(ch, 280, -30, 0, 0.9)
		for i = 0, 4 do
			box(ch, 300 + i * 7, 0, -110, 302 + i * 7, 3, -109.3, P.darkstone, M.Slate, { noshadow = true }, "Headstone")
		end

		-- Atelier L. Dolne, armurier (maker of the "Apache" knuckleduster revolver) — enterable
		local at = model(eastBank, "AtelierDolne", true)
		local ac = P.brick[3]
		walls(at, 366, -170, 410, -126, 0, 14, 1.5, ac, M.Brick, {
			{ W, -152, -146, 0, 8 }, { W, -164, -157, 3, 9 }, { W, -141, -134, 3, 9 },
			{ E, -151, -145, 0, 8 }, { S, 378, 386, 3, 9 }, { S, 396, 404, 3, 9 },
		})
		box(at, 366, 0, -170, 410, 0.15, -126, C(110, 86, 62), M.WoodPlanks, { noshadow = true }, "Floor")
		box(at, 366, 14, -170, 410, 25, -126, ac, M.Brick, nil, "UpperFloor")
		gableRoof(at, 366, -170, 410, -126, 25, 12, "Z", P.slate[1], M.Slate, 0.8)
		winGrid(at, W, 366, -168, -128, 5, { 16.5 }, 3.4, 5.5, 0.3)
		winGrid(at, S, -126, 370, 406, 4, { 16.5 }, 3.4, 5.5, 0.3)
		box(at, 388.5, 0, -168.5, 389.5, 14, -153, ac, M.Brick, nil, "Partition")
		box(at, 388.5, 0, -144, 389.5, 14, -127.5, ac, M.Brick, nil, "Partition")
		box(at, 373, 0, -167, 375.4, 3.6, -156, P.darkwood, M.Wood, nil, "Counter")
		box(at, 367.6, 4, -140, 368.2, 10, -129, P.darkwood, M.Wood, DECO, "GunRack")
		box(at, 380, 5, -168.4, 388, 10, -167.9, P.darkwood, M.Wood, DECO, "GunRack")
		for i = 0, 3 do
			box(at, 381 + i * 2, 5.4, -167.9, 381.3 + i * 2, 9.4, -167.6, P.iron, M.Metal, DECO, "Barrel")
		end
		box(at, 392, 0, -131.5, 406, 3.2, -128, P.wood, M.WoodPlanks, nil, "Workbench")
		box(at, 394, 3.2, -130.6, 396, 4.4, -129, P.iron, M.Metal, DECO, "Vice")
		box(at, 401, 0, -168.5, 408.5, 4, -161, P.brick[4], M.Brick, nil, "Forge")
		fireGlow(box(at, 402, 4, -167.5, 407.5, 4.5, -162, P.ember, M.Neon, DECO, "Embers"), 24, 1.6, 4)
		smoke(at, 404.75, 43, -165.25, 3, 0.22, 4)
		box(at, 401, 9, -168.5, 408.5, 14, -161, P.brick[4], M.Brick, { noshadow = true }, "ForgeHood")
		box(at, 403, 25, -167, 406.5, 42, -163.5, P.brick[4], M.Brick, nil, "Chimney")
		box(at, 396, 0, -158, 399, 2.4, -156.4, P.iron, M.Metal, nil, "Anvil")
		barrel(at, 393, -165, 0)
		crate(at, 384, -131, 0, 3)
		ceilingLamp(at, 378, 14, -148, 24)
		ceilingLamp(at, 400, 14, -148, 24)
		sign(at, 365.7, 11.4, -149, 22, 2.6, W, "L. DOLNE — ARMURIER", C(34, 46, 40), C(232, 206, 140))

		-- Banc d'Épreuves (proof house) — enterable firing gallery
		local bp = model(eastBank, "BancDEpreuves", true)
		local bc = P.brick[2]
		walls(bp, 404, -410, 468, -300, 0, 18, 2, bc, M.Brick, {
			{ W, -356, -344, 0, 10 }, { W, -400, -388, 9, 15 }, { W, -380, -368, 9, 15 }, { W, -334, -322, 9, 15 }, { W, -316, -306, 9, 15 },
			{ S, 414, 422, 0, 9 }, { N, 414, 422, 0, 9 },
		})
		box(bp, 404, 0, -410, 468, 0.15, -300, C(120, 112, 100), M.Pavement, { noshadow = true }, "Floor")
		gableRoof(bp, 404, -410, 468, -300, 18, 12, "Z", P.slate[2], M.Slate, 0.8)
		wedge(bp, 456, 0, -408, 466, 8, -302, W, P.sand, M.Sand, nil, "SandButt")
		for _, z in ipairs({ -390, -372, -354, -336, -318 }) do
			box(bp, 436, 0, z - 0.75, 458, 10, z + 0.75, bc, M.Brick, nil, "StallWall")
		end
		for _, z in ipairs({ -399, -381, -363, -345, -327, -309 }) do
			box(bp, 432, 0, z - 3, 435, 3.4, z + 3, P.wood, M.WoodPlanks, nil, "ProofBench")
			cylX(bp, 431, 437, 4, z, 0.7, P.iron, M.Metal, DECO, "ProofBarrel")
		end
		box(bp, 408, 0, -398, 412, 3.2, -372, P.wood, M.WoodPlanks, nil, "LoadingTable")
		box(bp, 408, 0, -332, 412, 3.2, -310, P.wood, M.WoodPlanks, nil, "LoadingTable")
		scatter(bp, 414, -400, 426, -310, 4)
		ceilingLamp(bp, 420, 18, -384, 34)
		ceilingLamp(bp, 420, 18, -326, 34)
		ceilingLamp(bp, 446, 18, -355, 34)
		sign(bp, 403.7, 12.5, -350, 30, 2.6, W, "BANC D'ÉPREUVES DES ARMES À FEU", C(34, 40, 52), C(232, 214, 168))

		-- Estaminet on the quay — enterable
		local es = model(eastBank, "Estaminet", true)
		local ec = P.plaster[2]
		walls(es, 262, 16, 300, 56, 0, 13, 1.5, ec, M.Plaster, {
			{ W, 32, 38, 0, 8 }, { W, 20, 28, 3, 9 }, { W, 42, 50, 3, 9 },
			{ N, 278, 284, 0, 8 }, { N, 266, 274, 3, 9 }, { N, 288, 296, 3, 9 }, { E, 44, 50, 0, 8 },
		})
		box(es, 262, 0, 16, 300, 0.15, 56, C(110, 86, 62), M.WoodPlanks, { noshadow = true }, "Floor")
		box(es, 262, 13, 16, 300, 24, 56, ec, M.Plaster, nil, "UpperFloor")
		gableRoof(es, 262, 16, 300, 56, 24, 11, "Z", P.tile, M.Slate, 0.8)
		winGrid(es, W, 262, 18, 54, 4, { 15.5 }, 3.4, 5.5, 0.5)
		winGrid(es, N, 16, 264, 298, 4, { 15.5 }, 3.4, 5.5, 0.5)
		box(es, 289, 0, 22, 291.4, 3.8, 42, P.darkwood, M.Wood, nil, "Bar")
		box(es, 297, 0, 20, 298.5, 9, 40, P.darkwood, M.Wood, DECO, "BottleShelf")
		for _, p in ipairs({ { 270, 24 }, { 279, 34 }, { 270, 45 }, { 281, 48 } }) do
			cylY(es, p[1], 0, 2.8, p[2], 0.8, P.darkwood, M.Wood, DECO, "TableLeg")
			cylY(es, p[1], 2.8, 3.2, p[2], 5, P.wood, M.WoodPlanks, { noshadow = true }, "Table")
		end
		box(es, 268, 0, 53, 278, 7, 54.5, P.brick[4], M.Brick, nil, "Fireplace")
		fireGlow(box(es, 270, 0.4, 52.7, 276, 3, 53.1, P.ember, M.Neon, DECO, "Fire"), 22, 1.4, 4)
		box(es, 271, 24, 51, 275, 39, 54.5, P.brick[4], M.Brick, { noshadow = true }, "Chimney")
		smoke(es, 273, 40, 52.75, 3, 0.2, 4)
		barrel(es, 294, 50, 0)
		barrel(es, 296.5, 52.5, 0)
		ceilingLamp(es, 276, 13, 36, 26)
		sign(es, 261.7, 10.6, 35, 20, 2.2, W, "ESTAMINET — AU PERRON D'OR", C(96, 40, 34), C(238, 214, 150))

		-- Fonderie Royale de Canons — enterable foundry hall with stacks
		local fo = model(eastBank, "FonderieDeCanons", true)
		local fc = P.brick[4]
		walls(fo, 376, 30, 470, 150, 0, 24, 2, fc, M.Brick, {
			{ W, 80, 96, 0, 14 }, { W, 40, 52, 6, 16 }, { W, 58, 70, 6, 16 }, { W, 106, 118, 6, 16 }, { W, 124, 136, 6, 16 },
			{ N, 400, 408, 0, 9 }, { S, 420, 430, 0, 10 },
		})
		box(fo, 376, 0, 30, 470, 0.15, 150, C(86, 80, 74), M.Ground, { noshadow = true }, "Floor")
		gableRoof(fo, 376, 30, 470, 90, 24, 12, "X", P.slate[3], M.Slate, 0.8)
		gableRoof(fo, 376, 90, 470, 150, 24, 12, "X", P.slate[3], M.Slate, 0.8)
		for _, z in ipairs({ 36, 134 }) do
			box(fo, 454, 0, z, 464, 62, z + 10, P.brick[2], M.Brick, nil, "Stack")
			box(fo, 455.5, 62, z + 1.5, 462.5, 98, z + 8.5, P.brick[2], M.Brick, nil, "Stack")
			box(fo, 455, 98, z + 1, 463, 100, z + 9, P.darkstone, M.Limestone, { noshadow = true }, "StackCap")
			smoke(fo, 459, 101, z + 5, 16, 0.38, 9, C(62, 58, 56))
		end
		for _, z in ipairs({ 56, 106 }) do
			box(fo, 440, 0, z, 458, 13, z + 18, P.brick[1], M.Brick, nil, "Furnace")
			fireGlow(box(fo, 439.6, 2, z + 5, 440.1, 7, z + 13, P.ember, M.Neon, DECO, "FurnaceMouth"), 34, 2, 7)
			box(fo, 420, 0, z + 2, 432, 0.5, z + 16, P.sand, M.Sand, { noshadow = true }, "CastingPit")
			cylY(fo, 426, 0.5, 4, z + 9, 4, P.iron, M.Metal, { noshadow = true }, "Mould")
		end
		for i = 0, 2 do
			cylZ(fo, 392 + i * 7, 3, 110, 126, 2.2, P.iron, M.Metal, nil, "CannonCasting")
			box(fo, 390 + i * 7, 0, 113, 394 + i * 7, 1.9, 115, P.wood, M.Wood, DECO, "Trestle")
			box(fo, 390 + i * 7, 0, 121, 394 + i * 7, 1.9, 123, P.wood, M.Wood, DECO, "Trestle")
		end
		cylY(fo, 410, 0, 20, 70, 1.6, P.darkwood, M.Wood, { noshadow = true }, "CranePost")
		plank(fo, 410, 19, 70, 426, 16, 64, 1, 1, P.darkwood, M.Wood, DECO, "CraneJib")
		heap(fo, 382, 36, 398, 52, 0, 6, P.coal, M.Slate)
		scatter(fo, 384, 60, 400, 100, 4)
		scatter(fo, 384, 130, 440, 146, 3)
		ceilingLamp(fo, 400, 24, 90, 36)
		sign(fo, 375.7, 18.5, 88, 34, 2.8, W, "FONDERIE ROYALE DE CANONS", C(40, 38, 36), C(232, 214, 168))

		-- coal yard
		local cy = model(eastBank, "CoalYard", true)
		local yc = C(110, 92, 80)
		box(cy, 366, 0, 178, 470, 0.15, 300, C(60, 56, 54), M.Ground, { noshadow = true }, "YardGround")
		box(cy, 366, 0, 178, 367.5, 9, 230, yc, M.Brick, nil, "YardWall")
		box(cy, 366, 0, 246, 367.5, 9, 300, yc, M.Brick, nil, "YardWall")
		box(cy, 367.5, 0, 178, 420, 9, 179.5, yc, M.Brick, nil, "YardWall")
		box(cy, 432, 0, 178, 470, 9, 179.5, yc, M.Brick, nil, "YardWall")
		box(cy, 367.5, 0, 298.5, 406, 9, 300, yc, M.Brick, nil, "YardWall")
		box(cy, 418, 0, 298.5, 470, 9, 300, yc, M.Brick, nil, "YardWall")
		for _, p in ipairs({ { 376, 188, 404, 212 }, { 414, 190, 440, 216 }, { 446, 196, 466, 232 }, { 378, 256, 410, 290 }, { 424, 250, 462, 288 } }) do
			heap(cy, p[1], p[2], p[3], p[4], 0, 7 + rnd() * 4, P.coal, M.Slate)
		end
		box(cy, 372, 0, 222, 384, 9, 232, P.plaster[3], M.Plaster, nil, "WeighHouse")
		wedge(cy, 371.5, 9, 221.5, 384.5, 12, 232.5, S, P.slate[1], M.Slate, { noshadow = true }, "WeighHouseRoof")
		cart(cy, 392, 238, 0, "X")
		cart(cy, 414, 234, 0, "Z")
		cylY(cy, 412, 0, 16, 240, 1.2, P.darkwood, M.Wood, { noshadow = true }, "CranePost")
		plank(cy, 412, 15.5, 240, 422, 12, 244, 0.8, 0.8, P.darkwood, M.Wood, DECO, "CraneJib")
		sign(cy, 365.7, 10.5, 238, 18, 2, W, "CHARBONNAGES DE LONGDOZ", C(30, 30, 32), C(226, 212, 176))

		-- Gare de Longdoz
		local st = model(eastBank, "GareDeLongdoz", true)
		local gc = P.plaster[1]
		box(st, 300, 0, 384, 352, 22, 426, gc, M.Plaster, nil, "WingW")
		box(st, 368, 0, 384, 420, 22, 426, gc, M.Plaster, nil, "WingE")
		box(st, 352, 14, 384, 368, 27, 426, gc, M.Plaster, nil, "ClockBlock")
		gableRoof(st, 300, 384, 352, 426, 22, 9, "X", P.slate[2])
		gableRoof(st, 368, 384, 420, 426, 22, 9, "X", P.slate[2])
		gableRoof(st, 352, 384, 368, 426, 27, 6, "Z", P.slate[2])
		cylZ(st, 360, 21, 383.4, 384.2, 5, P.lime, M.SmoothPlastic, DECO, "Clock")
		winGrid(st, N, 384, 304, 348, 5, { 3, 13 }, 3.6, 6.5)
		winGrid(st, N, 384, 372, 416, 5, { 3, 13 }, 3.6, 6.5)
		winGrid(st, S, 426, 304, 348, 5, { 13 }, 3.6, 6.5)
		winGrid(st, S, 426, 372, 416, 5, { 13 }, 3.6, 6.5)
		sign(st, 360, 16, 383.6, 15, 2, N, "GARE DE LONGDOZ", gc, C(40, 36, 32))
		box(st, 262, 0, 426, 470, 0.8, 440, P.stone, M.Limestone, nil, "Platform")
		box(st, 280, 13, 425, 450, 13.8, 442.5, P.slate[2], M.Metal, nil, "Canopy")
		for i = 0, 8 do
			cylY(st, 284 + i * 20.5, 0.8, 13, 439, 0.8, P.iron, M.Metal, DECO, "CanopyPost")
		end
		ceilingLamp(st, 360, 14, 405, 30)
		for _, x in ipairs({ 310, 410 }) do
			ceilingLamp(st, x, 13, 433, 26)
		end
		box(st, 470, 0, 430, 499, 26, 468, P.brick[2], M.Brick, nil, "EngineShed")
		box(st, 469.6, 0, 442, 470.1, 14, 452, C(14, 14, 16), M.SmoothPlastic, DECO, "ShedDoor")
		box(st, 469.6, 0, 454, 470.1, 14, 464, C(14, 14, 16), M.SmoothPlastic, DECO, "ShedDoor")
		scatter(st, 270, 428, 296, 438, 2, 0.8)
		scatter(st, 430, 428, 462, 438, 2, 0.8)
		scatter(st, 270, 310, 460, 366, 6)
		lamp(st, 300, 336)
		lamp(st, 420, 336)

		-- east gate closing the Chaussée des Prés
		local eg = model(eastBank, "PorteDAmercoeur", true)
		box(eg, 470, 0, -16, 499, 32, 16, P.stone, M.Limestone, nil, "Gatehouse")
		gableRoof(eg, 470, -16, 499, 16, 32, 10, "Z", P.slate[3])
		box(eg, 469.6, 0, -8, 470.1, 15, 8, P.darkwood, M.WoodPlanks, DECO, "GateDoors")
		box(eg, 469.4, 15, -10, 470.4, 17, 10, P.lime, M.Limestone, DECO, "GateLintel")
		winGrid(eg, W, 470, -12, 12, 3, { 21 }, 3, 6, 0.4)
		sign(eg, 469.5, 18.6, 0, 16, 1.8, W, "PORTE D'AMERCŒUR", P.lime, C(40, 36, 32))
	end

	---------------------------------------------------------------- street furniture
	do
		local lamps = model(propsF, "GasLamps", true)
		for _, z in ipairs({ -430, -370, -310, -250, -210, -150 }) do
			lamp(lamps, -238.5, z)
			lamp(lamps, -77.5, z + 30)
		end
		for _, z in ipairs({ -420, -340, -260, -180, -100, -28, 40, 120, 200, 280, 360 }) do
			lamp(lamps, 104, z)
			lamp(lamps, 236, z + 20)
		end
		for _, x in ipairs({ -180, -120, -40, 40 }) do
			lamp(lamps, x, -14.5)
			lamp(lamps, x + 30, 14.5)
		end
		for _, p in ipairs({ { -236, -126 }, { -80, -126 }, { -236, -60 }, { -80, -60 }, { -326, -50 }, { -204, -50 }, { -326, 118 }, { -204, 118 },
			{ -265, 30 }, { -356, 160 }, { -108, 160 }, { -356, 232 }, { -232, 196 }, { -90, 60 }, { -90, 140 }, { -90, 220 }, { -90, 300 },
			{ -300, 334 }, { -180, 334 }, { -40, 334 }, { -5, -420 }, { -5, -240 }, { -5, -120 }, { -5, 70 }, { -5, 210 } }) do
			lamp(lamps, p[1], p[2])
		end
		for _, z in ipairs({ -430, -340, -280, -190, -100, 60, 120, 200, 270 }) do
			lamp(lamps, 342, z)
		end
		for _, x in ipairs({ 280, 330, 400, 450 }) do
			lamp(lamps, x, -14.5)
			lamp(lamps, x + 10, 164)
		end
		for _, x in ipairs({ -200, -100, 0, 260, 400 }) do
			lamp(lamps, x, -448)
		end

		-- La Batte: the riverside market
		local batte = model(propsF, "MarcheDeLaBatte", true)
		for i = 0, 13 do
			local z = -424 + i * 26
			if z < -296 or z > -274 then stall(batte, 82 + (i % 2) * 10, z, (i % 2 == 0) and E or W) end
		end
		scatter(batte, 76, -430, 100, -60, 12)
		scatter(batte, 76, 30, 100, 150, 5)
		scatter(batte, 76, 190, 100, 420, 8)
		sign(batte, 70.3, 12.5, -338, 12, 1.6, E, "QUAI DE LA BATTE")

		local misc = model(propsF, "Clutter", true)
		scatter(misc, -234, -440, -218, -140, 8) -- Hors-Château
		scatter(misc, -100, -440, -80, -140, 8) -- Féronstrée
		scatter(misc, -10, -440, 0, -30, 6) -- En Neuvice
		scatter(misc, -320, -40, -210, 110, 7) -- Place Saint-Lambert
		scatter(misc, -350, 164, -112, 228, 7) -- Place Cathédrale
		scatter(misc, -100, 30, -80, 320, 7) -- Vinâve d'Île
		scatter(misc, -380, 334, 60, 348, 8) -- Sauvenière
		scatter(misc, 238, -440, 258, 420, 16) -- east quay
		scatter(misc, 344, -440, 362, 290, 14) -- Puits-en-Sock
		scatter(misc, 270, -10, 460, 10, 4)
		scatter(misc, 240, 160, 460, 174, 5)
		-- omnibus on Place Saint-Lambert
		box(misc, -292, 3, 60, -276, 10, 68, C(60, 84, 70), M.WoodPlanks, nil, "Omnibus")
		box(misc, -293, 10, 59.5, -275, 10.6, 68.5, P.darkwood, M.Wood, { noshadow = true }, "OmnibusRoof")
		for _, x in ipairs({ -289, -279 }) do
			cylZ(misc, x, 2.2, 59.2, 60, 4.4, P.darkwood, M.Wood, DECO, "Wheel")
			cylZ(misc, x, 2.2, 68, 68.8, 4.4, P.darkwood, M.Wood, DECO, "Wheel")
		end
		cylY(misc, -265, 0, 3, 30, 14, P.stone, M.Limestone, nil, "FountainBasin")
		cylY(misc, -265, 2.4, 3.05, 30, 12, C(40, 60, 66), M.SmoothPlastic, DECO, "FountainWater")
		cylY(misc, -265, 3, 9, 30, 2, P.lime, M.Limestone, { noshadow = true }, "FountainColumn")
		for _, p in ipairs({ { -340, 170 }, { -340, 222 }, { -120, 170 }, { -120, 222 }, { -300, 100 }, { -230, 100 } }) do
			tree(misc, p[1], p[2], 0, 1)
		end

		local names = model(propsF, "StreetNames", true)
		sign(names, -212.3, 12.5, -440, 10, 1.6, W, "EN HORS-CHÂTEAU")
		sign(names, -103.7, 12.5, -440, 9, 1.6, E, "FÉRONSTRÉE")
		sign(names, -11.7, 12.5, -40, 8, 1.6, E, "EN NEUVICE")
		sign(names, -60, 12.5, -15.7, 10, 1.6, S, "RUE LÉOPOLD")
		sign(names, -150, 12.5, -129.7, 12, 1.6, S, "PLACE DU MARCHÉ")
		sign(names, -260, 12.5, -55.7, 15, 1.6, S, "PLACE SAINT-LAMBERT")
		sign(names, -76.3, 12.5, 60, 10, 1.6, W, "VINÂVE D'ÎLE")
		sign(names, 339.7, 12.5, -240, 12, 1.6, E, "RUE PUITS-EN-SOCK")
		sign(names, 261.7, 12.5, -300, 12, 1.6, W, "QUAI DES TANNEURS")
		sign(names, 380, 12.5, -15.7, 12, 1.6, S, "CHAUSSÉE DES PRÉS")
	end

	---------------------------------------------------------------- spawn markers
	do
		local sp = folder(root, "SpawnMarkers")
		local pts = {
			{ -200, 0, -100 }, { -265, 0, 60 }, { -226, 0, -420 }, { -90, 0, -330 }, { 90, 0, -300 }, { 90, 0, 250 },
			{ -90, 0, 200 }, { -230, 0, 196 }, { -200, 0, 341 }, { -150, 0, 392 }, { -430, 0, 20 }, { -440, 64, -250 },
			{ -322, 32, -300 }, { -5, 0, -140 }, { -158, 0, -240 }, { 248, 0, -350 }, { 353, 0, -300 }, { 353, 0, 90 },
			{ 300, 0, 0 }, { 430, 0, -200 }, { 360, 0, 340 }, { 400, 0, 240 }, { 248, 0, 250 }, { 400, 0, -458 },
		}
		for i, p in ipairs(pts) do
			local s
			if SPAWN_LOCATIONS then
				s = Instance.new("SpawnLocation")
				s.Neutral = true
			else
				s = Instance.new("Part")
			end
			s.Name = string.format("Spawn%02d", i)
			s.Anchored = true
			s.CanCollide = false
			s.CanTouch = false
			s.CanQuery = false
			s.CastShadow = false
			s.Transparency = 1
			s.Size = Vector3.new(6, 1, 6)
			s.CFrame = CFrame.new(p[1], p[2] + 3.5, p[3])
			s:SetAttribute("LiegeSpawn", true)
			s.Parent = sp
		end
		stats.spawns = #pts
	end

	---------------------------------------------------------------- ambience: lighting scripts + interior zones
	-- The scripts (src/Ambience) apply the mood to Lighting on their own once the map is in Workspace.
	local ambience = folder(root, "Ambience")
	ambience:SetAttribute("ManageLighting", true)
	ambience:SetAttribute("Mood", "Dusk")
	ambience:SetAttribute("CycleMinutes", 0)
	ambience:SetAttribute("InteriorGrading", true)
	ambience:SetAttribute("FireFlicker", true)
	do
		-- Volumes the client script tests the camera against; each carries its own colour grade.
		local zones = folder(ambience, "InteriorZones")
		local function zone(name, x0, y0, z0, x1, y1, z1, tint, brightness, contrast, saturation)
			local p = box(zones, x0, y0, z0, x1, y1, z1, P.lit, M.SmoothPlastic, { deco = true, t = 1 }, name)
			p:SetAttribute("Tint", tint)
			p:SetAttribute("Brightness", brightness)
			p:SetAttribute("Contrast", contrast)
			p:SetAttribute("Saturation", saturation)
		end
		zone("AtelierDolne", 367, 0, -169, 409, 14, -127, C(255, 214, 170), -0.04, 0.1, -0.05) -- forge glow
		zone("BancDEpreuves", 405, 0, -409, 467, 18, -301, C(236, 228, 214), -0.06, 0.12, -0.2) -- powder smoke
		zone("Estaminet", 263, 0, 17, 299, 13, 55, C(255, 206, 150), -0.03, 0.08, 0.05) -- lamplit and warm
		zone("FonderieDeCanons", 377, 0, 31, 469, 24, 149, C(255, 190, 140), -0.05, 0.16, 0) -- furnace heat
		zone("CathedraleSaintPaul", -289, 0, 251, -113, 40, 311, C(214, 224, 255), -0.08, 0.1, -0.15) -- cold stone
		zone("HalleAuxViandes", 35, 0, -231, 69, 20, -197, C(240, 226, 206), -0.05, 0.1, -0.1)
		zone("PassageLemonnier", -76, 0, 94, -12, 24, 110, C(255, 236, 206), 0.02, 0.04, 0.05) -- gaslit arcade
	end
	if config.scripts then
		local core = Instance.new("ModuleScript")
		core.Name = "AmbienceCore"
		core.Source = config.scripts.core
		core.Parent = ambience
		local server = Instance.new("Script")
		server.Name = "LiegeAmbience"
		server.Source = config.scripts.server
		server.Parent = ambience
		local client = Instance.new("Script")
		client.Name = "LiegeAmbienceClient"
		client.RunContext = Enum.RunContext.Client
		client.Source = config.scripts.client
		client.Parent = ambience
	end

	return root, stats
end
