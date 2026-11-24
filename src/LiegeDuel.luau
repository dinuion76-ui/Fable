--!nocheck
--[[
	Le Bief — a 250 × 250 stud duel map: a corner of Outremeuse, Liège, around 1870.

	Returns a function:   build(config?, R?) -> Model, stats
	  config.seed      number   house variation (default 1871)
	  config.scripts   table    { core, server, client } sources of src/Ambience; when given, the lighting
	                            scripts are embedded in the model (the Lune build does this)
	  R                table    { Instance, Vector3, CFrame, Color3, Enum, UDim2, Font }; defaults to the
	                            Roblox globals, so the same file runs in Studio and under Lune.

	Footprint: x and z in [-125, 125]. North = -Z, east = +X. Street level y = 0.
	The canal (le bief) runs east-west through the middle: bed y = -5, water surface y = -2.

	The map is point-symmetric (180° about the centre): everything on the Red side (north, -Z) has an
	identical twin on the Blue side (south, +Z), built by running the same half-builder twice. Only the
	team colours differ. Each side has a spawn courtyard with three exits and three lanes to the canal:
	the gunsmiths' alley (narrow, on each team's right), the square (centre) and the market (wide, on the
	left). The canal is crossed by a footbridge on each flank, by the two staggered bridges over the
	Perron island in the middle, or by wading.

	Only Part / WedgePart primitives: no unions, meshes or textures.
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

	local N, S, E, W = "N", "S", "E", "W"
	local OPP = { N = S, S = N, E = W, W = E }
	local PI = math.pi
	local YAW = { N = 0, S = PI, W = PI / 2, E = -PI / 2 }
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
		stone = C(128, 132, 135),
		darkstone = C(96, 98, 102),
		lime = C(188, 181, 164),
		brick = { C(142, 74, 58), C(122, 64, 52), C(156, 88, 66), C(108, 60, 50), C(134, 82, 68) },
		plaster = { C(206, 192, 162), C(192, 164, 116), C(160, 158, 150), C(214, 208, 190), C(150, 160, 136), C(184, 146, 130) },
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
		canvas = C(196, 184, 158),
		ember = C(255, 120, 40),
		brass = C(176, 140, 70),
		green = C(48, 74, 58),
		awning = { C(150, 54, 44), C(60, 84, 70), C(190, 170, 120), C(110, 96, 70) },
		leaf = { C(74, 104, 54), C(94, 112, 52), C(122, 108, 50) },
		poster = { C(214, 196, 150), C(186, 70, 54), C(64, 90, 120), C(230, 214, 170) },
	}
	local TEAMS = {
		{ name = "Red", color = C(166, 34, 32), dark = C(104, 22, 22), xf = CFrame.new() },
		{ name = "Blue", color = C(38, 68, 148), dark = C(24, 42, 94), xf = CFrame.Angles(0, PI, 0) },
	}
	local GOLD = C(232, 192, 64)

	---------------------------------------------------------------- RNG (reset per half, so both halves match)
	local baseSeed = (config.seed or 1871) % 2147483647
	if baseSeed <= 0 then baseSeed = 1871 end
	local seed = baseSeed
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
	-- Everything is authored in "half" coordinates; XF maps them to the world (identity for Red,
	-- a 180° turn about the centre for Blue).
	local XF = CFrame.new()
	local stats = { parts = 0, lights = 0, signs = 0 }

	local function finish(p, parent, name, color, mat, o, cf)
		p.Name = name or "Part"
		p.Anchored = true
		p.CanTouch = false
		p.TopSurface = SMOOTH
		p.BottomSurface = SMOOTH
		p.Color = color
		p.Material = mat
		p.CFrame = XF * cf
		if o then
			if o.deco then
				p.CanCollide = false
				p.CanQuery = false
				p.CastShadow = false
			end
			if o.nc then p.CanCollide = false end
			if o.nq then p.CanQuery = false end
			if o.noshadow then p.CastShadow = false end
			if o.t then p.Transparency = o.t end
			if o.refl then p.Reflectance = o.refl end
		end
		if name == "Window" and mat == M.Neon then p:AddTag("LiegeLitWindow") end
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
		return finish(p, parent, name, color, mat, o, CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2))
	end
	-- Wedge filling the box; the slope descends towards `dir`. o.flip puts the flat face on top.
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
		return finish(p, parent, name or "Wedge", color, mat, o, cf)
	end
	local function cylY(parent, cx, y0, y1, cz, d, color, mat, o, name)
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(y1 - y0, d, d)
		return finish(p, parent, name or "Column", color, mat, o, CFrame.new(cx, (y0 + y1) / 2, cz) * CFrame.Angles(0, 0, PI / 2))
	end
	local function cylX(parent, x0, x1, cy, cz, d, color, mat, o, name)
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(x1 - x0, d, d)
		return finish(p, parent, name or "Cylinder", color, mat, o, CFrame.new((x0 + x1) / 2, cy, cz))
	end
	local function cylZ(parent, cx, cy, z0, z1, d, color, mat, o, name)
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(z1 - z0, d, d)
		return finish(p, parent, name or "Cylinder", color, mat, o, CFrame.new(cx, cy, (z0 + z1) / 2) * CFrame.Angles(0, PI / 2, 0))
	end
	local function ball(parent, cx, cy, cz, d, color, mat, o, name)
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.new(d, d, d)
		return finish(p, parent, name or "Ball", color, mat, o, CFrame.new(cx, cy, cz))
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

	---------------------------------------------------------------- building helpers
	-- Visible steps (no collision) over one invisible ramp you actually walk on.
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
		wedge(parent, rx0, yLow, rz0, rx1, yHigh, rz1, OPP[up], color, mat, { t = 1, noshadow = true, nq = true }, "StairRamp")
	end

	-- Four walls with door / window holes. openings = { {side, a, b, sillY, headY}, ... } (a, b in world coords)
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
	local function helm(parent, x0, z0, x1, z1, y, h, color)
		local xc, zc = (x0 + x1) / 2, (z0 + z1) / 2
		wedge(parent, x0, y, z0, x1, y + h, zc, N, color, M.Slate, nil, "Roof")
		wedge(parent, x0, y, zc, x1, y + h, z1, S, color, M.Slate, nil, "Roof")
		wedge(parent, x0, y, z0, xc, y + h, z1, W, color, M.Slate, nil, "Roof")
		wedge(parent, xc, y, z0, x1, y + h, z1, E, color, M.Slate, nil, "Roof")
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
		local pl = Instance.new("PointLight")
		pl.Range = 24
		pl.Brightness = 0.9
		pl.Color = C(255, 190, 120)
		pl.Shadows = false
		pl.Parent = l
		stats.lights += 1
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
	local function smoke(parent, x, y, z, size, opacity, rise)
		local e = box(parent, x - 0.5, y - 0.5, z - 0.5, x + 0.5, y + 0.5, z + 0.5, P.coal, M.SmoothPlastic, { deco = true, t = 1 }, "SmokeEmitter")
		local s = Instance.new("Smoke")
		s.Size = size
		s.Opacity = opacity
		s.RiseVelocity = rise
		s.Color = C(96, 92, 88)
		s.Parent = e
	end
	local function tree(parent, x, z, y0, s)
		y0 = y0 or 0
		s = s or 1
		cylY(parent, x, y0, y0 + 9 * s, z, 1.6 * s, P.darkwood, M.Wood, { noshadow = true }, "Trunk")
		ball(parent, x, y0 + 13 * s, z, 12 * s, pick(P.leaf), M.Grass, { nc = true, nq = true }, "Foliage")
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
			box(parent, x - 4.2, y0, z - 2, x + 4.2, y0 + 2.2, z + 2, P.darkwood, M.Wood, { noshadow = true }, "CartChassis")
			cylZ(parent, x, y0 + 2.2, z - 3.1, z - 2.5, 4.4, P.darkwood, M.Wood, DECO, "Wheel")
			cylZ(parent, x, y0 + 2.2, z + 2.5, z + 3.1, 4.4, P.darkwood, M.Wood, DECO, "Wheel")
		else
			box(parent, x - 2.4, y0 + 2.2, z - 4.5, x + 2.4, y0 + 3.2, z + 4.5, P.wood, M.WoodPlanks, nil, "CartBed")
			box(parent, x - 2.4, y0 + 3.2, z - 4.5, x - 2, y0 + 5, z + 4.5, P.wood, M.WoodPlanks, { noshadow = true }, "CartSide")
			box(parent, x + 2, y0 + 3.2, z - 4.5, x + 2.4, y0 + 5, z + 4.5, P.wood, M.WoodPlanks, { noshadow = true }, "CartSide")
			box(parent, x - 2, y0, z - 4.2, x + 2, y0 + 2.2, z + 4.2, P.darkwood, M.Wood, { noshadow = true }, "CartChassis")
			cylX(parent, x - 3.1, x - 2.5, y0 + 2.2, z, 4.4, P.darkwood, M.Wood, DECO, "Wheel")
			cylX(parent, x + 2.5, x + 3.1, y0 + 2.2, z, 4.4, P.darkwood, M.Wood, DECO, "Wheel")
		end
	end
	-- Market stall; the canopy (no collision, no queries) drops towards `face`.
	local function stall(parent, x, z, face)
		local col = pick(P.awning)
		if face == N or face == S then
			box(parent, x - 4.5, 0, z - 1.6, x + 4.5, 3.2, z + 1.6, P.wood, M.WoodPlanks, { noshadow = true }, "Counter")
			local zb = (face == S) and (z - 2.2) or (z + 2.2)
			cylY(parent, x - 4.3, 0, 9.2, zb, 0.5, P.darkwood, M.Wood, DECO, "Post")
			cylY(parent, x + 4.3, 0, 9.2, zb, 0.5, P.darkwood, M.Wood, DECO, "Post")
			wedge(parent, x - 5, 7.2, z - 3, x + 5, 9.4, z + 3, face, col, M.Fabric, { deco = true }, "Canopy")
		else
			box(parent, x - 1.6, 0, z - 4.5, x + 1.6, 3.2, z + 4.5, P.wood, M.WoodPlanks, { noshadow = true }, "Counter")
			local xb = (face == E) and (x - 2.2) or (x + 2.2)
			cylY(parent, xb, 0, 9.2, z - 4.3, 0.5, P.darkwood, M.Wood, DECO, "Post")
			cylY(parent, xb, 0, 9.2, z + 4.3, 0.5, P.darkwood, M.Wood, DECO, "Post")
			wedge(parent, x - 3, 7.2, z - 5, x + 3, 9.4, z + 5, face, col, M.Fabric, { deco = true }, "Canopy")
		end
		for i = 0, 2 do
			box(parent, x - 1 + (i - 1) * 1.6 * ((face == N or face == S) and 1 or 0), 3.2, z - 0.6 + (i - 1) * 1.6 * ((face == N or face == S) and 0 or 1),
				x + 0.2 + (i - 1) * 1.6 * ((face == N or face == S) and 1 or 0), 3.9, z + 0.6 + (i - 1) * 1.6 * ((face == N or face == S) and 0 or 1),
				pick({ C(180, 40, 36), C(206, 150, 40), C(110, 140, 50) }), M.SmoothPlastic, DECO, "Goods")
		end
	end
	local function heap(parent, x0, z0, x1, z1, y0, h, color, mat)
		local xc = (x0 + x1) / 2
		wedge(parent, x0, y0, z0, xc, y0 + h, z1, W, color, mat, nil, "Heap")
		wedge(parent, xc, y0, z0, x1, y0 + h, z1, E, color, mat, nil, "Heap")
	end
	-- Covered wagon, long axis along Z; tall enough to block sight and too tall to climb.
	local function wagon(parent, x0, z0, x1, z1)
		box(parent, x0 + 0.3, 0.4, z0, x1 - 0.3, 2.4, z1, P.darkwood, M.WoodPlanks, nil, "WagonBed")
		box(parent, x0, 2.4, z0 + 0.4, x1, 8.6, z1 - 0.4, P.canvas, M.Fabric, nil, "WagonCanvas")
		local xc = (x0 + x1) / 2
		wedge(parent, x0, 8.6, z0 + 0.4, xc, 10.2, z1 - 0.4, W, P.canvas, M.Fabric, nil, "WagonTop")
		wedge(parent, xc, 8.6, z0 + 0.4, x1, 10.2, z1 - 0.4, E, P.canvas, M.Fabric, nil, "WagonTop")
		for _, z in ipairs({ z0 + 1.8, z1 - 1.8 }) do
			cylX(parent, x0 - 0.5, x0, 1.8, z, 3.6, P.darkwood, M.Wood, DECO, "Wheel")
			cylX(parent, x1, x1 + 0.5, 1.8, z, 3.6, P.darkwood, M.Wood, DECO, "Wheel")
		end
		box(parent, xc - 0.2, 1.4, z1, xc + 0.2, 1.8, z1 + 3.5, P.darkwood, M.Wood, DECO, "Shaft")
	end
	-- Round advertising column (the Paris "colonne Morris" reached Belgian squares in the 1870s).
	local function advertColumn(parent, x, z)
		cylY(parent, x, 0, 0.6, z, 3.8, P.green, M.Metal, nil, "ColumnBase")
		cylY(parent, x, 0.6, 8.6, z, 3.2, pick(P.poster), M.SmoothPlastic, nil, "ColumnPosters")
		cylY(parent, x, 8.6, 9.2, z, 3.6, P.green, M.Metal, nil, "ColumnCap")
		ball(parent, x, 9.4, z, 2.8, P.green, M.Metal, DECO, "ColumnDome")
		cylY(parent, x, 10.4, 11.2, z, 0.3, P.brass, M.Metal, DECO, "ColumnFinial")
		for i = 0, 3 do
			local a = i * PI / 2 + 0.4
			box(parent, x + math.cos(a) * 1.62 - 0.6, 3, z + math.sin(a) * 1.62 - 0.6, x + math.cos(a) * 1.62 + 0.6, 6.5, z + math.sin(a) * 1.62 + 0.6,
				pick(P.poster), M.SmoothPlastic, DECO, "Poster")
		end
	end
	local function bollard(parent, x, z)
		cylY(parent, x, 0.3, 1.6, z, 0.8, P.iron, M.Metal, DECO, "Bollard")
	end
	local function bench(parent, x, z, axis)
		if axis == "X" then
			box(parent, x - 3, 1.4, z - 0.7, x + 3, 1.7, z + 0.7, P.wood, M.WoodPlanks, DECO, "Bench")
			box(parent, x - 3, 1.7, z + 0.5, x + 3, 3.2, z + 0.7, P.wood, M.WoodPlanks, DECO, "BenchBack")
		else
			box(parent, x - 0.7, 1.4, z - 3, x + 0.7, 1.7, z + 3, P.wood, M.WoodPlanks, DECO, "Bench")
			box(parent, x + 0.5, 1.7, z - 3, x + 0.7, 3.2, z + 3, P.wood, M.WoodPlanks, DECO, "BenchBack")
		end
	end
	-- Team banner hanging on a wall whose outward normal is `face`, at plane coordinate c.
	local function banner(parent, team, a, c, face, y0)
		y0 = y0 or 7
		local function slab(a0, a1, ya, yb, d0, d1, col, name)
			if face == S then box(parent, a0, ya, c + d0, a1, yb, c + d1, col, M.Fabric, DECO, name)
			elseif face == N then box(parent, a0, ya, c - d1, a1, yb, c - d0, col, M.Fabric, DECO, name)
			elseif face == E then box(parent, c + d0, ya, a0, c + d1, yb, a1, col, M.Fabric, DECO, name)
			else box(parent, c - d1, ya, a0, c - d0, yb, a1, col, M.Fabric, DECO, name) end
		end
		slab(a - 1.7, a + 1.7, y0, y0 + 9, 0.05, 0.3, team.color, "TeamBanner")
		slab(a - 0.18, a + 0.18, y0 + 2, y0 + 7, 0.3, 0.42, GOLD, "BannerEmblem")
		slab(a - 0.9, a + 0.9, y0 + 6.1, y0 + 6.4, 0.3, 0.42, GOLD, "BannerEmblem")
		slab(a - 1.7, a + 1.7, y0 + 9, y0 + 9.3, 0.0, 0.5, P.darkwood, "BannerPole")
		slab(a - 1.7, a + 1.7, y0 - 0.6, y0, 0.05, 0.3, team.dark, "BannerFringe")
	end

	---------------------------------------------------------------- terraced houses
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
		local roofC = pick(P.slate)
		if rnd() < 0.2 then roofC = P.tile end
		local bo = o.back and 0.8 or 0
		lwedge(f, m, u0, -0.8, H, u1, D / 2, H + rh, true, roofC, M.Slate, nil, "Roof")
		lwedge(f, m, u0, D / 2, H, u1, D + bo, H + rh, false, roofC, M.Slate, nil, "Roof")
		lbox(f, m, u0 + 1, D / 2 - 1.5, H + rh - 4, u0 + 4, D / 2 + 1.5, H + rh + 4, P.brick[4], M.Brick, DECO, "Chimney")

		local bays = max(2, floor(w / 7))
		local bw = w / bays
		local doorBay = rint(1, bays)
		local shop = o.shops and rnd() < o.shops
		if shop then
			lbox(f, m, u0 + 0.5, -0.4, 9, u1 - 0.5, 0, 10.8, pick(P.awning), M.Wood, DECO, "ShopSign")
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
		local function side(ue)
			for fl = 0, floors - 1 do
				local yb = fl * FLOOR + 1.5
				for _, vc in ipairs({ D * 0.3, D * 0.7 }) do
					if D >= 7 then
						local col, mat = windowLook()
						lbox(f, m, ue - 0.25, vc - 1.7, yb + 2.5, ue + 0.25, vc + 1.7, yb + 8, col, mat, DECO, "Window")
					end
				end
			end
			lwedge(f, m, ue - 0.3, -0.8, H, ue + 0.3, D / 2, H + rh + 0.5, true, wallC, wallM, DECO, "Gable")
			lwedge(f, m, ue - 0.3, D / 2, H, ue + 0.3, D + bo, H + rh + 0.5, false, wallC, wallM, DECO, "Gable")
		end
		if exposedA then side(u0) end
		if exposedB then side(u1) end
	end

	local FLOORS = { 2, 3, 3, 3, 4 }
	local function row(parent, name, x0, z0, x1, z1, face, o)
		o = o or {}
		local f = frame(x0, z0, x1, z1, face)
		local m = model(parent, name, true)
		local n = max(1, floor(f.L / 20 + 0.5))
		local base = f.L / n
		local cuts = { 0 }
		for i = 1, n - 1 do
			cuts[#cuts + 1] = i * base + (rnd() - 0.5) * min(4, base * 0.25)
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
	-- A block nobody sees from the ground: one box and a roof, for the skyline.
	local function mass(parent, name, x0, z0, x1, z1, h, axis)
		local m = model(parent, name, true)
		box(m, x0, 0, z0, x1, h, z1, pick(P.brick), M.Brick, nil, "Wall")
		gableRoof(m, x0, z0, x1, z1, h, min(10, ((axis == "X") and (z1 - z0) or (x1 - x0)) * 0.38), axis, pick(P.slate), M.Slate, 0)
		return m
	end
	-- Upper storeys over a covered passage (open from the ground to y = y0).
	local function passage(parent, name, x0, z0, x1, z1, y0, y1, axis, team)
		local m = model(parent, name, true)
		local c = pick(P.plaster)
		box(m, x0, y0, z0, x1, y1, z1, c, M.Plaster, nil, "UpperFloors")
		gableRoof(m, x0, z0, x1, z1, y1, 7, axis, pick(P.slate), M.Slate, 0.6)
		-- arch rings at both mouths
		if axis == "X" then
			for _, x in ipairs({ x0, x1 - 0.8 }) do
				box(m, x, y0 - 1, z0, x + 0.8, y0, z1, P.lime, M.Limestone, DECO, "ArchRing")
			end
			ceilingLamp(m, (x0 + x1) / 2, y0, (z0 + z1) / 2, 22)
		else
			for _, z in ipairs({ z0, z1 - 0.8 }) do
				box(m, x0, y0 - 1, z, x1, y0, z + 0.8, P.lime, M.Limestone, DECO, "ArchRing")
			end
			ceilingLamp(m, (x0 + x1) / 2, y0, (z0 + z1) / 2, 22)
		end
		return m
	end

	---------------------------------------------------------------- root
	local root = model(nil, "LiegeDuel")
	root:SetAttribute("DisplayName", "Le Bief")
	root:SetAttribute("Size", "250 x 250")
	local markers = folder(root, "Markers")
	local spawnFolder = folder(markers, "Spawns")
	local zoneFolder = folder(markers, "SpawnZones")

	local function marker(parent, name, cf, size)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Transparency = 1
		p.Size = size or Vector3.new(2, 0.2, 2)
		p.CFrame = XF * cf
		p.Color = C(255, 200, 60)
		p.Material = M.SmoothPlastic
		p.Parent = parent
		return p
	end

	---------------------------------------------------------------- one side of the map (authored as Red, north)
	-- Spawn slots: slot 1 is the 1v1 spawn. Chosen with tools/check_duel.py: none of them can be seen
	-- from outside the spawn courtyard.
	local SPAWNS = { { -4, -106, S }, { 4, -106, S }, { -12, -106, S }, { 12, -106, S } }

	local zones = {}
	local function half(team)
		local H = folder(root, team.name .. "Side")
		local pav = { noshadow = true }

		------------------------------------------------ ground, quay, canal (this side)
		local g = model(H, "Ground", false)
		box(g, -125, -6, -125, 125, 0, -18, P.cobble, M.Cobblestone, nil, "Ground")
		box(g, -125, -6, -18, -30, 0, -9, P.cobble, M.Cobblestone, nil, "Ground")
		box(g, 30, -6, -18, 125, 0, -9, P.cobble, M.Cobblestone, nil, "Ground")
		box(g, -30, -6, -18, 30, -5, -9, P.mud, M.Mud, nil, "BasinBed")
		local water = box(g, -125, -5, -9, -30, -2, 9, P.water, M.SmoothPlastic, { nc = true, nq = true, noshadow = true, t = 0.35, refl = 0.15 }, "CanalWater")
		water.CastShadow = false
		box(g, -109, 0, -24, -30, 0.2, -10.5, P.paving, M.Pavement, pav, "Quay")
		box(g, 30, 0, -24, 109, 0.2, -10.5, P.paving, M.Pavement, pav, "Quay")
		box(g, -30, 0, -24, 30, 0.2, -19.5, P.paving, M.Pavement, pav, "Quay")
		box(g, -109, 0, -10.5, -31.5, 0.3, -9, P.lime, M.Limestone, pav, "Coping")
		box(g, 31.5, 0, -10.5, 109, 0.3, -9, P.lime, M.Limestone, pav, "Coping")
		box(g, -31.5, 0, -19.5, 31.5, 0.3, -18, P.lime, M.Limestone, pav, "Coping")
		box(g, -31.5, 0, -18, -30, 0.3, -10.5, P.lime, M.Limestone, pav, "Coping")
		box(g, 30, 0, -18, 31.5, 0.3, -10.5, P.lime, M.Limestone, pav, "Coping")
		box(g, -28, 0, -109, 28, 0.2, -88, P.paving, M.Pavement, pav, "CourtyardPaving")
		box(g, -28, 0, -80, 28, 0.2, -24, P.paving, M.Pavement, pav, "SquarePaving")
		box(g, -109, 0, -84, -66, 0.15, -36, P.dirt, M.Ground, pav, "YardGround")

		------------------------------------------------ buildings
		local B = folder(H, "Buildings")
		-- north edge of the map (only the parts you can see get windows)
		mass(B, "Backdrop_NW", -125, -125, -64, -109, 30, "X")
		row(B, "Rue_Saint_Pholien", -64, -125, -28, -104, S, { fmin = 3 })
		row(B, "Courtyard_Back", -28, -125, 28, -109, S, { fmin = 3, fmax = 3 })
		row(B, "Gate_Back", 28, -125, 44, -104, S, { fmin = 3 })
		row(B, "Market_Back", 44, -125, 96, -109, S, { fmin = 3, shops = 0.5 })
		mass(B, "Backdrop_NE", 96, -125, 125, -109, 34, "X")
		-- west edge
		mass(B, "Backdrop_W", -125, -109, -109, -84, 34, "Z")
		row(B, "Yard_West", -125, -84, -109, -36, E, { fmin = 3 })
		mass(B, "Backdrop_SW", -125, -36, -109, -24, 30, "Z")
		row(B, "Quay_West", -125, -24, -109, -9, E, { fmin = 3, sideB = true })
		-- east edge
		row(B, "Market_East", 96, -109, 125, -24, W, { fmin = 3, shops = 0.6, sideB = true })
		row(B, "Quay_East", 109, -24, 125, -9, W, { fmin = 3 })
		-- inner blocks
		row(B, "Yard_North", -109, -109, -64, -84, S, { fmin = 2, fmax = 3, sideB = true })
		row(B, "Tunnel_South", -52, -94, -28, -88, E, { back = true, sideA = true, fmin = 3, fmax = 3 })
		passage(B, "Tunnel", -52, -104, -28, -94, 10, 34.5, "X", team)
		row(B, "Halle_West", -28, -88, -5, -80, S, { back = true, sideB = true, fmin = 3, fmax = 3 })
		row(B, "Halle_East", 5, -88, 28, -80, S, { back = true, sideA = true, fmin = 3, fmax = 3 })
		passage(B, "Gateway", -5, -88, 5, -80, 10, 34.5, "Z", team)
		row(B, "Gate_South", 28, -94, 44, -88, W, { back = true, sideA = true, fmin = 3, fmax = 3 })
		row(B, "Armuriers_North", -52, -88, -28, -70, E, { back = true, fmin = 3 })
		row(B, "Armuriers_South", -52, -44, -28, -24, E, { back = true, sideB = true, fmin = 3 })
		row(B, "Estaminet_North", 28, -88, 44, -70, W, { back = true, fmin = 3 })
		row(B, "Estaminet_South", 28, -40, 44, -24, W, { back = true, sideB = true, fmin = 3 })
		row(B, "Yard_South_W", -109, -36, -96, -24, N, { back = true, sideB = true, fmax = 3 })
		row(B, "Yard_South_E", -86, -36, -64, -24, N, { back = true, sideA = true, sideB = true, fmax = 3 })

		-- the yard wall: 13 tall so nothing in the alley or yard lets you climb onto it
		local yw = model(B, "YardWall", true)
		local ywC = C(120, 100, 86)
		for _, zz in ipairs({ { -84, -78 }, { -72, -50 }, { -44, -36 } }) do
			box(yw, -66, 0, zz[1], -64, 13, zz[2], ywC, M.Brick, nil, "Wall")
			box(yw, -66.3, 13, zz[1], -63.7, 13.6, zz[2], P.lime, M.Limestone, DECO, "Coping")
		end
		-- gate posts of the yard
		for _, zz in ipairs({ -78, -72, -50, -44 }) do
			box(yw, -66.4, 0, zz - 0.4, -63.6, 14.2, zz + 0.4, P.stone, M.Limestone, DECO, "GatePost")
		end
		sign(yw, -63.6, 9.5, -75, 5.5, 1.4, E, "COUR DES APACHES")

		------------------------------------------------ the spawn courtyard
		local cy = model(H, "SpawnCourtyard", true)
		-- covered wagons screen the tunnel and the east gate, so the lanes cannot see into the courtyard
		wagon(cy, -22, -108.5, -17.5, -97)
		wagon(cy, 17.5, -108.5, 22, -97)
		-- the guardhouse screens the gateway from the square
		box(cy, -9, 0, -98, 9, 10, -94, P.brick[2], M.Brick, nil, "Guardhouse")
		gableRoof(cy, -9, -98, 9, -94, 10, 2.5, "X", P.slate[1], M.Slate, 0.4)
		box(cy, -1.5, 0, -98.25, 1.5, 7, -97.95, P.darkwood, M.Wood, DECO, "Door")
		sign(cy, 0, 7.8, -93.8, 9, 1.3, S, "CORPS DE GARDE", team.dark, C(236, 220, 170))
		banner(cy, team, -12, -109, S, 8)
		banner(cy, team, 12, -109, S, 8)
		banner(cy, team, 0, -80, S, 11)
		barrel(cy, -25.5, -90.5, 0.2)
		barrel(cy, 25.5, -90.5, 0.2)
		lamp(cy, -14, -89.2, 0.2)
		lamp(cy, 14, -89.2, 0.2)
		-- the east gate: an arch you cannot stand on, with the team colours
		box(cy, 28, 15, -104.6, 30, 16.4, -93.4, P.lime, M.Limestone, DECO, "GateArch")
		banner(cy, team, -91, 44, E, 9)
		banner(cy, team, -99, -52, W, 10)
		local zone = marker(zoneFolder, team.name, CFrame.new(0, 10, -98.5), Vector3.new(56, 20, 21))
		zone:SetAttribute("Team", team.name)
		zone:AddTag("LiegeSpawnZone")
		for i, s in ipairs(SPAWNS) do
			local m = marker(spawnFolder, team.name .. "_" .. i, CFrame.new(s[1], 0.3, s[2]) * CFrame.Angles(0, YAW[s[3]], 0))
			m:SetAttribute("Team", team.name)
			m:SetAttribute("Slot", i)
			m:AddTag("LiegeDuelSpawn")
		end

		------------------------------------------------ the gunsmiths' alley (x -64 .. -52)
		local al = model(H, "RueDesArmuriers", true)
		barrel(al, -61.5, -98, 0)
		barrel(al, -61.5, -95.2, 0)
		crate(al, -54.5, -82, 0, 4)
		cart(al, -60, -66, 0, "Z")
		crate(al, -54.5, -50, 0, 3.5)
		barrel(al, -61.5, -38, 0)
		box(al, -64, 10, -76, -52, 21, -71, pick(P.plaster), M.Plaster, nil, "Overpass")
		box(al, -64.4, 21, -76.4, -51.6, 22, -70.6, P.slate[1], M.Slate, { noshadow = true }, "OverpassRoof")
		sign(al, -52.3, 10.5, -86, 10, 1.6, W, "RUE DES ARMURIERS")
		lamp(al, -53, -92)
		lamp(al, -63, -58)
		lamp(al, -53, -30)

		------------------------------------------------ the gunsmith's workshop (pass-through, x -52 .. -28)
		local at = model(H, "Atelier", true)
		local ac = P.brick[3]
		walls(at, -52, -70, -28, -44, 0, 12, 1.5, ac, M.Brick, {
			{ W, -62, -57, 0, 8 },
			{ E, -53, -48, 0, 8 }, { E, -66, -62, 3.6, 7.4 },
		})
		box(at, -52, 0, -70, -28, 0.15, -44, C(110, 86, 62), M.WoodPlanks, { noshadow = true }, "Floor")
		box(at, -52, 12, -70, -28, 23.5, -44, ac, M.Brick, nil, "UpperFloor")
		gableRoof(at, -52, -70, -28, -44, 23.5, 9, "Z", P.slate[1], M.Slate, 0.8)
		winGrid(at, W, -52, -68, -46, 3, { 15 }, 3.4, 5.5, 0.3)
		winGrid(at, E, -28, -68, -46, 3, { 15 }, 3.4, 5.5, 0.3)
		-- window onto the square: glass you can shoot through but not climb through
		box(at, -28.85, 3.6, -66, -28.65, 7.4, -62, C(170, 196, 210), M.Glass, { nq = true, noshadow = true, t = 0.55 }, "WindowPane")
		box(at, -50.5, 0, -68.5, -42, 3.2, -66, P.wood, M.WoodPlanks, nil, "Workbench")
		local forge = box(at, -34.5, 0, -68.5, -29.5, 4, -63.5, P.brick[4], M.Brick, nil, "Forge")
		fireGlow(box(at, -33.5, 4, -67.5, -30.5, 4.4, -64.5, P.ember, M.Neon, DECO, "Embers"), 24, 1.6, 4)
		box(at, -34.5, 9, -68.5, -29.5, 12, -63.5, P.brick[4], M.Brick, { noshadow = true }, "ForgeHood")
		box(at, -33.5, 23.5, -68, -30.5, 36, -65, P.brick[4], M.Brick, nil, "Chimney")
		smoke(at, -32, 36.5, -66.5, 3, 0.22, 4)
		box(at, -41.5, 0, -59, -38.5, 2.4, -57.4, P.iron, M.Metal, nil, "Anvil")
		box(at, -45, 0, -51.5, -37, 3.2, -49, P.wood, M.WoodPlanks, nil, "Table")
		crate(at, -48.5, -47.5, 0.15, 3)
		box(at, -36, 4, -45.4, -30, 9, -45.1, P.darkwood, M.Wood, DECO, "GunRack")
		ceilingLamp(at, -46, 12, -57, 24)
		ceilingLamp(at, -34, 12, -55, 24)
		sign(at, -27.7, 9.6, -50.5, 9, 1.6, E, "ARMURIER", C(34, 46, 40), C(232, 206, 140))
		sign(at, -52.3, 9.6, -59.5, 9, 1.6, W, "ARMURIER", C(34, 46, 40), C(232, 206, 140))
		if team == TEAMS[1] then zones[#zones + 1] = { "Atelier", -51.5, 0, -69.5, -28.5, 12, -44.5, C(255, 214, 170), -0.04, 0.1, -0.05 } end

		------------------------------------------------ the estaminet (pass-through, x 28 .. 44)
		local es = model(H, "Estaminet", true)
		local ec = P.plaster[2]
		walls(es, 28, -70, 44, -40, 0, 12, 1.5, ec, M.Plaster, {
			{ W, -66, -61, 0, 8 }, { W, -56, -50, 3.6, 7.4 },
			{ E, -50, -45, 0, 8 },
		})
		box(es, 28, 0, -70, 44, 0.15, -40, C(110, 86, 62), M.WoodPlanks, { noshadow = true }, "Floor")
		box(es, 28, 12, -70, 44, 23.5, -40, ec, M.Plaster, nil, "UpperFloor")
		gableRoof(es, 28, -70, 44, -40, 23.5, 8, "Z", P.tile, M.Slate, 0.8)
		winGrid(es, W, 28, -68, -42, 3, { 15 }, 3.4, 5.5, 0.5)
		winGrid(es, E, 44, -68, -42, 3, { 15 }, 3.4, 5.5, 0.5)
		box(es, 28.65, 3.6, -56, 28.85, 7.4, -50, C(170, 196, 210), M.Glass, { nq = true, noshadow = true, t = 0.55 }, "WindowPane")
		box(es, 32, 0, -66, 40, 3.8, -64, P.darkwood, M.Wood, nil, "Bar")
		box(es, 32, 0, -68.5, 40, 8, -67.5, P.darkwood, M.Wood, DECO, "BottleShelf")
		for _, p in ipairs({ { 34, -55 }, { 39, -51 } }) do
			cylY(es, p[1], 0, 2.8, p[2], 0.8, P.darkwood, M.Wood, DECO, "TableLeg")
			cylY(es, p[1], 2.8, 3.2, p[2], 4.4, P.wood, M.WoodPlanks, nil, "Table")
		end
		box(es, 33, 0, -42.5, 39, 6, -41.5, P.brick[4], M.Brick, nil, "Hearth")
		fireGlow(box(es, 34.5, 0.4, -42.8, 37.5, 2.8, -42.4, P.ember, M.Neon, DECO, "Fire"), 22, 1.4, 3)
		box(es, 34, 23.5, -42, 38, 33, -40, P.brick[4], M.Brick, nil, "Chimney")
		smoke(es, 36, 33.5, -41, 2.5, 0.2, 4)
		barrel(es, 41, -43, 0.15)
		ceilingLamp(es, 36, 12, -58, 24)
		ceilingLamp(es, 36, 12, -47, 22)
		sign(es, 27.7, 9.6, -63.5, 10, 1.6, W, "ESTAMINET", C(96, 40, 34), C(238, 214, 150))
		sign(es, 44.3, 9.6, -47.5, 10, 1.6, E, "ESTAMINET", C(96, 40, 34), C(238, 214, 150))
		if team == TEAMS[1] then zones[#zones + 1] = { "Estaminet", 29.5, 0, -69.5, 42.5, 12, -40.5, C(255, 206, 150), -0.03, 0.08, 0.05 } end

		------------------------------------------------ the yard (x -109 .. -66)
		local yd = model(H, "CourDesApaches", true)
		box(yd, -106, 0, -82, -96, 10, -75, pick(P.brick), M.Brick, nil, "Shed")
		gableRoof(yd, -106, -82, -96, -75, 10, 3, "X", P.tile, M.Slate, 0.5)
		box(yd, -102.5, 0, -75.2, -99.5, 7, -74.9, P.darkwood, M.Wood, DECO, "Door")
		heap(yd, -104, -54, -92, -42, 0, 3.5, P.coal, M.Slate)
		box(yd, -86.5, 0, -68, -81.5, 3, -64, P.wood, M.WoodPlanks, nil, "GangTable")
		for _, p in ipairs({ { -88, -66 }, { -80, -66 }, { -84, -69.5 } }) do
			crate(yd, p[1], p[2], 0.15, 2)
		end
		crate(yd, -76, -80, 0.15, 4)
		crate(yd, -72, -58, 0.15, 3.5)
		crate(yd, -75.5, -56.5, 0.15, 3)
		cart(yd, -88, -42, 0.15, "X")
		barrel(yd, -104, -62, 0.15)
		barrel(yd, -104, -59.2, 0.15)
		barrel(yd, -79, -40, 0.15)
		for _, z in ipairs({ -70, -60 }) do
			box(yd, -108.5, 13, z, -66.5, 13.15, z + 0.15, P.lime, M.Fabric, DECO, "WashingLine")
			box(yd, -100, 10, z, -97, 13, z + 0.1, pick(P.plaster), M.Fabric, DECO, "Washing")
			box(yd, -90, 10.6, z, -87.5, 13, z + 0.1, pick(P.plaster), M.Fabric, DECO, "Washing")
			box(yd, -78, 10.2, z, -75, 13, z + 0.1, pick(P.plaster), M.Fabric, DECO, "Washing")
		end
		lamp(yd, -91, -82.5, 0.15)
		sign(yd, -91, 11, -36.3, 10, 1.6, N, "COUR DES APACHES")
		-- the yard gate onto the quay: open, with a wooden beam far out of reach
		box(yd, -96, 16, -36, -86, 17, -35, P.darkwood, M.Wood, DECO, "GateBeam")

		------------------------------------------------ the square (x -28 .. 28)
		local sq = model(H, "Square", true)
		box(sq, -4, 0, -66, 4, 10, -58, C(52, 86, 66), M.WoodPlanks, nil, "Kiosk")
		helm(sq, -4.6, -66.6, 4.6, -57.4, 10, 3, P.slate[2])
		box(sq, -4.1, 6, -66.1, 4.1, 8, -57.9, pick(P.poster), M.SmoothPlastic, DECO, "KioskPosters")
		sign(sq, 0, 8.8, -57.8, 6.5, 1.2, S, "JOURNAUX", C(52, 86, 66), C(236, 220, 170))
		stall(sq, -17, -46, E)
		stall(sq, 17, -72, W)
		cart(sq, 15, -42, 0.2, "X")
		box(sq, -23, 0.2, -75, -16, 2.6, -72.5, P.stone, M.Limestone, nil, "HorseTrough")
		box(sq, -22.6, 2.3, -74.6, -16.4, 2.62, -72.9, P.water, M.SmoothPlastic, DECO, "TroughWater")
		for _, p in ipairs({ { -21, -30 }, { 21, -58 } }) do
			box(sq, p[1] - 1.8, 0.2, p[2] - 1.8, p[1] + 1.8, 1.4, p[2] + 1.8, P.stone, M.Limestone, nil, "Planter")
			tree(sq, p[1], p[2], 1.4, 0.85)
		end
		advertColumn(sq, 0, -34)
		barrel(sq, 24, -27, 0.2)
		barrel(sq, -9, -76, 0.2)
		bench(sq, -12, -62, "Z")
		bench(sq, 12, -38, "Z")
		lamp(sq, -26, -78, 0.2)
		lamp(sq, 26, -78, 0.2)
		lamp(sq, -26, -26, 0.2)
		lamp(sq, 26, -26, 0.2)

		------------------------------------------------ the market (x 44 .. 96)
		local mk = model(H, "Marche", true)
		box(mk, 86, 0, -92, 96, 4.5, -62, P.brick[2], M.Brick, nil, "LoadingDock")
		box(mk, 85.7, 4.5, -92.3, 96, 4.8, -61.7, P.wood, M.WoodPlanks, { noshadow = true }, "DockDeck")
		stairs(mk, 86, -62, 96, -55, 0, 4.8, N, 0, P.stone, M.Limestone)
		crate(mk, 88.5, -88, 4.8, 3)
		crate(mk, 88.5, -70, 4.8, 3)
		stall(mk, 54, -96, E)
		stall(mk, 54, -72, E)
		stall(mk, 54, -48, E)
		stall(mk, 70, -84, W)
		stall(mk, 70, -60, W)
		cart(mk, 76, -102, 0, "X")
		cart(mk, 80, -38, 0, "Z")
		advertColumn(mk, 62, -30)
		barrel(mk, 47.5, -105, 0)
		barrel(mk, 50.3, -105, 0)
		crate(mk, 92, -48, 0, 4)
		box(mk, 66.4, 0, -105.6, 67.6, 4.2, -104.4, P.iron, M.Metal, nil, "Pump")
		box(mk, 66.8, 3.2, -104.4, 67.2, 3.5, -103, P.iron, M.Metal, DECO, "PumpSpout")
		sign(mk, 70, 16, -108.7, 12, 2, S, "MARCHÉ DE LA BATTE")
		lamp(mk, 46, -98)
		lamp(mk, 46, -58)
		lamp(mk, 94.5, -46)
		lamp(mk, 80, -107)

		------------------------------------------------ the quay
		local qy = model(H, "Quay", true)
		advertColumn(qy, -44, -17)
		crate(qy, -98, -20, 0.2, 4)
		crate(qy, -94, -20, 0.2, 4)
		barrel(qy, 101, -21, 0.2)
		barrel(qy, 103.8, -21, 0.2)
		barrel(qy, 101, -18.2, 0.2)
		tree(qy, -62, -21.5, 0.2, 0.9)
		tree(qy, 72, -21.5, 0.2, 0.9)
		for _, x in ipairs({ -104, -66, -36, 36, 66, 104 }) do
			bollard(qy, x, -11.4)
		end
		bench(qy, -20, -22.8, "X")
		lamp(qy, -100, -23)
		lamp(qy, -36, -23)
		lamp(qy, 36, -23)
		lamp(qy, 96, -23)
		-- stairs down into the canal
		stairs(qy, -104, -9, -92, -5.5, -5, 0, W, -5, P.stone, M.Limestone)
		stairs(qy, 40, -9, 52, -5.5, -5, 0, W, -5, P.stone, M.Limestone)
		-- a moored barge: its cabin breaks the long lines along the canal and gives the waders cover
		local bt = model(qy, "Peniche", true)
		local hull = C(52, 40, 32)
		box(bt, -66, -5, -8.6, -44, -1.0, -3.4, hull, M.WoodPlanks, nil, "Hull")
		wedge(bt, -44, -5, -8.6, -40, -1.0, -3.4, E, hull, M.WoodPlanks, nil, "Bow")
		wedge(bt, -69, -5, -8.6, -66, -1.0, -3.4, W, hull, M.WoodPlanks, nil, "Stern")
		heap(bt, -64, -8, -56, -4, -1.0, 1.6, P.coal, M.Slate)
		box(bt, -53, -1.0, -8.1, -45, 5.5, -3.9, C(132, 96, 62), M.WoodPlanks, nil, "Cabin")
		box(bt, -53.4, 5.5, -8.5, -44.6, 6.0, -3.5, C(70, 56, 44), M.WoodPlanks, { noshadow = true }, "CabinRoof")
		winGrid(bt, N, -8.1, -52, -46, 2, { 1.5 }, 1.6, 1.8, 0.6)
		box(bt, -51, 6.0, -6.4, -50.4, 9, -5.8, P.iron, M.Metal, DECO, "Stovepipe")
		-- the public weigh-house on the quay: blocks the line from this market to the far side's alley
		local wh = model(qy, "PoidsPublic", true)
		box(wh, 52, 0.2, -20, 64, 9.5, -14, P.lime, M.Limestone, nil, "WeighHouse")
		helm(wh, 51.6, -20.4, 64.4, -13.6, 9.5, 3, P.slate[1])
		box(wh, 56.5, 0.2, -20.25, 59.5, 7, -19.95, P.darkwood, M.Wood, DECO, "Door")
		winGrid(wh, S, -14, 53, 63, 2, { 3.5 }, 2.6, 3.2)
		sign(wh, 58, 8.4, -20.3, 8, 1.2, N, "POIDS PUBLIC", P.lime, C(40, 36, 32))
		box(qy, 18, -5, -15, 26, -3.6, -12, P.wood, M.WoodPlanks, { noshadow = true }, "RowingBoat")

		------------------------------------------------ crossings on this side's flank (built once per side)
		local fb = model(H, "Footbridge", true)
		wedge(fb, -84, 0, -15, -76, 1.5, -9, N, P.wood, M.WoodPlanks, nil, "Ramp")
		wedge(fb, -84, 0, 9, -76, 1.5, 15, S, P.wood, M.WoodPlanks, nil, "Ramp")
		box(fb, -84, 1.0, -9, -76, 1.5, 9, P.wood, M.WoodPlanks, nil, "Deck")
		box(fb, -84, 0.6, -9, -83.4, 1.0, 9, P.iron, M.Metal, { noshadow = true }, "Girder")
		box(fb, -76.6, 0.6, -9, -76, 1.0, 9, P.iron, M.Metal, { noshadow = true }, "Girder")
		for _, x in ipairs({ -84, -76.25 }) do
			box(fb, x, 4.3, -15, x + 0.25, 4.6, 15, P.iron, M.Metal, { nq = true, noshadow = true }, "Railing")
			box(fb, x, 1.5, -9, x + 0.25, 4.3, 9, P.iron, M.Metal, { t = 1, nq = true, noshadow = true }, "RailingBlocker")
			for i = 0, 12 do
				box(fb, x + 0.05, 1.5, -9 + i * 1.5 - 0.06, x + 0.2, 4.3, -9 + i * 1.5 + 0.06, P.iron, M.Metal, DECO, "Baluster")
			end
		end
		for _, zz in ipairs({ { -17, -13 }, { 13, 17 } }) do
			box(fb, -86.5, 0, zz[1], -84.5, 3.6, zz[2], P.stone, M.Limestone, nil, "EndPost")
			box(fb, -75.5, 0, zz[1], -73.5, 3.6, zz[2], P.stone, M.Limestone, nil, "EndPost")
		end
		lamp(fb, -85.5, -11)
		lamp(fb, -74.5, 11)

		-- the north half of the Perron crossing: bridge from the quay to the island
		local pb = model(H, "PerronBridge", true)
		box(pb, -12, -0.8, -18, -4, 0.2, -8, P.stone, M.Limestone, nil, "Deck")
		box(pb, -12, 0.2, -18, -11, 3.0, -8, P.stone, M.Limestone, nil, "Parapet")
		box(pb, -5, 0.2, -18, -4, 3.0, -8, P.stone, M.Limestone, nil, "Parapet")
		wedge(pb, -12, -3.6, -18, -4, -0.8, -15, S, P.stone, M.Limestone, { flip = true, deco = true }, "ArchHaunch")
		wedge(pb, -12, -3.6, -11, -4, -0.8, -8, N, P.stone, M.Limestone, { flip = true, deco = true }, "ArchHaunch")
		-- island stairs down into the basin, and two island lamps
		stairs(pb, 12, -3, 17, 3, -5, 0.2, W, -5, P.stone, M.Limestone)
		lamp(pb, 10.5, -6.5, 0.2)
		lamp(pb, -10.5, -6.5, 0.2)

		-- the culvert where the canal leaves the map: a house over an iron grate
		local cv = model(H, "Culvert", true)
		local cvC = pick(P.brick)
		box(cv, -125, 3, -9, -109, 27, 9, cvC, M.Brick, nil, "Culvert")
		gableRoof(cv, -125, -9, -109, 9, 27, 7, "Z", pick(P.slate), M.Slate, 0)
		winGrid(cv, E, -109, -7, 7, 3, { 7, 16 }, 3.2, 6)
		box(cv, -125, -5, -8.5, -110, 3, 8.5, C(12, 12, 14), M.SmoothPlastic, { noshadow = true }, "CulvertDark")
		box(cv, -109.8, 2.4, -9.6, -108.6, 4, 9.6, P.lime, M.Limestone, DECO, "ArchRing")
		for i = 0, 11 do
			box(cv, -109.4, -5, -8.6 + i * 1.5, -109.1, 2.4, -8.3 + i * 1.5, P.iron, M.Metal, DECO, "GrateBar")
		end
		box(cv, -109.6, -5, -9, -109, 3, 9, P.iron, M.SmoothPlastic, { t = 1, nq = true, noshadow = true }, "GrateBlocker")
		sign(cv, -108.5, 5.2, 0, 8, 1.4, E, "LE BIEF")
	end

	---------------------------------------------------------------- the centre: canal bed, basin, island, Perron
	local function centre()
		local c = folder(root, "Centre")
		local g = model(c, "Canal", false)
		box(g, -125, -6, -9, 125, -5, 9, P.mud, M.Mud, nil, "CanalBed")
		box(g, -30, -5, -18, 30, -2, 18, P.water, M.SmoothPlastic, { nc = true, nq = true, noshadow = true, t = 0.35, refl = 0.15 }, "BasinWater")
		local isl = model(c, "Island", true)
		box(isl, -12, -6, -8, 12, 0.2, 8, P.lime, M.Limestone, nil, "Island")
		box(isl, -11.6, 0.2, -7.6, 11.6, 0.3, 7.6, P.cobble, M.Cobblestone, { noshadow = true }, "IslandPaving")
		-- Le Perron, Liège's emblem: stepped base, fountain basin, column, pine cone and cross
		local pr = model(c, "LePerron", true)
		box(pr, -5, 0.2, -5, 5, 1.0, 5, P.stone, M.Limestone, nil, "Step")
		box(pr, -3.6, 1.0, -3.6, 3.6, 1.8, 3.6, P.stone, M.Limestone, nil, "Step")
		cylY(pr, 0, 1.8, 3.3, 0, 6.4, P.stone, M.Limestone, nil, "Basin")
		cylY(pr, 0, 3.0, 3.35, 0, 5.4, C(40, 60, 66), M.SmoothPlastic, DECO, "BasinWater")
		box(pr, -1, 3.3, -1, 1, 6, 1, P.lime, M.Limestone, nil, "Pedestal")
		cylY(pr, 0, 6, 17, 0, 1.4, P.lime, M.Limestone, { noshadow = true }, "PerronColumn")
		box(pr, -1.2, 17, -1.2, 1.2, 17.8, 1.2, P.lime, M.Limestone, DECO, "Capital")
		ball(pr, 0, 19, 0, 2.6, P.brass, M.Metal, DECO, "PineCone")
		box(pr, -0.18, 20.2, -0.18, 0.18, 23, 0.18, P.brass, M.Metal, DECO, "Cross")
		box(pr, -0.9, 21.8, -0.18, 0.9, 22.15, 0.18, P.brass, M.Metal, DECO, "Cross")
		for _, d in ipairs({ { 3, 3 }, { -3, 3 }, { 3, -3 }, { -3, -3 } }) do
			box(pr, d[1] - 0.6, 1.8, d[2] - 0.6, d[1] + 0.6, 3.0, d[2] + 0.6, P.lime, M.Limestone, DECO, "Lion")
		end
		-- the edge of the world: invisible walls, and the play area for out-of-bounds checks
		local lim = folder(root, "MapLimits")
		local inv = { t = 1, noshadow = true, nq = true }
		box(lim, -125, -6, -125, 125, 120, -124, P.stone, M.SmoothPlastic, inv, "LimitN")
		box(lim, -125, -6, 124, 125, 120, 125, P.stone, M.SmoothPlastic, inv, "LimitS")
		box(lim, -125, -6, -124, -124, 120, 124, P.stone, M.SmoothPlastic, inv, "LimitW")
		box(lim, 124, -6, -124, 125, 120, 124, P.stone, M.SmoothPlastic, inv, "LimitE")
		local play = marker(markers, "PlayArea", CFrame.new(0, 17, 0), Vector3.new(218, 46, 218))
		play:SetAttribute("Note", "Everything a player can reach is inside this box.")
	end

	for _, team in ipairs(TEAMS) do
		XF = team.xf
		seed = baseSeed
		half(team)
	end
	XF = CFrame.new()
	centre()

	---------------------------------------------------------------- lighting (same scripts as before)
	local ambience = folder(root, "Ambience")
	ambience:SetAttribute("ManageLighting", true)
	ambience:SetAttribute("Mood", "Dusk")
	ambience:SetAttribute("CycleMinutes", 0)
	ambience:SetAttribute("InteriorGrading", true)
	ambience:SetAttribute("FireFlicker", true)
	do
		local zf = folder(ambience, "InteriorZones")
		for _, team in ipairs(TEAMS) do
			XF = team.xf
			for _, z in ipairs(zones) do
				local p = box(zf, z[2], z[3], z[4], z[5], z[6], z[7], P.lit, M.SmoothPlastic, { deco = true, t = 1 }, z[1] .. "_" .. team.name)
				p:SetAttribute("Tint", z[8])
				p:SetAttribute("Brightness", z[9])
				p:SetAttribute("Contrast", z[10])
				p:SetAttribute("Saturation", z[11])
				stats.parts -= 1
			end
		end
		XF = CFrame.new()
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
