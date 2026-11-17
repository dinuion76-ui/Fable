--!nocheck
--[[
	Liège in the 1800s — NPC model generator.

	Blocky, parts-only characters dressed for 1860-1880 Liège: townsfolk, workers, soldiers and police,
	the Apache gang, seven named characters and three bosses. No scripts, no animations, no asset ids.

	local NPCs = require(path)(R)          R = { Instance, Vector3, CFrame, Color3, Enum } (Lune); omit in Studio
	NPCs.roster                            array of character definitions (see ROSTER)
	NPCs.byId[id]                          one definition
	NPCs.build(id, variant, rig, cframe)   one character Model, feet at `cframe`, facing its LookVector
	                                       rig = "R15" (default) or "R6"
	NPCs.library(rig)                      Folder with every character laid out as a gallery, plus NPCCatalog
	NPCs.catalogSource()                   Luau source of the NPCCatalog ModuleScript

	Rigs
	  R15: 15 body Parts + HumanoidRootPart, standard joint and attachment names, so stock R15 animations
	       and accessories work. R6: 6 body Parts with the classic Motor6D frames, so stock R6 animations work.
	  Clothing, hair and props are separate Parts welded to the body (Massless, no collision, no queries,
	  no touch), so physics and hit detection only see the body parts.
]]

return function(R)
	R = R or {}
	local Instance = R.Instance or Instance
	local Vector3 = R.Vector3 or Vector3
	local CFrame = R.CFrame or CFrame
	local Color3 = R.Color3 or Color3
	local Enum = R.Enum or Enum

	local PI = math.pi
	local N, S, E, W = "N", "S", "E", "W"
	local YAW = { N = 0, S = PI, W = PI / 2, E = -PI / 2 }
	local M = Enum.Material
	local SMOOTH = Enum.SurfaceType.Smooth
	local min, abs, floor = math.min, math.abs, math.floor

	local function C(r, g, b)
		return Color3.fromRGB(r, g, b)
	end
	local function shade(c, f)
		return Color3.new(min(1, c.R * f), min(1, c.G * f), min(1, c.B * f))
	end
	local function same(a, b)
		return a.R == b.R and a.G == b.G and a.B == b.B
	end

	---------------------------------------------------------------- palettes
	local SKIN = { C(240, 204, 176), C(226, 184, 150), C(204, 158, 122), C(232, 196, 168), C(178, 128, 94), C(140, 98, 70) }
	local HAIR = {
		black = C(32, 28, 26), brown = C(76, 52, 36), chestnut = C(112, 68, 40), blond = C(192, 158, 98),
		ginger = C(158, 80, 40), grey = C(148, 144, 138), white = C(212, 210, 204), dark = C(52, 40, 32),
	}
	local HAIRS = { HAIR.black, HAIR.brown, HAIR.chestnut, HAIR.dark, HAIR.blond, HAIR.ginger }
	local CL = {
		black = C(28, 28, 32), charcoal = C(50, 50, 54), navy = C(36, 42, 72), brown = C(82, 58, 40), tan = C(146, 118, 84),
		grey = C(108, 106, 102), bottle = C(42, 68, 52), burgundy = C(96, 36, 40), cream = C(224, 214, 192), white = C(234, 232, 224),
		blue = C(68, 94, 148), smock = C(74, 100, 150), red = C(160, 40, 36), mustard = C(172, 138, 60), plum = C(84, 52, 78),
		rust = C(138, 74, 44), olive = C(96, 96, 58), slate = C(86, 96, 108), lilac = C(146, 126, 158), rose = C(172, 108, 108),
		wicker = C(164, 126, 76), wood = C(104, 70, 44), darkwood = C(62, 42, 30), iron = C(52, 54, 58), steel = C(150, 154, 160),
		brass = C(184, 146, 68), gold = C(206, 170, 80), leather = C(96, 62, 38), darkleather = C(58, 40, 28), canvas = C(176, 164, 136),
		soot = C(46, 44, 44), ember = C(255, 128, 40), linen = C(214, 204, 180), stone = C(130, 128, 122), greyblue = C(104, 114, 132),
		belgianYellow = C(232, 190, 40), belgianRed = C(196, 36, 40), blood = C(110, 20, 22), sky = C(150, 170, 196),
	}
	local PRODUCE = { C(180, 40, 36), C(206, 150, 40), C(110, 140, 50), C(214, 120, 40), C(150, 60, 90) }
	local FLOWERS = { C(220, 60, 80), C(240, 220, 90), C(240, 240, 240), C(170, 90, 200), C(250, 140, 60) }

	---------------------------------------------------------------- anatomy
	-- Model space: feet on y = 0, facing -Z, the character's right is +X.
	local function anatomy(b)
		b = b or {}
		local s = b.scale or 1
		local A = { s = s }
		A.tw = 2 * s * (b.width or 1)
		A.td = 1 * s * (b.depth or 1)
		A.th = 2 * s * (b.torso or 1)
		A.lh = 0.2 * A.th
		A.aw = s * (b.limb or 1)
		A.lw = min(s * (b.leg or b.limb or 1), A.tw / 2)
		A.legH = 2 * s * (b.legs or 1)
		A.armH = A.th
		local hd = b.head or 1
		A.hw, A.hh, A.hd = 1.2 * s * hd, 1.2 * s * hd, 1.15 * s * hd
		A.yHip = A.legH
		A.yWaist = A.yHip + A.lh
		A.yNeck = A.yHip + A.th
		A.yTop = A.yNeck + A.hh
		A.hx = A.tw / 4
		A.ax = A.tw / 2 + A.aw / 2
		A.yHand = A.yNeck - A.armH
		A.yWrist = A.yHand + 0.15 * A.armH
		A.yElbow = A.yWrist + 0.4 * A.armH
		A.yAnkle = 0.15 * A.legH
		A.yKnee = A.yAnkle + 0.425 * A.legH
		return A
	end

	local function segBoxes(A)
		local t = {}
		local x2, z2 = A.tw / 2, A.td / 2
		t.HumanoidRootPart = { -x2, A.yHip, -z2, x2, A.yNeck, z2 }
		t.LowerTorso = { -x2, A.yHip, -z2, x2, A.yWaist, z2 }
		t.UpperTorso = { -x2, A.yWaist, -z2, x2, A.yNeck, z2 }
		t.Torso = { -x2, A.yHip, -z2, x2, A.yNeck, z2 }
		t.Head = { -A.hw / 2, A.yNeck, -A.hd / 2, A.hw / 2, A.yTop, A.hd / 2 }
		for _, sd in ipairs({ -1, 1 }) do
			local L = sd < 0 and "Left" or "Right"
			local ax, a = sd * A.ax, A.aw / 2
			t[L .. "UpperArm"] = { ax - a, A.yElbow, -a, ax + a, A.yNeck, a }
			t[L .. "LowerArm"] = { ax - a, A.yWrist, -a, ax + a, A.yElbow, a }
			t[L .. "Hand"] = { ax - a, A.yHand, -a, ax + a, A.yWrist, a }
			t[L .. " Arm"] = { ax - a, A.yHand, -a, ax + a, A.yNeck, a }
			local lx, l = sd * A.hx, A.lw / 2
			t[L .. "UpperLeg"] = { lx - l, A.yKnee, -l, lx + l, A.yHip, l }
			t[L .. "LowerLeg"] = { lx - l, A.yAnkle, -l, lx + l, A.yKnee, l }
			t[L .. "Foot"] = { lx - l, 0, -l, lx + l, A.yAnkle, l }
			t[L .. " Leg"] = { lx - l, 0, -l, lx + l, A.yHip, l }
		end
		return t
	end
	local function boxCenter(b)
		return Vector3.new((b[1] + b[4]) / 2, (b[2] + b[5]) / 2, (b[3] + b[6]) / 2)
	end
	local function boxSize(b)
		return Vector3.new(b[4] - b[1], b[5] - b[2], b[6] - b[3])
	end

	local R6MAP = {
		HumanoidRootPart = "HumanoidRootPart", Head = "Head", UpperTorso = "Torso", LowerTorso = "Torso",
		LeftUpperArm = "Left Arm", LeftLowerArm = "Left Arm", LeftHand = "Left Arm",
		RightUpperArm = "Right Arm", RightLowerArm = "Right Arm", RightHand = "Right Arm",
		LeftUpperLeg = "Left Leg", LeftLowerLeg = "Left Leg", LeftFoot = "Left Leg",
		RightUpperLeg = "Right Leg", RightLowerLeg = "Right Leg", RightFoot = "Right Leg",
	}
	local R6GROUPS = {
		{ "Torso", { "UpperTorso", "LowerTorso" } },
		{ "Left Arm", { "LeftUpperArm", "LeftLowerArm", "LeftHand" } },
		{ "Right Arm", { "RightUpperArm", "RightLowerArm", "RightHand" } },
		{ "Left Leg", { "LeftUpperLeg", "LeftLowerLeg", "LeftFoot" } },
		{ "Right Leg", { "RightUpperLeg", "RightLowerLeg", "RightFoot" } },
	}
	local COLLIDE = { Head = true, Torso = true, UpperTorso = true, LowerTorso = true }

	local function newPart(kind, name, cf, size, color, mat)
		local p
		if kind == "Wedge" then
			p = Instance.new("WedgePart")
		else
			p = Instance.new("Part")
			if kind == "Ball" then
				p.Shape = Enum.PartType.Ball
			elseif kind == "Cyl" then
				p.Shape = Enum.PartType.Cylinder
			end
		end
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = mat
		p.TopSurface = SMOOTH
		p.BottomSurface = SMOOTH
		return p
	end

	---------------------------------------------------------------- wardrobe kit
	local function makeKit(ctx)
		local A, s = ctx.A, ctx.A.s
		local K = { A = A, s = s, variant = ctx.variant, skin = SKIN[1] }
		local hs = A.hw / 1.2
		local yN, yT, H, yH, yW = A.yNeck, A.yTop, A.hh, A.yHip, A.yWaist
		local hw2, hd2, hzf = A.hw / 2, A.hd / 2, -A.hd / 2
		local tw2, td2, zf, zb = A.tw / 2, A.td / 2, -A.td / 2, A.td / 2

		function K.rng()
			return ctx.rng()
		end
		function K.pick(t)
			return t[1 + floor(ctx.rng() * #t) % #t]
		end
		function K.vary(t)
			return t[(ctx.variant - 1) % #t + 1]
		end

		local function piece(seg, kind, lcf, size, color, mat, name, o)
			o = o or {}
			if ctx.xf then lcf = ctx.xf * lcf end
			local p = newPart(kind, name or "Piece", ctx.O * lcf, size, color, mat or M.Fabric)
			p.Anchored = false
			p.Massless = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			if o.t then p.Transparency = o.t end
			if o.shadow == false or (o.shadow == nil and size.X * size.Y * size.Z < 0.03 * s * s * s) then
				p.CastShadow = false
			end
			local host = ctx.partFor(seg)
			local w = Instance.new("Weld")
			w.Name = "Attach"
			w.Part0 = host
			w.Part1 = p
			w.C0 = host.CFrame:Inverse() * p.CFrame
			w.Parent = p
			p.Parent = o.prop and ctx.props() or ctx.outfit
			ctx.count += 1
			return p
		end
		local function blk(seg, x0, y0, z0, x1, y1, z1, color, mat, name, o)
			if x1 < x0 then x0, x1 = x1, x0 end
			if y1 < y0 then y0, y1 = y1, y0 end
			if z1 < z0 then z0, z1 = z1, z0 end
			return piece(seg, "Block", CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), Vector3.new(x1 - x0, y1 - y0, z1 - z0), color, mat, name, o)
		end
		-- Wedge filling the box; the slope descends towards `dir`. o.flip puts the flat face on top.
		local function wdg(seg, x0, y0, z0, x1, y1, z1, dir, color, mat, name, o)
			if x1 < x0 then x0, x1 = x1, x0 end
			if y1 < y0 then y0, y1 = y1, y0 end
			if z1 < z0 then z0, z1 = z1, z0 end
			local sx, sy, sz = x1 - x0, y1 - y0, z1 - z0
			local size = (dir == N or dir == S) and Vector3.new(sx, sy, sz) or Vector3.new(sz, sy, sx)
			local cf = CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2) * CFrame.Angles(0, YAW[dir], 0)
			if o and o.flip then cf = cf * CFrame.Angles(0, 0, PI) end
			return piece(seg, "Wedge", cf, size, color, mat, name or "Wedge", o)
		end
		local function cylY(seg, cx, y0, y1, cz, d, color, mat, name, o)
			return piece(seg, "Cyl", CFrame.new(cx, (y0 + y1) / 2, cz) * CFrame.Angles(0, 0, PI / 2), Vector3.new(y1 - y0, d, d), color, mat, name, o)
		end
		local function cylX(seg, x0, x1, cy, cz, d, color, mat, name, o)
			return piece(seg, "Cyl", CFrame.new((x0 + x1) / 2, cy, cz), Vector3.new(abs(x1 - x0), d, d), color, mat, name, o)
		end
		local function cylZ(seg, cx, cy, z0, z1, d, color, mat, name, o)
			return piece(seg, "Cyl", CFrame.new(cx, cy, (z0 + z1) / 2) * CFrame.Angles(0, PI / 2, 0), Vector3.new(abs(z1 - z0), d, d), color, mat, name, o)
		end
		local function ball(seg, cx, cy, cz, d, color, mat, name, o)
			return piece(seg, "Ball", CFrame.new(cx, cy, cz), Vector3.new(d, d, d), color, mat, name, o)
		end
		local function rbox(seg, cx, cy, cz, sx, sy, sz, rx, ry, rz, color, mat, name, o)
			return piece(seg, "Block", CFrame.new(cx, cy, cz) * CFrame.Angles(rx, ry, rz), Vector3.new(sx, sy, sz), color, mat, name, o)
		end
		-- Square rod between two model-space points.
		local function rod(seg, a, b, d, color, mat, name, o)
			local v = b - a
			local cf
			if abs(v.Unit.Y) > 0.999 then
				cf = CFrame.new((a + b) / 2) * CFrame.Angles(PI / 2, 0, 0)
			else
				cf = CFrame.new((a + b) / 2, b)
			end
			return piece(seg, "Block", cf, Vector3.new(d, d, v.Magnitude), color, mat, name, o)
		end
		local function V(x, y, z)
			return Vector3.new(x, y, z)
		end
		local function handSeg(sd)
			return sd < 0 and "LeftHand" or "RightHand"
		end
		local function handPos(sd)
			return sd * A.ax, A.yHand
		end
		local PROP = { prop = true }
		local PROPNS = { prop = true, shadow = false }
		local DET = { shadow = false }

		---------------------------------------------------------------- body colours
		local function groupOf(seg)
			if seg == "UpperTorso" then return "torso" end
			if seg == "LowerTorso" then return "lower" end
			if seg:find("UpperArm") then return "arms" end
			if seg:find("LowerArm") then return "forearms" end
			if seg:find("Hand") then return "hands" end
			if seg:find("UpperLeg") then return "legs" end
			if seg:find("LowerLeg") then return "shins" end
			return "feet"
		end
		-- t: skin, torso, lower, arms, forearms, hands, legs, shins, feet; t.mat = { group = Material }
		function K.paint(t)
			K.skin = t.skin or K.skin
			local skin = K.skin
			local function spec(seg)
				local g = groupOf(seg)
				local c
				if g == "torso" then c = t.torso
				elseif g == "lower" then c = t.lower or t.legs
				elseif g == "arms" then c = t.arms or t.torso
				elseif g == "forearms" then c = t.forearms or t.arms or t.torso
				elseif g == "hands" then c = t.hands or skin
				elseif g == "legs" then c = t.legs
				elseif g == "shins" then c = t.shins or t.legs
				else c = t.feet or t.shins or t.legs end
				local mat = (t.mat and t.mat[g]) or (same(c, skin) and M.SmoothPlastic) or (g == "feet" and M.Leather) or M.Fabric
				return c, mat
			end
			local head = ctx.body.Head
			head.Color = skin
			head.Material = M.SmoothPlastic
			if ctx.rig == "R15" then
				for _, grp in ipairs(R6GROUPS) do
					for _, seg in ipairs(grp[2]) do
						local c, m = spec(seg)
						ctx.body[seg].Color = c
						ctx.body[seg].Material = m
					end
				end
			else
				for _, grp in ipairs(R6GROUPS) do
					local list = grp[2]
					local c0, m0 = spec(list[1])
					local p = ctx.body[grp[1]]
					p.Color = c0
					p.Material = m0
					for i = 2, #list do
						local c, m = spec(list[i])
						if not same(c, c0) or m ~= m0 then
							local b = ctx.boxes[list[i]]
							local e = 0.025 * s
							local yb = (i == #list and grp[1] ~= "Torso") and (b[2] - e) or b[2]
							blk(list[i], b[1] - e, yb, b[3] - e, b[4] + e, b[5], b[6] + e, c, m, "R6Paint", DET)
						end
					end
				end
			end
		end

		---------------------------------------------------------------- face, hair, beards
		function K.face(o)
			o = o or {}
			local skin = K.skin
			local eye = o.eye or C(30, 26, 24)
			local brow = o.brow or K.hairColor or HAIR.dark
			local SP = M.SmoothPlastic
			for _, sd in ipairs({ -1, 1 }) do
				local ex = sd * 0.25 * hs
				blk("Head", ex - 0.085 * hs, yN + 0.5 * H, hzf - 0.03 * hs, ex + 0.085 * hs, yN + 0.5 * H + 0.15 * hs, hzf + 0.02, eye, SP, "Eye", DET)
				local by = yN + 0.73 * H
				local bh = (o.fem and 0.045 or 0.075) * hs
				if o.angry then
					rbox("Head", ex + sd * 0.02 * hs, by - 0.02 * hs, hzf - 0.01 * hs, 0.36 * hs, bh, 0.05 * hs, 0, 0, sd * 0.32, brow, SP, "Brow", DET)
				else
					blk("Head", ex - 0.16 * hs, by - bh / 2, hzf - 0.035 * hs, ex + 0.16 * hs, by + bh / 2, hzf + 0.015, brow, SP, "Brow", DET)
				end
				if not o.noEars then
					blk("Head", sd * hw2, yN + 0.38 * H, -0.09 * hs, sd * (hw2 + 0.06 * hs), yN + 0.62 * H, 0.09 * hs, skin, SP, "Ear", DET)
				end
			end
			blk("Head", -0.07 * hs, yN + 0.36 * H, hzf - 0.11 * hs, 0.07 * hs, yN + 0.52 * H, hzf + 0.02, shade(skin, 0.92), SP, "Nose", DET)
			if not o.noMouth then
				local lips = o.lips or (o.fem and C(158, 76, 72) or C(112, 62, 54))
				blk("Head", -0.14 * hs, yN + 0.23 * H, hzf - 0.02 * hs, 0.14 * hs, yN + 0.28 * H, hzf + 0.02, lips, SP, "Mouth", DET)
			end
			if o.scar then
				rbox("Head", -0.25 * hs, yN + 0.55 * H, hzf - 0.04 * hs, 0.05 * hs, 0.55 * hs, 0.03 * hs, 0, 0, 0.35, shade(skin, 1.15), SP, "Scar", DET)
			end
			if o.soot then
				local d = shade(skin, 0.55)
				blk("Head", 0.12 * hs, yN + 0.3 * H, hzf - 0.012, 0.42 * hs, yN + 0.46 * H, hzf + 0.02, d, SP, "Soot", DET)
				blk("Head", -0.45 * hs, yN + 0.66 * H, hzf - 0.012, -0.05 * hs, yN + 0.7 * H, hzf + 0.02, d, SP, "Soot", DET)
			end
			if o.blush then
				for _, sd in ipairs({ -1, 1 }) do
					blk("Head", sd * 0.3 * hs - 0.08 * hs, yN + 0.34 * H, hzf - 0.012, sd * 0.3 * hs + 0.08 * hs, yN + 0.42 * H, hzf + 0.02, C(214, 130, 120), SP, "Blush", DET)
				end
			end
		end

		-- styles: short, bald, long, bun, messy, cropped
		function K.hair(style, c)
			K.hairColor = c
			if not style or style == "none" then return end
			local mat = M.SmoothPlastic
			local t = 0.045 * hs
			local xo, zo = hw2 + t, hd2 + t
			local bald = style == "bald"
			if not bald then
				local fr = (style == "cropped") and (hzf + 0.05 * hs) or (hzf - t)
				blk("Head", -xo, yN + (style == "cropped" and 0.88 or 0.83) * H, fr, xo, yT + (style == "cropped" and 0.03 or 0.07) * hs, zo, c, mat, "Hair")
			end
			local backTop = bald and (yN + 0.66 * H) or (yN + 0.83 * H)
			local backLow = (style == "long") and (yN - 0.35 * s) or (yN + (bald and 0.3 or 0.22) * H)
			blk("Head", -xo, backLow, 0.15 * hd2, xo, backTop, zo, c, mat, "HairBack")
			blk("Head", -xo, yN + (bald and 0.45 or 0.55) * H, -0.3 * hd2, xo, backTop, 0.15 * hd2, c, mat, "HairSides")
			if style == "bun" then
				ball("Head", 0, yN + 0.78 * H, zo + 0.12 * hs, 0.5 * hs, c, mat, "Bun")
			elseif style == "messy" then
				rbox("Head", -0.25 * hs, yT + 0.1 * hs, -0.1 * hs, 0.38 * hs, 0.16 * hs, 0.32 * hs, 0.3, 0.4, 0.25, c, mat, "Tuft", DET)
				rbox("Head", 0.2 * hs, yT + 0.12 * hs, 0.15 * hs, 0.32 * hs, 0.16 * hs, 0.36 * hs, -0.2, -0.3, -0.3, c, mat, "Tuft", DET)
				rbox("Head", 0.05 * hs, yN + 0.86 * H, hzf - 0.06 * hs, 0.55 * hs, 0.13 * hs, 0.1 * hs, 0, 0, 0.15, c, mat, "Fringe", DET)
			end
		end

		-- styles: mustache, walrus, handlebar, imperial, muttonchops, friendly (chops + mustache), full,
		--         goatee, sideburns, stubble
		function K.beard(style, c)
			if not style or style == "none" then return end
			c = c or K.hairColor or HAIR.dark
			local mat = M.SmoothPlastic
			local function mustache(w, y0, y1, z)
				blk("Head", -w * hs, yN + y0 * H, hzf - (z or 0.07) * hs, w * hs, yN + y1 * H, hzf + 0.02, c, mat, "Mustache", DET)
			end
			local function chops()
				for _, sd in ipairs({ -1, 1 }) do
					blk("Head", sd * (hw2 - 0.2 * hs), yN + 0.08 * H, hzf - 0.045 * hs, sd * (hw2 + 0.035 * hs), yN + 0.62 * H, 0.05 * hs, c, mat, "Whiskers")
				end
			end
			local function goatee(long)
				blk("Head", -0.08 * hs, yN - (long and 0.1 or 0.0) * H, hzf - 0.06 * hs, 0.08 * hs, yN + 0.21 * H, hzf + 0.02, c, mat, "Goatee", DET)
			end
			if style == "mustache" then
				mustache(0.24, 0.29, 0.36)
			elseif style == "walrus" then
				mustache(0.3, 0.19, 0.37)
			elseif style == "handlebar" or style == "imperial" then
				mustache(0.24, 0.29, 0.36)
				for _, sd in ipairs({ -1, 1 }) do
					rbox("Head", sd * 0.31 * hs, yN + 0.37 * H, hzf - 0.05 * hs, 0.17 * hs, 0.05 * hs, 0.05 * hs, 0, 0, sd * 0.7, c, mat, "MustacheTip", DET)
				end
				if style == "imperial" then goatee(true) end
			elseif style == "muttonchops" then
				chops()
			elseif style == "friendly" then
				chops()
				mustache(0.3, 0.27, 0.36)
			elseif style == "full" then
				chops()
				blk("Head", -(hw2 + 0.035 * hs), yN - 0.12 * H, hzf - 0.07 * hs, hw2 + 0.035 * hs, yN + 0.33 * H, hzf + 0.3 * hd2, c, mat, "Beard")
				mustache(0.27, 0.28, 0.37, 0.1)
			elseif style == "goatee" then
				goatee(false)
				mustache(0.2, 0.3, 0.36)
			elseif style == "sideburns" then
				for _, sd in ipairs({ -1, 1 }) do
					blk("Head", sd * hw2, yN + 0.3 * H, -0.3 * hs, sd * (hw2 + 0.03 * hs), yN + 0.62 * H, -0.09 * hs, c, mat, "Sideburn", DET)
					ball("Head", sd * (hw2 + 0.01 * hs), yN + 0.3 * H, -0.26 * hs, 0.13 * hs, c, mat, "Curl", DET)
				end
			elseif style == "stubble" then
				blk("Head", -(hw2 + 0.005), yN + 0.02 * H, hzf - 0.012, hw2 + 0.005, yN + 0.33 * H, hzf + 0.05, c, mat, "Stubble", DET)
			end
		end

		---------------------------------------------------------------- hats
		local function hatTilt(o, fn)
			if o and (o.tilt or o.pitch or o.turn) then
				local pv = CFrame.new(0, yT, 0)
				ctx.xf = pv * CFrame.Angles(o.pitch or 0, o.turn or 0, o.tilt or 0) * pv:Inverse()
			end
			fn()
			ctx.xf = nil
		end
		local function cockade(x, y, z0, z1, d)
			cylZ("Head", x, y, z0, z1, d, CL.black, M.Fabric, "Cockade", DET)
			cylZ("Head", x, y, z0 - 0.01, z1, d * 0.66, CL.belgianYellow, M.Fabric, "Cockade", DET)
			cylZ("Head", x, y, z0 - 0.02, z1, d * 0.33, CL.belgianRed, M.Fabric, "Cockade", DET)
		end

		function K.tophat(c, o)
			o = o or {}
			hatTilt(o, function()
				local h = (o.h or 1) * hs
				local y0 = yT - 0.02 * hs
				cylY("Head", 0, y0, y0 + 0.07 * hs, 0, A.hw * 1.5, c, M.Fabric, "HatBrim")
				cylY("Head", 0, y0 + 0.07 * hs, y0 + h, 0, A.hw, c, M.Fabric, "HatCrown")
				cylY("Head", 0, y0 + 0.07 * hs, y0 + 0.27 * hs, 0, A.hw + 0.04 * hs, o.band or C(18, 18, 20), M.Fabric, "HatBand")
				if o.cockade then
					cylX("Head", -0.66 * hs, -0.6 * hs, y0 + 0.4 * hs, 0, 0.3 * hs, CL.belgianYellow, M.Fabric, "Cockade", DET)
					cylX("Head", -0.67 * hs, -0.6 * hs, y0 + 0.4 * hs, 0, 0.16 * hs, CL.belgianRed, M.Fabric, "Cockade", DET)
				end
				if o.dent then
					rbox("Head", 0.2 * hs, y0 + h - 0.05 * hs, -0.1 * hs, 0.5 * hs, 0.14 * hs, 0.5 * hs, 0.3, 0.4, 0.2, shade(c, 0.8), M.Fabric, "Dent", DET)
				end
			end)
		end
		function K.bowler(c, o)
			o = o or {}
			hatTilt(o, function()
				local y0 = yT - 0.02 * hs
				cylY("Head", 0, y0, y0 + 0.06 * hs, 0, A.hw * 1.42, c, M.Fabric, "HatBrim")
				ball("Head", 0, yT + 0.1 * hs, 0, A.hw, c, M.Fabric, "HatCrown")
				cylY("Head", 0, y0 + 0.05 * hs, y0 + 0.17 * hs, 0, A.hw * 1.01, o.band or shade(c, 0.7), M.Fabric, "HatBand")
			end)
		end
		function K.flatcap(c, o)
			o = o or {}
			hatTilt(o, function()
				local tall = (o.big and 0.3 or 0.17) * hs
				local over = (o.big and 0.16 or 0.08) * hs
				blk("Head", -hw2 - 0.05 * hs, yT - 0.06 * hs, hzf - over, hw2 + 0.05 * hs, yT + tall, hd2 + 0.05 * hs, c, M.Fabric, "Cap")
				wdg("Head", -hw2 + 0.06 * hs, yT - 0.09 * hs, hzf - over - 0.36 * hs, hw2 - 0.06 * hs, yT + 0.03 * hs, hzf - over, N, shade(c, 0.85), M.Fabric, "CapPeak")
				ball("Head", 0, yT + tall, -over / 2, 0.14 * hs, shade(c, 0.8), M.Fabric, "CapButton", DET)
			end)
		end
		-- o.band, o.top (crown top colour), o.h, o.badge, o.strap, o.braid
		function K.kepi(c, o)
			o = o or {}
			hatTilt(o, function()
				local h = (o.h or 0.42) * hs
				local y1 = yT + 0.06 * hs
				blk("Head", -hw2 - 0.04 * hs, yT - 0.16 * hs, hzf - 0.04 * hs, hw2 + 0.04 * hs, y1, hd2 + 0.04 * hs, o.band or c, M.Fabric, "KepiBand")
				cylY("Head", 0, y1, y1 + h, 0, A.hw * 0.98, c, M.Fabric, "KepiCrown")
				cylY("Head", 0, y1 + h - 0.01, y1 + h + 0.04 * hs, 0, A.hw * 0.98, o.top or shade(c, 0.85), M.Fabric, "KepiTop")
				wdg("Head", -0.42 * hs, yT - 0.2 * hs, hzf - 0.42 * hs, 0.42 * hs, yT - 0.1 * hs, hzf - 0.04 * hs, N, C(20, 20, 22), M.SmoothPlastic, "Visor")
				if o.braid then
					blk("Head", -hw2 - 0.05 * hs, yT - 0.03 * hs, hzf - 0.05 * hs, hw2 + 0.05 * hs, yT + 0.02 * hs, hd2 + 0.05 * hs, o.braid, M.Metal, "Braid", DET)
				end
				if o.strap then
					blk("Head", -hw2 - 0.05 * hs, yT - 0.15 * hs, hzf - 0.06 * hs, hw2 + 0.05 * hs, yT - 0.1 * hs, hzf - 0.03 * hs, o.strap, M.Metal, "ChinStrap", DET)
				end
				if o.badge then
					blk("Head", -0.08 * hs, yT - 0.08 * hs, hzf - 0.07 * hs, 0.08 * hs, yT + 0.05 * hs, hzf - 0.03 * hs, o.badge, M.Metal, "Badge", DET)
				end
			end)
		end
		function K.shako(c, o)
			o = o or {}
			hatTilt(o, function()
				local h = 0.75 * hs
				local y1 = yT + 0.06 * hs
				blk("Head", -hw2 - 0.04 * hs, yT - 0.16 * hs, hzf - 0.04 * hs, hw2 + 0.04 * hs, y1, hd2 + 0.04 * hs, c, M.Fabric, "ShakoBand")
				cylY("Head", 0, y1, y1 + h, 0, A.hw * 0.98, c, M.Fabric, "ShakoCrown")
				cylY("Head", 0, y1 + h, y1 + h + 0.07 * hs, 0, A.hw * 1.08, shade(c, 0.8), M.Leather, "ShakoTop")
				wdg("Head", -0.42 * hs, yT - 0.2 * hs, hzf - 0.42 * hs, 0.42 * hs, yT - 0.1 * hs, hzf - 0.04 * hs, N, C(20, 20, 22), M.SmoothPlastic, "Visor")
				ball("Head", 0, y1 + h + 0.18 * hs, -0.42 * hs, 0.3 * hs, o.plume or CL.red, M.Fabric, "Pompon")
				blk("Head", -0.14 * hs, y1 + 0.1 * hs, -0.52 * hs, 0.14 * hs, y1 + 0.42 * hs, -0.47 * hs, CL.brass, M.Metal, "ShakoPlate", DET)
				blk("Head", -hw2 - 0.05 * hs, yT - 0.15 * hs, hzf - 0.06 * hs, hw2 + 0.05 * hs, yT - 0.1 * hs, hzf - 0.03 * hs, CL.brass, M.Metal, "ChinScales", DET)
			end)
		end
		function K.bicorne(c, o)
			o = o or {}
			hatTilt(o, function()
				local X = 1.05 * hs
				blk("Head", -hw2 - 0.04 * hs, yT - 0.12 * hs, hzf - 0.04 * hs, hw2 + 0.04 * hs, yT + 0.04 * hs, hd2 + 0.04 * hs, c, M.Fabric, "HatBand")
				blk("Head", -X, yT - 0.02 * hs, -0.2 * hs, X, yT + 0.3 * hs, 0.2 * hs, c, M.Fabric, "Bicorne")
				wdg("Head", -X, yT + 0.3 * hs, -0.2 * hs, 0, yT + 0.72 * hs, 0.2 * hs, W, c, M.Fabric, "Bicorne")
				wdg("Head", 0, yT + 0.3 * hs, -0.2 * hs, X, yT + 0.72 * hs, 0.2 * hs, E, c, M.Fabric, "Bicorne")
				if o.trim then
					blk("Head", -X - 0.02, yT - 0.04 * hs, -0.21 * hs, X + 0.02, yT + 0.02 * hs, 0.21 * hs, o.trim, M.Fabric, "Trim", DET)
				end
				cockade(-0.45 * hs, yT + 0.36 * hs, -0.25 * hs, -0.2 * hs, 0.32 * hs)
			end)
		end
		function K.bonnet(c, o)
			o = o or {}
			local t = 0.08 * hs
			local fr = hzf - 0.14 * hs
			blk("Head", -hw2 - t, yT - 0.02, fr, hw2 + t, yT + 0.16 * hs, hd2 + t, c, M.Fabric, "Bonnet")
			for _, sd in ipairs({ -1, 1 }) do
				blk("Head", sd * hw2, yN + 0.32 * H, fr, sd * (hw2 + t), yT, hd2 + t, c, M.Fabric, "BonnetSide")
			end
			blk("Head", -hw2, yN + 0.3 * H, hd2, hw2, yT, hd2 + t, c, M.Fabric, "BonnetBack")
			local rib = o.ribbon or shade(c, 0.7)
			blk("Head", -hw2 - 0.01, yN + 0.02 * H, hzf - 0.04 * hs, hw2 + 0.01, yN + 0.08 * H, hzf + 0.05, rib, M.Fabric, "Ribbon", DET)
			ball("Head", 0.38 * hs, yN + 0.05 * H, hzf - 0.08 * hs, 0.22 * hs, rib, M.Fabric, "Bow", DET)
			if o.flower then
				ball("Head", -0.4 * hs, yT + 0.18 * hs, -0.2 * hs, 0.24 * hs, o.flower, M.Fabric, "Flower", DET)
				ball("Head", -0.25 * hs, yT + 0.2 * hs, -0.05 * hs, 0.2 * hs, C(90, 120, 60), M.Fabric, "Leaf", DET)
			end
		end
		-- knot = "back" (default) or "chin"
		function K.scarf(c, o)
			o = o or {}
			local t = 0.05 * hs
			local fr = hzf - 0.05 * hs
			blk("Head", -hw2 - t, yN + 0.8 * H, fr, hw2 + t, yT + 0.08 * hs, hd2 + t, c, M.Fabric, "Headscarf")
			for _, sd in ipairs({ -1, 1 }) do
				blk("Head", sd * hw2, yN + 0.25 * H, fr + 0.06 * hs, sd * (hw2 + t), yN + 0.8 * H, hd2 + t, c, M.Fabric, "HeadscarfSide")
			end
			blk("Head", -hw2, yN + 0.15 * H, hd2, hw2, yN + 0.8 * H, hd2 + t, c, M.Fabric, "HeadscarfBack")
			if o.knot == "chin" then
				ball("Head", 0, yN + 0.02 * H, hzf - 0.1 * hs, 0.26 * hs, shade(c, 0.85), M.Fabric, "Knot", DET)
			else
				ball("Head", 0, yN + 0.2 * H, hd2 + 0.12 * hs, 0.3 * hs, shade(c, 0.85), M.Fabric, "Knot", DET)
				wdg("Head", -0.12 * hs, yN - 0.25 * H, hd2 + 0.02, 0.12 * hs, yN + 0.15 * H, hd2 + 0.12 * hs, S, shade(c, 0.85), M.Fabric, "KnotTail", DET)
			end
			if o.dots then
				for i = 0, 3 do
					blk("Head", -0.45 * hs + i * 0.3 * hs, yT + 0.081 * hs, -0.3 * hs + (i % 2) * 0.3 * hs, -0.37 * hs + i * 0.3 * hs, yT + 0.1 * hs, -0.22 * hs + (i % 2) * 0.3 * hs, o.dots, M.Fabric, "Dot", DET)
				end
			end
		end
		function K.mobcap(c)
			blk("Head", -hw2 - 0.1 * hs, yT - 0.18 * hs, hzf - 0.06 * hs, hw2 + 0.1 * hs, yT + 0.22 * hs, hd2 + 0.12 * hs, c, M.Fabric, "Mobcap")
			blk("Head", -hw2 - 0.12 * hs, yT - 0.24 * hs, hzf - 0.1 * hs, hw2 + 0.12 * hs, yT - 0.14 * hs, hzf - 0.02, c, M.Fabric, "Frill", DET)
			blk("Head", -hw2 - 0.02, yN + 0.55 * H, 0, hw2 + 0.02, yT - 0.15 * hs, hd2 + 0.08 * hs, c, M.Fabric, "MobcapBack")
		end
		function K.biretta(c)
			blk("Head", -hw2 - 0.04 * hs, yT - 0.1 * hs, hzf - 0.04 * hs, hw2 + 0.04 * hs, yT + 0.3 * hs, hd2 + 0.04 * hs, c, M.Fabric, "Biretta")
			for _, x in ipairs({ -0.32, 0, 0.32 }) do
				blk("Head", x * hs - 0.03 * hs, yT + 0.3 * hs, -0.4 * hs, x * hs + 0.03 * hs, yT + 0.48 * hs, 0.4 * hs, c, M.Fabric, "Fin", DET)
			end
			ball("Head", 0, yT + 0.52 * hs, 0, 0.2 * hs, c, M.Fabric, "Pompom", DET)
		end
		function K.shovelhat(c)
			cylY("Head", 0, yT - 0.02 * hs, yT + 0.05 * hs, 0, A.hw * 1.9, c, M.Fabric, "HatBrim")
			ball("Head", 0, yT + 0.05 * hs, 0, A.hw * 0.92, c, M.Fabric, "HatCrown")
		end
		function K.calotte(c, o)
			o = o or {}
			hatTilt({ pitch = 0.22 }, function()
				cylY("Head", 0, yT - 0.06 * hs, yT + 0.2 * hs, 0.05 * hs, A.hw * 1.06, c, M.Fabric, "Calotte")
				wdg("Head", -0.3 * hs, yT - 0.08 * hs, hzf - 0.25 * hs, 0.3 * hs, yT - 0.02 * hs, hzf, N, C(20, 20, 22), M.SmoothPlastic, "Visor")
				blk("Head", -0.62 * hs, yT + 0.02 * hs, -0.03, 0.62 * hs, yT + 0.06 * hs, 0.03, o.band or CL.gold, M.Fabric, "Band", DET)
			end)
		end
		-- Nun: white wimple framing the face, black veil down the back.
		function K.veil(c, wimple)
			wimple = wimple or CL.white
			local t = 0.06 * hs
			blk("Head", -hw2 - 0.02, yN + 0.78 * H, hzf - 0.04 * hs, hw2 + 0.02, yN + 0.94 * H, hzf + 0.1 * hs, wimple, M.Fabric, "Wimple", DET)
			for _, sd in ipairs({ -1, 1 }) do
				blk("Head", sd * (hw2 - 0.12 * hs), yN - 0.02, hzf - 0.04 * hs, sd * (hw2 + 0.02), yN + 0.94 * H, hzf + 0.3 * hs, wimple, M.Fabric, "Wimple", DET)
			end
			blk("Head", -hw2 - 0.04 * hs, yN - 0.5 * s, hzf - 0.06 * hs, hw2 + 0.04 * hs, yN + 0.1 * H, hzf + 0.25 * hs, wimple, M.Fabric, "Guimpe")
			blk("Head", -hw2 - t, yN + 0.9 * H, hzf - 0.05 * hs, hw2 + t, yT + 0.1 * hs, hd2 + t, c, M.Fabric, "Veil")
			for _, sd in ipairs({ -1, 1 }) do
				blk("Head", sd * (hw2 + 0.02), yN - 0.4 * s, hzf + 0.04 * hs, sd * (hw2 + t + 0.02), yN + 0.94 * H, hd2 + t, c, M.Fabric, "Veil")
			end
			blk("Head", -hw2 - t, yN - 1.2 * s, hd2, hw2 + t, yT, hd2 + t + 0.04, c, M.Fabric, "VeilBack")
		end
		-- Foundry hood with leather mask.
		function K.hood(c, mask)
			local t = 0.1 * hs
			blk("Head", -hw2 - t, yN + 0.82 * H, hzf - 0.08 * hs, hw2 + t, yT + 0.12 * hs, hd2 + t, c, M.Leather, "Hood")
			for _, sd in ipairs({ -1, 1 }) do
				blk("Head", sd * hw2, yN - 0.08 * s, hzf - 0.08 * hs, sd * (hw2 + t), yN + 0.82 * H, hd2 + t, c, M.Leather, "HoodSide")
			end
			blk("Head", -hw2, yN - 0.08 * s, hd2, hw2, yN + 0.82 * H, hd2 + t, c, M.Leather, "HoodBack")
			if mask then
				blk("Head", -hw2 - 0.02, yN + 0.02 * H, hzf - 0.08 * hs, hw2 + 0.02, yN + 0.44 * H, hzf + 0.1 * hs, mask, M.Leather, "Mask")
				for _, x in ipairs({ -0.3, -0.1, 0.1, 0.3 }) do
					blk("Head", x * hs - 0.03 * hs, yN + 0.12 * H, hzf - 0.1 * hs, x * hs + 0.03 * hs, yN + 0.3 * H, hzf - 0.07 * hs, CL.iron, M.Metal, "MaskVent", DET)
				end
			end
		end

		---------------------------------------------------------------- spectacles and the like
		function K.spectacles(frame, o)
			o = o or {}
			frame = frame or CL.iron
			for _, sd in ipairs({ -1, 1 }) do
				local ex = sd * 0.25 * hs
				blk("Head", ex - 0.13 * hs, yN + 0.47 * H, hzf - 0.09 * hs, ex + 0.13 * hs, yN + 0.67 * H, hzf - 0.06 * hs, C(196, 214, 224), M.Glass, "Lens", { t = 0.45, shadow = false })
				if not o.pincenez then
					blk("Head", sd * hw2, yN + 0.6 * H, hzf - 0.06 * hs, sd * (hw2 + 0.02), yN + 0.63 * H, 0, frame, M.Metal, "Temple", DET)
				end
			end
			blk("Head", -0.12 * hs, yN + 0.6 * H, hzf - 0.09 * hs, 0.12 * hs, yN + 0.63 * H, hzf - 0.06 * hs, frame, M.Metal, "Bridge", DET)
			if o.pincenez then
				rod("Head", V(0.38 * hs, yN + 0.5 * H, hzf - 0.07 * hs), V(0.45 * s, yN - 0.5 * s, zf - 0.06 * s), 0.025 * s, CL.gold, M.Metal, "Chain", DET)
			end
		end
		function K.goggles(lens)
			for _, sd in ipairs({ -1, 1 }) do
				local ex = sd * 0.25 * hs
				cylZ("Head", ex, yN + 0.57 * H, hzf - 0.16 * hs, hzf + 0.02, 0.36 * hs, CL.iron, M.Metal, "Goggle")
				cylZ("Head", ex, yN + 0.57 * H, hzf - 0.18 * hs, hzf - 0.15 * hs, 0.26 * hs, lens or CL.ember, M.Neon, "GoggleLens", DET)
			end
			blk("Head", -hw2 - 0.12 * hs, yN + 0.52 * H, hzf - 0.11 * hs, hw2 + 0.12 * hs, yN + 0.63 * H, hd2 + 0.12 * hs, CL.darkleather, M.Leather, "GoggleStrap")
		end
		function K.pipe()
			rod("Head", V(0.14 * hs, yN + 0.26 * H, hzf), V(0.3 * hs, yN + 0.18 * H, hzf - 0.38 * hs), 0.06 * hs, CL.darkwood, M.Wood, "PipeStem", DET)
			cylY("Head", 0.32 * hs, yN + 0.14 * H, yN + 0.36 * H, hzf - 0.42 * hs, 0.17 * hs, CL.darkwood, M.Wood, "PipeBowl", DET)
		end
		function K.cigarette()
			rod("Head", V(0.14 * hs, yN + 0.26 * H, hzf), V(0.22 * hs, yN + 0.23 * H, hzf - 0.32 * hs), 0.045 * hs, CL.white, M.SmoothPlastic, "Cigarette", DET)
			local tip = ball("Head", 0.225 * hs, yN + 0.23 * H, hzf - 0.33 * hs, 0.055 * hs, CL.ember, M.Neon, "Ember", DET)
			local sm = Instance.new("Smoke")
			sm.Size = 0.4
			sm.Opacity = 0.06
			sm.RiseVelocity = 1.5
			sm.Color = C(200, 200, 200)
			sm.Parent = tip
		end
		-- Scarf pulled up over the nose and mouth.
		function K.facescarf(c)
			blk("Head", -hw2 - 0.03 * hs, yN - 0.05 * s, hzf - 0.06 * hs, hw2 + 0.03 * hs, yN + 0.45 * H, hd2 + 0.03 * hs, c, M.Fabric, "FaceScarf")
			blk("UpperTorso", -0.5 * s, yN - 0.25 * s, zf - 0.08 * s, 0.5 * s, yN + 0.02, zb - 0.1 * s, c, M.Fabric, "ScarfDrape")
			ball("Head", 0, yN + 0.3 * H, hd2 + 0.1 * hs, 0.25 * hs, shade(c, 0.85), M.Fabric, "ScarfKnot", DET)
		end
		function K.earring(sd)
			ball("Head", (sd or 1) * (hw2 + 0.04 * hs), yN + 0.36 * H, 0, 0.09 * hs, CL.gold, M.Metal, "Earring", DET)
		end

		---------------------------------------------------------------- torso
		-- Inverted triangle of `c` on the chest (the opening of a coat or waistcoat).
		function K.vneck(c, depth, w)
			depth = (depth or 0.9) * s
			w = (w or 0.42) * s
			local z0, z1 = zf - 0.035 * s, zf + 0.01
			wdg("UpperTorso", -w, yN - depth, z0, 0, yN, z1, W, c, M.Fabric, "VFront", { flip = true })
			wdg("UpperTorso", 0, yN - depth, z0, w, yN, z1, E, c, M.Fabric, "VFront", { flip = true })
		end
		-- style: "cravat", "bow", "neckerchief", "collar", "roman"
		function K.shirtFront(shirt, tie, style)
			blk("UpperTorso", -0.13 * s, yN - 0.48 * s, zf - 0.05 * s, 0.13 * s, yN, zf, shirt, M.Fabric, "ShirtFront", DET)
			for _, sd in ipairs({ -1, 1 }) do
				rbox("UpperTorso", sd * 0.17 * s, yN - 0.05 * s, zf - 0.07 * s, 0.2 * s, 0.14 * s, 0.04 * s, 0, 0, sd * 0.6, shirt, M.Fabric, "CollarPoint", DET)
			end
			if style == "cravat" then
				blk("UpperTorso", -0.15 * s, yN - 0.26 * s, zf - 0.09 * s, 0.15 * s, yN + 0.02 * s, zf - 0.03 * s, tie, M.Fabric, "Cravat", DET)
				ball("UpperTorso", 0, yN - 0.06 * s, zf - 0.1 * s, 0.14 * s, tie, M.Fabric, "CravatPin", DET)
			elseif style == "bow" then
				blk("UpperTorso", -0.2 * s, yN - 0.14 * s, zf - 0.09 * s, 0.2 * s, yN - 0.03 * s, zf - 0.04 * s, tie, M.Fabric, "BowTie", DET)
			elseif style == "neckerchief" then
				blk("UpperTorso", -0.45 * s, yN - 0.1 * s, zf - 0.06 * s, 0.45 * s, yN + 0.03 * s, zb - 0.1 * s, tie, M.Fabric, "Neckerchief", DET)
				ball("UpperTorso", 0.1 * s, yN - 0.12 * s, zf - 0.1 * s, 0.2 * s, tie, M.Fabric, "Knot", DET)
				wdg("UpperTorso", -0.02 * s, yN - 0.5 * s, zf - 0.1 * s, 0.22 * s, yN - 0.15 * s, zf - 0.05 * s, E, tie, M.Fabric, "KnotTail", { flip = true, shadow = false })
			elseif style == "roman" then
				blk("UpperTorso", -0.08 * s, yN - 0.12 * s, zf - 0.08 * s, 0.08 * s, yN + 0.02 * s, zf - 0.03 * s, CL.white, M.Fabric, "CollarTab", DET)
			end
		end
		-- n buttons down the front; o.x (column offset), o.top, o.bottom, o.double, o.z
		function K.buttons(c, n, o)
			o = o or {}
			local top, bot = o.top or (yN - 0.55 * s), o.bottom or (yW + 0.1 * s)
			local cols = o.double and { -0.3 * s, 0.3 * s } or { o.x or 0 }
			local z = o.z or zf
			for _, x in ipairs(cols) do
				for i = 0, n - 1 do
					local y = (n == 1) and top or (top - (top - bot) * i / (n - 1))
					blk("UpperTorso", x - 0.055 * s, y - 0.055 * s, z - 0.07 * s, x + 0.055 * s, y + 0.055 * s, z + 0.01, c, M.Metal, "Button", DET)
				end
			end
		end
		-- Standing collar in a facing colour (uniforms).
		function K.collar(c)
			blk("UpperTorso", -0.5 * s, yN - 0.06 * s, zf - 0.05 * s, 0.5 * s, yN + 0.14 * s, zb - 0.2 * s, c, M.Fabric, "Collar")
		end
		-- Coat skirt below the waist. len = studs below the hip line (unscaled).
		-- o.tails (back only), o.closed (no front split), o.loose (extra width), o.flare, o.hem (colour)
		function K.skirt(c, len, o)
			o = o or {}
			len = len * s
			local e = (o.loose or 0.06) * s
			local x = tw2 + e
			local g = o.closed and 0 or 0.05 * s
			local y0 = yH - len
			local top = o.top or yW
			if o.tails then
				blk("LowerTorso", -tw2 + 0.05 * s, y0, zb - 0.16 * s, -g, top, zb + e, c, M.Fabric, "CoatTail")
				blk("LowerTorso", g, y0, zb - 0.16 * s, tw2 - 0.05 * s, top, zb + e, c, M.Fabric, "CoatTail")
				return
			end
			if g == 0 then
				blk("LowerTorso", -x, y0, zf - e, x, top, zb + e, c, M.Fabric, "CoatSkirt")
			else
				blk("LowerTorso", -x, y0, zf - e, -g, top, zb + e, c, M.Fabric, "CoatSkirt")
				blk("LowerTorso", g, y0, zf - e, x, top, zb + e, c, M.Fabric, "CoatSkirt")
			end
			if o.flare then
				local fl = o.flare * s
				local yf = y0 + len * 0.55
				wdg("LowerTorso", -x, y0, zf - e - fl, x, yf, zf - e, N, c, M.Fabric, "Flare")
				wdg("LowerTorso", -x, y0, zb + e, x, yf, zb + e + fl, S, c, M.Fabric, "Flare")
			end
			if o.hem then
				blk("LowerTorso", -x - 0.02, y0, zf - e - 0.02, x + 0.02, y0 + 0.14 * s, zb + e + 0.02, o.hem, M.Fabric, "Hem", DET)
			end
		end
		-- Long skirt to the ground. o.width, o.flare, o.bustle (colour), o.band (waistband colour), o.hem
		function K.dress(c, o)
			o = o or {}
			local e = (o.width or 0.22) * s
			local x, zF, zB = tw2 + e, zf - e, zb + e
			local y0 = 0.1 * s
			local fl = (o.flare or 0.45) * s
			local yF = min(yH * 0.8, yW)
			blk("LowerTorso", -x, y0, zF, x, yW + 0.02, zB, c, M.Fabric, "Skirt")
			if fl > 0 then
				wdg("LowerTorso", -x, y0, zF - fl, x, yF, zF, N, c, M.Fabric, "SkirtFlare")
				wdg("LowerTorso", -x, y0, zB, x, yF, zB + fl, S, c, M.Fabric, "SkirtFlare")
				wdg("LowerTorso", -x - fl, y0, zF, -x, yF, zB, W, c, M.Fabric, "SkirtFlare")
				wdg("LowerTorso", x, y0, zF, x + fl, yF, zB, E, c, M.Fabric, "SkirtFlare")
			end
			if o.hem then
				blk("LowerTorso", -x - 0.01, y0, zF - 0.01, x + 0.01, y0 + 0.16 * s, zB + 0.01, o.hem, M.Fabric, "Hem", DET)
			end
			if o.bustle then
				blk("LowerTorso", -x * 0.75, yW - 1.0 * s, zB, x * 0.75, yW + 0.05, zB + 0.5 * s, o.bustle, M.Fabric, "Bustle")
				wdg("LowerTorso", -x * 0.75, yW - 1.6 * s, zB, x * 0.75, yW - 1.0 * s, zB + 0.5 * s, S, o.bustle, M.Fabric, "BustleDrape", { flip = true })
			end
			blk("LowerTorso", -tw2 - 0.04 * s, yW - 0.06 * s, zf - 0.04 * s, tw2 + 0.04 * s, yW + 0.1 * s, zb + 0.04 * s, o.band or shade(c, 0.8), M.Fabric, "Waistband")
			return zF
		end
		-- Cassock / habit: narrow robe to the ankle with a column of buttons.
		function K.robe(c, o)
			o = o or {}
			local zF = K.dress(c, { width = 0.1, flare = o.flare or 0.18, band = o.band or c })
			if o.buttons then
				for i = 0, 7 do
					local y = yW - 0.25 * s - i * (yW - 0.6 * s) / 8
					blk("LowerTorso", -0.05 * s, y - 0.05 * s, zF - 0.06 * s, 0.05 * s, y + 0.05 * s, zF + 0.01, o.buttons, M.Fabric, "Button", DET)
				end
				K.buttons(o.buttons, 5, { top = yN - 0.2 * s, bottom = yW + 0.15 * s })
			end
			if o.sash then
				blk("LowerTorso", -tw2 - 0.15 * s, yW - 0.12 * s, zf - 0.15 * s, tw2 + 0.15 * s, yW + 0.12 * s, zb + 0.15 * s, o.sash, M.Fabric, "Cincture")
				blk("LowerTorso", -tw2 - 0.1 * s, yH - 1.0 * s, zf - 0.2 * s, -tw2 + 0.15 * s, yW - 0.1 * s, zf - 0.13 * s, o.sash, M.Fabric, "CinctureEnd", DET)
			end
			return zF
		end
		-- Apron. o.top, o.bottom (y), o.z (front plane), o.w (half width), o.bib, o.bibW, o.bibZ, o.tie, o.stains, o.mat
		function K.apron(c, o)
			o = o or {}
			local w = o.w or (tw2 - 0.12 * s)
			local zF = (o.z or zf) - 0.03 * s
			local yb = o.bottom or (yH - 0.9 * s)
			local mat = o.mat or M.Fabric
			local panel = blk("LowerTorso", -w, yb, zF - 0.05 * s, w, o.top or (yW + 0.06 * s), zF, c, mat, "Apron")
			if o.bib then
				local bw = o.bibW or 0.48 * s
				local bz = (o.bibZ or zf) - 0.01
				blk("UpperTorso", -bw, yW, bz - 0.07 * s, bw, yN - 0.28 * s, bz, c, mat, "ApronBib")
				for _, sd in ipairs({ -1, 1 }) do
					blk("UpperTorso", sd * bw - 0.05 * s, yN - 0.3 * s, bz - 0.06 * s, sd * bw + 0.05 * s, yN + 0.02, bz, o.tie or c, mat, "ApronStrap", DET)
				end
			end
			blk("LowerTorso", -tw2 - 0.025 * s, yW - 0.04 * s, zf - 0.035 * s, tw2 + 0.025 * s, yW + 0.06 * s, zb + 0.025 * s, o.tie or c, mat, "ApronTie", DET)
			if o.stains then
				for i, st in ipairs(o.stains) do
					blk("LowerTorso", st[1] * s - st[3] * s, yb + st[2] * s - st[3] * s, zF - 0.065 * s, st[1] * s + st[3] * s, yb + st[2] * s + st[3] * s, zF - 0.04 * s, CL.blood, M.SmoothPlastic, "Stain" .. i, DET)
				end
			end
			if o.stripes then
				for i = -2, 2 do
					blk("LowerTorso", i * w / 3 - 0.05 * s, yb + 0.02, zF - 0.06 * s, i * w / 3 + 0.05 * s, (o.top or (yW + 0.06 * s)) - 0.02, zF - 0.045 * s, o.stripes, mat, "ApronStripe", DET)
				end
			end
			return panel
		end
		function K.belt(c, buckle, o)
			o = o or {}
			local e = (o.out or 0.03) * s
			local h = (o.h or 0.18) * s
			blk("LowerTorso", -tw2 - e, yW - h, zf - e, tw2 + e, yW + 0.01, zb + e, c, M.Leather, "Belt")
			if buckle then
				blk("LowerTorso", -0.13 * s, yW - h - 0.02, zf - e - 0.04 * s, 0.13 * s, yW + 0.03, zf - e + 0.01, buckle, M.Metal, "Buckle", DET)
			end
		end
		-- Wide cloth sash with an end hanging at the left hip.
		function K.sash(c, o)
			o = o or {}
			local e = (o.out or 0.05) * s
			blk("LowerTorso", -tw2 - e, yW - 0.34 * s, zf - e, tw2 + e, yW + 0.06 * s, zb + e, c, M.Fabric, "Sash")
			blk("LowerTorso", -tw2 - e - 0.02, yH - 0.55 * s, zf - e - 0.02, -tw2 + 0.3 * s, yW - 0.3 * s, zf + 0.25 * s, c, M.Fabric, "SashEnd")
		end
		-- Belgian official's sash: black / yellow / red with gold tassels.
		function K.tricolor(o)
			o = o or {}
			local e = (o.out or 0.06) * s
			local cols = { CL.black, CL.belgianYellow, CL.belgianRed }
			for i, c in ipairs(cols) do
				local y1 = yW + 0.08 * s - (i - 1) * 0.12 * s
				blk("LowerTorso", -tw2 - e, y1 - 0.12 * s, zf - e, tw2 + e, y1, zb + e, c, M.Fabric, "Sash", DET)
			end
			for _, z in ipairs({ -0.15, 0.1 }) do
				blk("LowerTorso", -tw2 - e - 0.03, yH - 0.45 * s, zf + z * s, -tw2 - e + 0.06 * s, yW - 0.25 * s, zf + (z + 0.12) * s, CL.belgianRed, M.Fabric, "SashEnd", DET)
				ball("LowerTorso", -tw2 - e + 0.01, yH - 0.5 * s, zf + (z + 0.06) * s, 0.16 * s, CL.gold, M.Metal, "Tassel", DET)
			end
		end
		function K.braces(c)
			for _, sd in ipairs({ -1, 1 }) do
				blk("UpperTorso", sd * 0.38 * s, yW - 0.02, zf - 0.03 * s, sd * 0.5 * s, yN + 0.01, zf + 0.01, c, M.Fabric, "Brace", DET)
				blk("UpperTorso", sd * 0.38 * s, yW - 0.02, zb - 0.01, sd * 0.5 * s, yN + 0.01, zb + 0.03 * s, c, M.Fabric, "Brace", DET)
			end
		end
		local function strap(seg, ax, ay, bx, by, z, w, t, c, mat, name, o)
			local dx, dy = bx - ax, by - ay
			local len = math.sqrt(dx * dx + dy * dy)
			return rbox(seg, (ax + bx) / 2, (ay + by) / 2, z, w, len, t, 0, 0, math.atan2(-dx, dy), c, mat, name, o)
		end
		function K.crossbelts(c, o)
			o = o or {}
			for _, z in ipairs({ zf - 0.03 * s, zb + 0.03 * s }) do
				strap("UpperTorso", -tw2 + 0.12 * s, yN - 0.03 * s, tw2 - 0.18 * s, yW + 0.05 * s, z, 0.24 * s, 0.05 * s, c, M.Leather, "CrossBelt", DET)
				strap("UpperTorso", tw2 - 0.12 * s, yN - 0.03 * s, -tw2 + 0.18 * s, yW + 0.05 * s, z + (z < 0 and -0.01 or 0.01), 0.24 * s, 0.05 * s, c, M.Leather, "CrossBelt", DET)
			end
			if o.plate then
				blk("UpperTorso", -0.12 * s, yN - 0.92 * s, zf - 0.1 * s, 0.12 * s, yN - 0.68 * s, zf - 0.04 * s, o.plate, M.Metal, "BeltPlate", DET)
			end
			if o.pouch then
				blk("LowerTorso", -0.5 * s, yH - 0.25 * s, zb, 0.5 * s, yW - 0.05 * s, zb + 0.32 * s, o.pouch, M.Leather, "Pouch")
			end
		end
		-- Horizontal stripes (the Apache marinière). o.arms adds them to the sleeves.
		function K.stripes(c, n, o)
			o = o or {}
			local e = 0.015 * s
			local span = yN - 0.18 * s - yW
			for i = 1, n do
				local yc = yW + span * (i - 0.5) / n
				blk("UpperTorso", -tw2 - e, yc - 0.06 * s, zf - e, tw2 + e, yc + 0.06 * s, zb + e, c, M.Fabric, "Stripe", DET)
			end
			if o.arms then
				for _, sd in ipairs({ -1, 1 }) do
					local L = sd < 0 and "Left" or "Right"
					local ax, a = sd * A.ax, A.aw / 2 + e
					for _, f in ipairs({ 0.25, 0.7 }) do
						local y = A.yElbow + (yN - A.yElbow) * f
						blk(L .. "UpperArm", ax - a, y - 0.06 * s, -a, ax + a, y + 0.06 * s, a, c, M.Fabric, "Stripe", DET)
					end
					if not o.rolled then
						for _, f in ipairs({ 0.3, 0.75 }) do
							local y = A.yWrist + (A.yElbow - A.yWrist) * f
							blk(L .. "LowerArm", ax - a, y - 0.06 * s, -a, ax + a, y + 0.06 * s, a, c, M.Fabric, "Stripe", DET)
						end
					end
				end
			end
		end
		function K.epaulettes(c, fringe)
			for _, sd in ipairs({ -1, 1 }) do
				blk("UpperTorso", sd * (tw2 - 0.45 * s), yN - 0.02, -0.32 * s, sd * (tw2 + 0.22 * s), yN + 0.1 * s, 0.32 * s, c, M.Metal, "Epaulette")
				if fringe then
					blk("UpperTorso", sd * (tw2 + 0.04 * s), yN - 0.28 * s, -0.34 * s, sd * (tw2 + 0.28 * s), yN + 0.02, 0.34 * s, fringe, M.Fabric, "Fringe", DET)
				end
			end
		end
		function K.aiguillette(c)
			strap("UpperTorso", tw2 - 0.1 * s, yN - 0.1 * s, 0.25 * s, yN - 0.75 * s, zf - 0.05 * s, 0.07 * s, 0.05 * s, c, M.Fabric, "Aiguillette", DET)
			strap("UpperTorso", tw2 - 0.05 * s, yN - 0.15 * s, 0.35 * s, yN - 0.95 * s, zf - 0.06 * s, 0.07 * s, 0.05 * s, c, M.Fabric, "Aiguillette", DET)
			ball("UpperTorso", 0.3 * s, yN - 0.98 * s, zf - 0.08 * s, 0.12 * s, CL.gold, M.Metal, "Ferrule", DET)
		end
		-- Short cape over the shoulders and upper arms. o.layers stacks capes (coachman).
		function K.capelet(c, len, o)
			o = o or {}
			for i = 1, (o.layers or 1) do
				local l = (len - (i - 1) * 0.3) * s
				local e = (0.08 + (i - 1) * 0.04) * s
				blk("UpperTorso", -tw2 - A.aw - e, yN - l, zf - e - 0.02 * s, tw2 + A.aw + e, yN + 0.06 * s + (i - 1) * 0.02 * s, zb + e, c, M.Fabric, "Cape")
			end
		end
		function K.shawl(c, o)
			o = o or {}
			blk("UpperTorso", -tw2 - 0.06 * s, yN - 0.35 * s, zf - 0.06 * s, tw2 + 0.06 * s, yN + 0.05 * s, zb + 0.06 * s, c, M.Fabric, "Shawl")
			local d = (o.depth or 1.0) * s
			wdg("UpperTorso", -0.7 * s, yN - 0.3 * s - d, zb, 0, yN - 0.3 * s, zb + 0.07 * s, W, c, M.Fabric, "ShawlBack", { flip = true })
			wdg("UpperTorso", 0, yN - 0.3 * s - d, zb, 0.7 * s, yN - 0.3 * s, zb + 0.07 * s, E, c, M.Fabric, "ShawlBack", { flip = true })
			for _, sd in ipairs({ -1, 1 }) do
				blk("UpperTorso", sd * 0.18 * s, yW + 0.25 * s, zf - 0.07 * s, sd * 0.5 * s, yN - 0.3 * s, zf - 0.02 * s, c, M.Fabric, "ShawlEnd", DET)
			end
			if o.fringe then
				blk("UpperTorso", -0.5 * s, yW + 0.15 * s, zf - 0.065 * s, 0.5 * s, yW + 0.25 * s, zf - 0.025 * s, o.fringe, M.Fabric, "ShawlFringe", DET)
			end
		end
		-- Open jacket over a different shirt: side and back panels around the torso.
		function K.jacketOpen(c, o)
			o = o or {}
			local e = 0.035 * s
			local inner = (o.open or 0.42) * s
			local y0 = (o.bottom or yW - 0.05 * s)
			for _, sd in ipairs({ -1, 1 }) do
				blk("UpperTorso", sd * inner, y0, zf - e, sd * (tw2 + e), yN + 0.02, zb + e, c, M.Fabric, "Jacket")
			end
			blk("UpperTorso", -inner, y0, zb - 0.1 * s, inner, yN + 0.02, zb + e, c, M.Fabric, "JacketBack")
			if o.collar then
				for _, sd in ipairs({ -1, 1 }) do
					wdg("UpperTorso", sd * inner, yN - 0.7 * s, zf - e - 0.03 * s, sd * (inner + 0.22 * s), yN + 0.03, zf - e, sd < 0 and E or W, o.collar, M.Fabric, "Lapel", { flip = true, shadow = false })
				end
			end
		end
		function K.belly(c, amt)
			amt = amt * s
			blk("UpperTorso", -tw2 + 0.15 * s, yH + 0.05 * s, zf - amt, tw2 - 0.15 * s, yW + 0.8 * s, zf + 0.1, c, M.Fabric, "Belly")
			wdg("UpperTorso", -tw2 + 0.15 * s, yW + 0.8 * s, zf - amt, tw2 - 0.15 * s, yW + 1.15 * s, zf, N, c, M.Fabric, "Belly")
			return zf - amt
		end
		function K.patches(list)
			for _, p in ipairs(list) do
				blk(p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], M.Fabric, "Patch", DET)
			end
		end
		function K.mantle(c)
			blk("UpperTorso", -tw2 - 0.12 * s, yN - 0.6 * s, zf - 0.12 * s, tw2 + 0.12 * s, yN + 0.08 * s, zb + 0.12 * s, c, M.Leather, "Mantle")
		end
		function K.pauldrons(c)
			for _, sd in ipairs({ -1, 1 }) do
				local L = sd < 0 and "Left" or "Right"
				local ax, a = sd * A.ax, A.aw / 2 + 0.12 * s
				blk(L .. "UpperArm", ax - a, yN - 0.65 * s, -a, ax + a, yN + 0.15 * s, a, c, M.Metal, "Pauldron")
				for i = 0, 1 do
					blk(L .. "UpperArm", ax - a - 0.02, yN - 0.5 * s + i * 0.35 * s, -a - 0.02, ax + a + 0.02, yN - 0.44 * s + i * 0.35 * s, a + 0.02, shade(c, 0.7), M.Metal, "Rivets", DET)
				end
			end
		end
		-- Small embers glowing on the front (Fonderie).
		function K.embers(seg, list)
			for _, e in ipairs(list) do
				blk(seg, e[1] * s - 0.05 * s, e[2] - 0.05 * s, e[3] - 0.03 * s, e[1] * s + 0.05 * s, e[2] + 0.05 * s, e[3], CL.ember, M.Neon, "Ember", DET)
			end
		end

		---------------------------------------------------------------- arms
		local function armBand(segSuffix, y0, y1, e, c, mat, name)
			for _, sd in ipairs({ -1, 1 }) do
				local L = sd < 0 and "Left" or "Right"
				local ax, a = sd * A.ax, A.aw / 2 + e
				blk(L .. segSuffix, ax - a, y0, -a, ax + a, y1, a, c, mat, name, DET)
			end
		end
		function K.cuffs(c, h)
			armBand("LowerArm", A.yWrist, A.yWrist + (h or 0.2) * s, 0.03 * s, c, M.Fabric, "Cuff")
		end
		function K.rolled(c)
			armBand("LowerArm", A.yElbow - 0.2 * s, A.yElbow, 0.045 * s, c, M.Fabric, "RolledSleeve")
		end
		function K.armband(c)
			armBand("UpperArm", A.yElbow + 0.15 * s, A.yElbow + 0.28 * s, 0.03 * s, c, M.Fabric, "SleeveGarter")
		end
		function K.gauntlets(c)
			armBand("LowerArm", A.yWrist - 0.02 * s, A.yWrist + 0.45 * s, 0.09 * s, c, M.Leather, "Gauntlet")
		end

		---------------------------------------------------------------- legs and feet
		local function legBand(segSuffix, y0, y1, e, c, mat, name, o)
			for _, sd in ipairs({ -1, 1 }) do
				local L = sd < 0 and "Left" or "Right"
				local lx, l = sd * A.hx, A.lw / 2 + e
				blk(L .. segSuffix, lx - l, y0, -l, lx + l, y1, l, c, mat, name, o)
			end
		end
		local function toes(c, mat, len, h)
			for _, sd in ipairs({ -1, 1 }) do
				local L = sd < 0 and "Left" or "Right"
				local lx, l = sd * A.hx, A.lw / 2
				blk(L .. "Foot", lx - l + 0.06 * s, 0, -l - len * s, lx + l - 0.06 * s, h * s, -l + 0.01, c, mat, "Toe", DET)
			end
		end
		function K.boots(c, h)
			legBand("LowerLeg", A.yAnkle, A.yAnkle + (h or 0.6) * s, 0.035 * s, c, M.Leather, "Boot")
			toes(c, M.Leather, 0.3, 0.26)
		end
		function K.tallboots(c)
			legBand("LowerLeg", A.yAnkle, A.yKnee + 0.05 * s, 0.035 * s, c, M.Leather, "Boot")
			legBand("UpperLeg", A.yKnee + 0.05 * s, A.yKnee + 0.25 * s, 0.06 * s, c, M.Leather, "BootTop")
			toes(c, M.Leather, 0.3, 0.26)
		end
		function K.shoes(c)
			toes(c, M.Leather, 0.28, 0.22)
		end
		function K.clogs()
			local wood = C(150, 110, 70)
			toes(wood, M.Wood, 0.38, 0.32)
			legBand("Foot", 0, 0.12 * s, 0.03 * s, wood, M.Wood, "ClogSole", DET)
		end
		function K.gaiters(c)
			legBand("LowerLeg", A.yAnkle, A.yAnkle + 0.55 * s, 0.03 * s, c, M.Fabric, "Gaiter", DET)
		end
		function K.legStripe(c, w)
			w = (w or 0.08) * s
			for _, sd in ipairs({ -1, 1 }) do
				local L = sd < 0 and "Left" or "Right"
				local xo = sd * (A.hx + A.lw / 2)
				blk(L .. "UpperLeg", xo, A.yKnee, -w, xo + sd * 0.025 * s, yH, w, c, M.Fabric, "Stripe", DET)
				blk(L .. "LowerLeg", xo, A.yAnkle, -w, xo + sd * 0.025 * s, A.yKnee, w, c, M.Fabric, "Stripe", DET)
			end
		end
		function K.flares(c)
			legBand("LowerLeg", A.yAnkle - 0.05 * s, A.yAnkle + 0.45 * s, 0.12 * s, c, M.Fabric, "TrouserFlare")
		end
		function K.kneePatch(c, sd)
			local L = sd < 0 and "Left" or "Right"
			local lx, l = sd * A.hx, A.lw / 2
			blk(L .. "LowerLeg", lx - 0.25 * s, A.yKnee - 0.3 * s, -l - 0.03 * s, lx + 0.2 * s, A.yKnee + 0.05 * s, -l + 0.01, c, M.Fabric, "Patch", DET)
		end

		---------------------------------------------------------------- props held in a hand (sd = -1 left, 1 right)
		function K.cane(c, sd, knob)
			sd = sd or 1
			local hx, hy = handPos(sd)
			cylY(handSeg(sd), hx, 0.05 * s, hy + 0.12 * s, 0, 0.16 * s, c or CL.darkwood, M.Wood, "Cane", PROP)
			ball(handSeg(sd), hx, hy + 0.16 * s, 0, 0.26 * s, knob or CL.brass, M.Metal, "CaneKnob", PROPNS)
		end
		function K.parasol(c, sd)
			sd = sd or 1
			local hx, hy = handPos(sd)
			cylY(handSeg(sd), hx, 0.05 * s, 0.45 * s, 0, 0.06 * s, CL.darkwood, M.Wood, "ParasolTip", PROPNS)
			cylY(handSeg(sd), hx, 0.45 * s, hy - 0.25 * s, 0, 0.3 * s, c, M.Fabric, "ParasolCanopy", PROP)
			cylY(handSeg(sd), hx, hy - 0.25 * s, hy + 0.2 * s, 0, 0.08 * s, CL.darkwood, M.Wood, "ParasolHandle", PROPNS)
		end
		function K.rifle(sd, bayonet)
			sd = sd or 1
			local hx = sd * A.ax
			local g = handSeg(sd)
			blk(g, hx - 0.1 * s, 0.02 * s, -0.16 * s, hx + 0.1 * s, 1.25 * s, 0.24 * s, CL.wood, M.Wood, "RifleStock", PROP)
			blk(g, hx - 0.08 * s, 1.25 * s, -0.04 * s, hx + 0.08 * s, 3.05 * s, 0.14 * s, CL.wood, M.Wood, "RifleFore", PROP)
			cylY(g, hx, 1.2 * s, 3.85 * s, -0.08 * s, 0.13 * s, CL.iron, M.Metal, "RifleBarrel", PROP)
			blk(g, hx - 0.06 * s, 1.25 * s, 0.1 * s, hx + 0.06 * s, 1.55 * s, 0.28 * s, CL.iron, M.Metal, "RifleLock", PROPNS)
			blk(g, hx - 0.02 * s, 1.0 * s, 0.24 * s, hx + 0.02 * s, 3.0 * s, 0.3 * s, CL.darkleather, M.Leather, "RifleSling", PROPNS)
			if bayonet then
				blk(g, hx - 0.025 * s, 3.85 * s, -0.12 * s, hx + 0.025 * s, 4.95 * s, -0.04 * s, CL.steel, M.Metal, "Bayonet", PROPNS)
			end
		end
		-- kind = "lamplighter" or "boathook"
		function K.pole(sd, kind)
			sd = sd or 1
			local hx = sd * A.ax
			local g = handSeg(sd)
			local top = (kind == "boathook" and 6.4 or 7.2) * s
			cylY(g, hx, 0.1 * s, top, 0, 0.13 * s, CL.wood, M.Wood, "Pole", PROP)
			if kind == "boathook" then
				blk(g, hx - 0.05 * s, top, -0.05 * s, hx + 0.05 * s, top + 0.5 * s, 0.05 * s, CL.iron, M.Metal, "HookSpike", PROPNS)
				rbox(g, hx, top - 0.05 * s, -0.2 * s, 0.08 * s, 0.08 * s, 0.4 * s, -0.5, 0, 0, CL.iron, M.Metal, "HookCurve", PROPNS)
			else
				cylY(g, hx, top - 0.3 * s, top, 0, 0.2 * s, CL.brass, M.Metal, "PoleCap", PROPNS)
				rbox(g, hx, top + 0.15 * s, -0.12 * s, 0.07 * s, 0.07 * s, 0.4 * s, 0.6, 0, 0, CL.brass, M.Metal, "PoleHook", PROPNS)
				ball(g, hx, top + 0.08 * s, 0, 0.12 * s, CL.ember, M.Neon, "Wick", PROPNS)
			end
		end
		function K.basket(sd, contents, o)
			sd = sd or 1
			o = o or {}
			local hx, hy = handPos(sd)
			local g = handSeg(sd)
			local cx = hx + sd * 0.08 * s
			local top = hy - 0.62 * s
			blk(g, cx - 0.32 * s, hy - 1.22 * s, -0.5 * s, cx + 0.32 * s, top, 0.5 * s, o.c or CL.wicker, M.WoodPlanks, "Basket", PROP)
			blk(g, cx - 0.36 * s, top - 0.08 * s, -0.54 * s, cx + 0.36 * s, top, 0.54 * s, shade(o.c or CL.wicker, 0.8), M.WoodPlanks, "BasketRim", PROPNS)
			for _, z in ipairs({ -0.4, 0.4 }) do
				blk(g, cx - 0.03 * s, top, z * s - 0.03 * s, cx + 0.03 * s, hy + 0.1 * s, z * s + 0.03 * s, shade(o.c or CL.wicker, 0.8), M.WoodPlanks, "BasketHandle", PROPNS)
			end
			blk(g, cx - 0.03 * s, hy + 0.04 * s, -0.43 * s, cx + 0.03 * s, hy + 0.12 * s, 0.43 * s, shade(o.c or CL.wicker, 0.8), M.WoodPlanks, "BasketHandle", PROPNS)
			if contents then
				for i, col in ipairs(contents) do
					local z = -0.32 + (i - 1) * (0.64 / math.max(1, #contents - 1))
					ball(g, cx + ((i % 2) - 0.5) * 0.25 * s, top + 0.02 * s, z * s, 0.28 * s, col, M.SmoothPlastic, "Goods", PROPNS)
				end
			end
		end
		-- Liège botteresse's tall wicker basket carried on the back.
		function K.hotte(contents)
			local zc0, zc1 = zb + 0.06 * s, zb + 0.95 * s
			blk("UpperTorso", -0.68 * s, yW - 0.7 * s, zc0, 0.68 * s, yN + 0.85 * s, zc1, CL.wicker, M.WoodPlanks, "Hotte")
			blk("UpperTorso", -0.76 * s, yN + 0.7 * s, zc0 - 0.06 * s, 0.76 * s, yN + 0.9 * s, zc1 + 0.06 * s, shade(CL.wicker, 0.8), M.WoodPlanks, "HotteRim")
			for _, y in ipairs({ yW - 0.2 * s, yN }) do
				blk("UpperTorso", -0.7 * s, y, zc0 - 0.02, 0.7 * s, y + 0.1 * s, zc1 + 0.02, shade(CL.wicker, 0.75), M.WoodPlanks, "HotteBand", DET)
			end
			for _, sd in ipairs({ -1, 1 }) do
				blk("UpperTorso", sd * 0.36 * s, yW - 0.1 * s, zf - 0.04 * s, sd * 0.5 * s, yN + 0.02, zf + 0.01, CL.leather, M.Leather, "HotteStrap", DET)
				blk("UpperTorso", sd * 0.36 * s, yN - 0.02, zf - 0.04 * s, sd * 0.5 * s, yN + 0.06 * s, zc0, CL.leather, M.Leather, "HotteStrap", DET)
			end
			if contents then
				for i, col in ipairs(contents) do
					ball("UpperTorso", ((i % 3) - 1) * 0.35 * s, yN + 0.95 * s, zc0 + (0.25 + 0.4 * ((i + 1) % 2)) * s, 0.42 * s, col, M.SmoothPlastic, "HotteGoods", DET)
				end
			end
		end
		function K.suitcase(sd, c)
			sd = sd or 1
			local hx, hy = handPos(sd)
			local g = handSeg(sd)
			local cx = hx + sd * 0.06 * s
			blk(g, cx - 0.2 * s, hy - 1.3 * s, -0.75 * s, cx + 0.2 * s, hy - 0.22 * s, 0.75 * s, c or CL.leather, M.Leather, "Suitcase", PROP)
			blk(g, cx - 0.05 * s, hy - 0.22 * s, -0.25 * s, cx + 0.05 * s, hy + 0.08 * s, 0.25 * s, CL.darkleather, M.Leather, "SuitcaseHandle", PROPNS)
			for _, z in ipairs({ -0.4, 0.4 }) do
				blk(g, cx - 0.22 * s, hy - 1.32 * s, z * s - 0.05 * s, cx + 0.22 * s, hy - 0.2 * s, z * s + 0.05 * s, CL.darkleather, M.Leather, "SuitcaseStrap", PROPNS)
			end
		end
		function K.papers(sd)
			sd = sd or -1
			local hx, hy = handPos(sd)
			local g = handSeg(sd)
			blk(g, hx - 0.2 * s, hy - 0.78 * s, -0.45 * s, hx + 0.2 * s, hy + 0.05 * s, 0.45 * s, C(222, 214, 196), M.SmoothPlastic, "Newspapers", PROP)
			blk(g, hx - 0.22 * s, hy - 0.45 * s, -0.47 * s, hx + 0.22 * s, hy - 0.4 * s, 0.47 * s, CL.darkwood, M.Fabric, "String", PROPNS)
			blk(g, hx - 0.21 * s, hy - 0.3 * s, -0.46 * s, hx + 0.21 * s, hy - 0.08 * s, -0.25 * s, C(40, 40, 40), M.SmoothPlastic, "Headline", PROPNS)
		end
		function K.book(sd, c, big)
			sd = sd or -1
			local hx, hy = handPos(sd)
			local g = handSeg(sd)
			local h = (big and 0.95 or 0.75) * s
			blk(g, hx - 0.12 * s, hy - h, -0.36 * s, hx + 0.12 * s, hy + 0.05 * s, 0.36 * s, c or CL.black, M.Leather, "Book", PROP)
			blk(g, hx - 0.1 * s, hy - h + 0.03 * s, -0.38 * s, hx + 0.1 * s, hy + 0.02 * s, -0.34 * s, CL.cream, M.SmoothPlastic, "Pages", PROPNS)
		end
		function K.cup(sd)
			sd = sd or 1
			local hx, hy = handPos(sd)
			cylY(handSeg(sd), hx, hy - 0.1 * s, hy + 0.3 * s, -0.4 * s, 0.38 * s, CL.steel, M.Metal, "TinCup", PROP)
		end
		function K.jug(sd)
			sd = sd or 1
			local hx, hy = handPos(sd)
			local g = handSeg(sd)
			cylY(g, hx, hy - 0.95 * s, hy - 0.08 * s, -0.12 * s, 0.6 * s, C(176, 150, 120), M.SmoothPlastic, "Jug", PROP)
			blk(g, hx - 0.05 * s, hy - 0.3 * s, 0.1 * s, hx + 0.05 * s, hy + 0.08 * s, 0.24 * s, C(150, 126, 100), M.SmoothPlastic, "JugHandle", PROPNS)
			wdg(g, hx - 0.1 * s, hy - 0.2 * s, -0.55 * s, hx + 0.1 * s, hy - 0.08 * s, -0.4 * s, N, C(176, 150, 120), M.SmoothPlastic, "JugSpout", PROPNS)
		end
		function K.mug(sd)
			sd = sd or -1
			local hx, hy = handPos(sd)
			local g = handSeg(sd)
			cylY(g, hx, hy - 0.45 * s, hy + 0.05 * s, -0.35 * s, 0.4 * s, C(200, 196, 186), M.SmoothPlastic, "Mug", PROP)
			cylY(g, hx, hy + 0.05 * s, hy + 0.12 * s, -0.35 * s, 0.38 * s, C(244, 238, 220), M.SmoothPlastic, "Foam", PROPNS)
		end
		function K.shovel(sd)
			sd = sd or 1
			local hx, hy = handPos(sd)
			local g = handSeg(sd)
			cylY(g, hx, 0.9 * s, hy + 0.55 * s, 0, 0.12 * s, CL.wood, M.Wood, "ShovelShaft", PROP)
			blk(g, hx - 0.05 * s, hy + 0.55 * s, -0.18 * s, hx + 0.05 * s, hy + 0.65 * s, 0.18 * s, CL.wood, M.Wood, "ShovelGrip", PROPNS)
			blk(g, hx - 0.04 * s, 0.08 * s, -0.42 * s, hx + 0.04 * s, 0.95 * s, 0.42 * s, CL.iron, M.Metal, "ShovelBlade", PROP)
		end
		function K.hammer(sd)
			sd = sd or 1
			local hx, hy = handPos(sd)
			local g = handSeg(sd)
			cylY(g, hx, hy - 0.95 * s, hy + 0.1 * s, 0, 0.11 * s, CL.wood, M.Wood, "HammerHandle", PROPNS)
			blk(g, hx - 0.12 * s, hy - 1.12 * s, -0.34 * s, hx + 0.12 * s, hy - 0.86 * s, 0.2 * s, CL.iron, M.Metal, "HammerHead", PROPNS)
		end
		function K.tongs(sd)
			sd = sd or 1
			local hx, hy = handPos(sd)
			local g = handSeg(sd)
			for _, dz in ipairs({ -0.06, 0.06 }) do
				rod(g, V(hx, hy + 0.1 * s, dz * s), V(hx, 0.4 * s, -0.4 * s + dz * 2 * s), 0.07 * s, CL.iron, M.Metal, "Tong", PROPNS)
			end
			blk(g, hx - 0.06 * s, 0.25 * s, -0.62 * s, hx + 0.06 * s, 0.45 * s, -0.3 * s, CL.ember, M.Neon, "HotIron", PROPNS)
		end
		function K.stamp(sd)
			sd = sd or 1
			local hx, hy = handPos(sd)
			local g = handSeg(sd)
			cylY(g, hx, hy - 0.7 * s, hy + 0.1 * s, 0, 0.12 * s, CL.darkwood, M.Wood, "StampHandle", PROPNS)
			cylY(g, hx, hy - 0.95 * s, hy - 0.7 * s, 0, 0.3 * s, CL.brass, M.Metal, "Stamp", PROPNS)
		end
		function K.file(sd)
			sd = sd or 1
			local hx, hy = handPos(sd)
			local g = handSeg(sd)
			blk(g, hx - 0.05 * s, hy - 0.1 * s, -0.05 * s, hx + 0.05 * s, hy + 0.15 * s, 0.05 * s, CL.darkwood, M.Wood, "FileHandle", PROPNS)
			blk(g, hx - 0.025 * s, hy - 0.85 * s, -0.06 * s, hx + 0.025 * s, hy - 0.1 * s, 0.06 * s, CL.steel, M.Metal, "File", PROPNS)
		end
		function K.cleaver(sd)
			sd = sd or 1
			local hx, hy = handPos(sd)
			local g = handSeg(sd)
			cylY(g, hx, hy - 0.62 * s, hy + 0.15 * s, 0, 0.22 * s, CL.darkwood, M.Wood, "CleaverHandle", PROPNS)
			blk(g, hx - 0.05 * s, hy - 2.0 * s, -1.0 * s, hx + 0.05 * s, hy - 0.55 * s, 0.18 * s, CL.steel, M.Metal, "CleaverBlade", PROP)
			blk(g, hx - 0.06 * s, hy - 2.04 * s, -1.02 * s, hx + 0.06 * s, hy - 1.9 * s, 0.18 * s, C(196, 200, 206), M.Metal, "CleaverEdge", PROPNS)
			blk(g, hx - 0.06 * s, hy - 1.6 * s, -0.75 * s, hx + 0.06 * s, hy - 1.1 * s, -0.4 * s, CL.blood, M.SmoothPlastic, "CleaverStain", PROPNS)
		end
		function K.hook(sd)
			sd = sd or -1
			local hx, hy = handPos(sd)
			local g = handSeg(sd)
			for i = 0, 2 do
				blk(g, hx - 0.05 * s, hy - (0.2 + i * 0.22) * s, -0.06 * s, hx + 0.05 * s, hy - (0.04 + i * 0.22) * s, 0.06 * s, CL.iron, M.Metal, "Chain", PROPNS)
			end
			blk(g, hx - 0.06 * s, hy - 1.5 * s, -0.06 * s, hx + 0.06 * s, hy - 0.68 * s, 0.06 * s, CL.steel, M.Metal, "HookShaft", PROPNS)
			rbox(g, hx, hy - 1.6 * s, -0.17 * s, 0.11 * s, 0.11 * s, 0.4 * s, -0.35, 0, 0, CL.steel, M.Metal, "HookCurve", PROPNS)
			rbox(g, hx, hy - 1.4 * s, -0.36 * s, 0.1 * s, 0.38 * s, 0.1 * s, 0.25, 0, 0, CL.steel, M.Metal, "HookPoint", PROPNS)
		end
		function K.sledge(sd)
			sd = sd or 1
			local hx, hy = handPos(sd)
			local g = handSeg(sd)
			cylY(g, hx, 0.9 * s, hy + 0.5 * s, 0, 0.24 * s, CL.darkwood, M.Wood, "SledgeShaft", PROP)
			blk(g, hx - 0.45 * s, 0.04 * s, -0.95 * s, hx + 0.45 * s, 0.94 * s, 0.95 * s, CL.iron, M.Metal, "SledgeHead", PROP)
			for _, z in ipairs({ -0.55, 0.55 }) do
				blk(g, hx - 0.47 * s, 0.02 * s, z * s - 0.06 * s, hx + 0.47 * s, 0.96 * s, z * s + 0.06 * s, shade(CL.iron, 0.7), M.Metal, "SledgeBand", PROPNS)
			end
			local hot = blk(g, hx - 0.4 * s, 0.09 * s, -1.0 * s, hx + 0.4 * s, 0.89 * s, -0.95 * s, CL.ember, M.Neon, "SledgeHotFace", PROPNS)
			blk(g, hx - 0.4 * s, 0.09 * s, 0.95 * s, hx + 0.4 * s, 0.89 * s, 1.0 * s, CL.ember, M.Neon, "SledgeHotFace", PROPNS)
			local pl = Instance.new("PointLight")
			pl.Color = C(255, 140, 60)
			pl.Range = 12
			pl.Brightness = 1.2
			pl.Shadows = false
			pl.Parent = hot
			local f = Instance.new("Fire")
			f.Size = 2
			f.Heat = 4
			f.Color = C(255, 150, 60)
			f.SecondaryColor = C(150, 50, 20)
			f.Parent = hot
		end
		function K.ladle(sd)
			sd = sd or -1
			local hx, hy = handPos(sd)
			local g = handSeg(sd)
			rod(g, V(hx, hy + 0.15 * s, 0), V(hx, 0.75 * s, -1.05 * s), 0.14 * s, CL.iron, M.Metal, "LadleRod", PROP)
			cylY(g, hx, 0.25 * s, 0.75 * s, -1.45 * s, 1.0 * s, CL.iron, M.Metal, "LadleBowl", PROP)
			cylY(g, hx, 0.74 * s, 0.79 * s, -1.45 * s, 0.86 * s, CL.ember, M.Neon, "MoltenIron", PROPNS)
		end
		function K.knife(sd)
			sd = sd or -1
			local hx, hy = handPos(sd)
			local g = handSeg(sd)
			blk(g, hx - 0.06 * s, hy - 0.14 * s, -0.07 * s, hx + 0.06 * s, hy + 0.14 * s, 0.07 * s, CL.darkwood, M.Wood, "KnifeHandle", PROPNS)
			blk(g, hx - 0.025 * s, hy - 0.9 * s, -0.1 * s, hx + 0.025 * s, hy - 0.14 * s, 0.05 * s, CL.steel, M.Metal, "KnifeBlade", PROPNS)
		end
		function K.knuckles(sd)
			sd = sd or 1
			local hx, hy = handPos(sd)
			local a = A.aw / 2
			blk(handSeg(sd), hx - a - 0.03 * s, hy + 0.01, -a - 0.07 * s, hx + a + 0.03 * s, hy + 0.17 * s, -a + 0.03 * s, CL.brass, M.Metal, "BrassKnuckles", PROPNS)
		end
		function K.lantern(sd, light)
			sd = sd or -1
			local hx, hy = handPos(sd)
			local g = handSeg(sd)
			blk(g, hx - 0.04 * s, hy - 0.2 * s, -0.04 * s, hx + 0.04 * s, hy + 0.08 * s, 0.04 * s, CL.iron, M.Metal, "LanternHandle", PROPNS)
			blk(g, hx - 0.2 * s, hy - 0.3 * s, -0.2 * s, hx + 0.2 * s, hy - 0.2 * s, 0.2 * s, CL.iron, M.Metal, "LanternCap", PROPNS)
			local glass = blk(g, hx - 0.16 * s, hy - 0.75 * s, -0.16 * s, hx + 0.16 * s, hy - 0.3 * s, 0.16 * s, C(255, 200, 120), M.Neon, "LanternGlass", PROPNS)
			blk(g, hx - 0.2 * s, hy - 0.85 * s, -0.2 * s, hx + 0.2 * s, hy - 0.75 * s, 0.2 * s, CL.iron, M.Metal, "LanternBase", PROPNS)
			if light ~= false then
				local pl = Instance.new("PointLight")
				pl.Color = C(255, 190, 120)
				pl.Range = 10
				pl.Brightness = 0.7
				pl.Shadows = false
				pl.Parent = glass
			end
		end
		function K.whip(sd)
			sd = sd or 1
			local hx, hy = handPos(sd)
			local g = handSeg(sd)
			rod(g, V(hx, hy - 0.2 * s, 0), V(hx, hy + 2.6 * s, -0.7 * s), 0.08 * s, CL.darkwood, M.Wood, "WhipHandle", PROPNS)
			rod(g, V(hx, hy + 2.6 * s, -0.7 * s), V(hx + sd * 0.4 * s, hy + 1.4 * s, -1.6 * s), 0.035 * s, CL.darkleather, M.Leather, "WhipLash", PROPNS)
		end
		function K.laundry(sd)
			sd = sd or 1
			K.basket(sd, nil, { c = C(186, 160, 110) })
			local hx, hy = handPos(sd)
			blk(handSeg(sd), hx - 0.18 * s + sd * 0.08 * s, hy - 0.7 * s, -0.42 * s, hx + 0.26 * s + sd * 0.08 * s, hy - 0.45 * s, 0.42 * s, CL.white, M.Fabric, "Linen", PROPNS)
		end

		---------------------------------------------------------------- worn props
		function K.sabre(o)
			o = o or {}
			local x = -tw2 - 0.14 * s
			local top = V(x, yW - 0.15 * s, -0.35 * s)
			rod("LowerTorso", top, V(x - 0.15 * s, 0.45 * s, 0.85 * s), 0.14 * s, o.scabbard or CL.black, M.Leather, "Scabbard")
			rod("LowerTorso", top, V(x + 0.06 * s, yW + 0.28 * s, -0.62 * s), 0.1 * s, o.hilt or CL.brass, M.Metal, "SabreGrip", DET)
			blk("LowerTorso", x - 0.08 * s, yW - 0.2 * s, -0.5 * s, x + 0.12 * s, yW - 0.05 * s, -0.25 * s, o.hilt or CL.brass, M.Metal, "SabreGuard", DET)
		end
		function K.whistle(c)
			c = c or CL.steel
			strap("UpperTorso", -0.62 * s, yN - 0.12 * s, -0.18 * s, yW + 0.55 * s, zf - 0.05 * s, 0.03 * s, 0.03 * s, c, M.Metal, "WhistleChain", DET)
			cylX("UpperTorso", -0.24 * s, -0.08 * s, yW + 0.55 * s, zf - 0.07 * s, 0.07 * s, c, M.Metal, "Whistle", DET)
		end
		function K.watchChain(c)
			c = c or CL.gold
			local z = zf - 0.06 * s
			rod("UpperTorso", V(-0.38 * s, yW + 0.42 * s, z), V(0, yW + 0.24 * s, z), 0.035 * s, c, M.Metal, "WatchChain", DET)
			rod("UpperTorso", V(0, yW + 0.24 * s, z), V(0.38 * s, yW + 0.42 * s, z), 0.035 * s, c, M.Metal, "WatchChain", DET)
			ball("UpperTorso", 0, yW + 0.2 * s, z - 0.02 * s, 0.1 * s, c, M.Metal, "Fob", DET)
		end
		function K.cross(c, o)
			o = o or {}
			c = c or CL.gold
			local z = (o.z or zf) - 0.06 * s
			local y = o.y or (yW + 0.45 * s)
			blk("UpperTorso", -0.04 * s, y - 0.22 * s, z - 0.03 * s, 0.04 * s, y + 0.18 * s, z, c, M.Metal, "Cross", DET)
			blk("UpperTorso", -0.13 * s, y + 0.02 * s, z - 0.03 * s, 0.13 * s, y + 0.09 * s, z, c, M.Metal, "Cross", DET)
			for _, sd in ipairs({ -1, 1 }) do
				rod("UpperTorso", V(sd * 0.3 * s, yN, z + 0.02), V(0, y + 0.18 * s, z - 0.01), 0.025 * s, c, M.Metal, "CrossChain", DET)
			end
		end
		function K.rosary(z)
			z = (z or zf) - 0.03 * s
			blk("LowerTorso", 0.35 * s, yH - 1.0 * s, z - 0.03 * s, 0.39 * s, yW - 0.05 * s, z, CL.darkwood, M.Wood, "Rosary", DET)
			blk("LowerTorso", 0.33 * s, yH - 1.25 * s, z - 0.03 * s, 0.41 * s, yH - 0.95 * s, z, CL.steel, M.Metal, "RosaryCross", DET)
		end
		function K.keys()
			local x = tw2 - 0.15 * s
			ball("LowerTorso", x, yW - 0.25 * s, zf - 0.32 * s, 0.18 * s, CL.iron, M.Metal, "KeyRing", DET)
			for i = 0, 2 do
				blk("LowerTorso", x - 0.12 * s + i * 0.1 * s, yW - 0.75 * s, zf - 0.34 * s, x - 0.08 * s + i * 0.1 * s, yW - 0.3 * s, zf - 0.3 * s, CL.iron, M.Metal, "Key", DET)
			end
		end

		return K
	end

	---------------------------------------------------------------- roster
	-- Each definition: id, name (DisplayName), title, category (Boss | Named | Hostile | Ambient), district,
	-- where (intended spots on the map), behaviour (suggestion), health, speed, variants, body, lines, outfit(K).
	local ROSTER = {}
	local function def(d)
		ROSTER[#ROSTER + 1] = d
	end

	local function townsman(K, o)
		K.hair(o.hair or "short", o.hairC)
		K.face(o.face)
		K.beard(o.beard, o.hairC)
	end

	------------------------------------------------ West bank (old town)
	def({
		id = "MarketVendor", name = "Marchand", title = "Market vendor", category = "Ambient", district = "WestBank",
		where = "Behind the stalls on Place du Marché and along Quai de la Batte.", behaviour = "Idle", health = 100, speed = 8, variants = 2,
		lines = { "Pommes, poires, belles carottes!", "Fresh from Herstal this morning, m'sieur.", "Two sous, not a centime less." },
		outfit = function(K)
			local A, s = K.A, K.s
			local sk = K.pick(SKIN)
			local shirt = K.vary({ CL.linen, CL.cream })
			K.paint({ skin = sk, torso = K.vary({ CL.brown, CL.olive }), arms = shirt, forearms = sk, legs = K.vary({ CL.grey, CL.tan }), feet = CL.darkleather })
			townsman(K, { hairC = K.pick(HAIRS), beard = K.vary({ "walrus", "mustache" }) })
			K.flatcap(K.vary({ CL.charcoal, CL.brown }))
			K.vneck(shirt, 0.6, 0.35)
			K.shirtFront(shirt, CL.red, "neckerchief")
			K.buttons(CL.brass, 3, { top = A.yNeck - 0.7 * s, bottom = A.yWaist + 0.15 * s })
			K.rolled(shirt)
			K.apron(CL.canvas, { bottom = A.yHip - 1.0 * s })
			K.clogs()
			K.basket(1, { PRODUCE[1], PRODUCE[2], PRODUCE[3], PRODUCE[4] })
		end,
	})
	def({
		id = "Botteresse", name = "Botteresse", title = "Basket porter", category = "Ambient", district = "WestBank",
		where = "Quai de la Batte, En Hors-Château, the stairs up to the Citadel.", behaviour = "Wander", health = 100, speed = 7, variants = 2,
		body = { width = 0.9, depth = 0.95, limb = 0.85 },
		lines = { "Hoppe! Make way for the hotte!", "Forty kilos of coal up the Bueren steps, and they pay me in sous.", "Bondjoû, fi." },
		outfit = function(K)
			local A, s = K.A, K.s
			local sk = K.pick(SKIN)
			local body = K.vary({ CL.slate, CL.plum })
			local skirt = K.vary({ CL.charcoal, CL.brown })
			K.paint({ skin = sk, torso = body, arms = body, legs = CL.charcoal, feet = CL.darkleather })
			K.hair("bun", K.pick(HAIRS))
			K.face({ fem = true })
			K.scarf(K.vary({ CL.cream, C(150, 60, 50) }), { knot = "back" })
			K.dress(skirt, { flare = 0.4 })
			K.apron(K.vary({ C(70, 90, 130), CL.canvas }), { z = A.td * -0.5 - 0.22 * s, bottom = A.yHip * 0.72, w = A.tw / 2 })
			K.shawl(K.vary({ C(110, 70, 50), CL.bottle }))
			K.hotte(K.vary({ { CL.soot, CL.soot, CL.soot }, { PRODUCE[3], PRODUCE[5], PRODUCE[2] } }))
			K.clogs()
		end,
	})
	def({
		id = "MarketWoman", name = "Marchande", title = "Flower and fruit seller", category = "Ambient", district = "WestBank",
		where = "Place du Marché stalls, Place Saint-Lambert by the fountain.", behaviour = "Idle", health = 100, speed = 7, variants = 2,
		body = { width = 0.9, depth = 0.95, limb = 0.85 },
		lines = { "Violettes de Liège, deux sous le bouquet!", "For your lady, m'sieur?", "The Batte market? Sunday, like always." },
		outfit = function(K)
			local A, s = K.A, K.s
			local sk = K.pick(SKIN)
			local bodice = K.vary({ CL.burgundy, CL.navy })
			K.paint({ skin = sk, torso = bodice, arms = bodice, legs = CL.charcoal, feet = CL.darkleather })
			K.hair("bun", K.pick(HAIRS))
			K.face({ fem = true, blush = true })
			K.mobcap(CL.white)
			K.dress(K.vary({ CL.grey, CL.brown }), { flare = 0.45 })
			K.apron(CL.white, { z = A.td * -0.5 - 0.22 * s, bottom = A.yHip * 0.72, w = A.tw / 2 - 0.05 * s, bib = true, bibW = 0.4 * s })
			K.cuffs(CL.white, 0.15)
			K.shoes(CL.darkleather)
			K.basket(-1, K.vary({ FLOWERS, PRODUCE }))
		end,
	})
	def({
		id = "Gentleman", name = "Bourgeois", title = "Gentleman", category = "Ambient", district = "WestBank",
		where = "Place Saint-Lambert, Passage Lemonnier, Rue Léopold, Place du Marché.", behaviour = "Wander", health = 100, speed = 8, variants = 3,
		lines = { "Good day. Mind the horse droppings.", "The Bourse closed up again, they say. Cockerill shares, of course.", "Have you seen the new Passage? Gaslight indoors, imagine." },
		outfit = function(K)
			local A, s = K.A, K.s
			local coat = K.vary({ CL.black, CL.brown, CL.navy })
			local waist = K.vary({ CL.burgundy, CL.cream, CL.mustard })
			local hairC = K.vary({ HAIR.grey, HAIR.dark, HAIR.chestnut })
			K.paint({ skin = K.pick(SKIN), torso = coat, legs = K.vary({ CL.grey, C(120, 110, 96), CL.charcoal }), feet = CL.black })
			townsman(K, { hairC = hairC, beard = K.vary({ "friendly", "imperial", "muttonchops" }) })
			if K.variant == 2 then K.bowler(CL.charcoal) else K.tophat(K.vary({ CL.black, C(70, 54, 42), CL.black })) end
			K.vneck(waist, 1.0, 0.44)
			K.shirtFront(CL.white, K.vary({ CL.black, CL.navy, CL.burgundy }), "cravat")
			K.buttons(CL.brass, 3, { top = A.yNeck - 0.6 * s, bottom = A.yNeck - 0.95 * s })
			K.watchChain()
			K.skirt(coat, K.variant == 2 and 0.55 or 1.0)
			K.cuffs(CL.white, 0.12)
			K.shoes(CL.black)
			K.cane()
		end,
	})
	def({
		id = "Lady", name = "Bourgeoise", title = "Lady", category = "Ambient", district = "WestBank",
		where = "Passage Lemonnier, Place Saint-Lambert, outside the Théâtre Royal.", behaviour = "Wander", health = 100, speed = 7, variants = 3,
		body = { width = 0.88, depth = 0.95, limb = 0.82 },
		lines = { "Such dreadful smoke from Seraing today.", "We are going to the Théâtre tonight. Grétry, naturally.", "Do not touch the gloves, they are from Brussels." },
		outfit = function(K)
			local A, s = K.A, K.s
			local main = K.vary({ CL.plum, CL.bottle, C(120, 60, 64) })
			local skirt = K.vary({ CL.lilac, C(74, 96, 80), CL.rose })
			K.paint({ skin = K.pick(SKIN), torso = main, arms = main, hands = CL.cream, legs = CL.charcoal, feet = CL.black })
			K.hair("bun", K.vary({ HAIR.chestnut, HAIR.blond, HAIR.black }))
			K.face({ fem = true, blush = true })
			K.bonnet(K.vary({ CL.cream, CL.black, C(200, 180, 150) }), { ribbon = main, flower = K.vary({ FLOWERS[1], FLOWERS[3], FLOWERS[4] }) })
			K.dress(skirt, { flare = 0.5, bustle = main, hem = main })
			K.buttons(CL.gold, 5, { top = A.yNeck - 0.25 * s, bottom = A.yWaist + 0.1 * s })
			K.cuffs(CL.white, 0.1)
			K.shoes(CL.black)
			K.parasol(K.vary({ CL.cream, CL.black, C(220, 200, 210) }), 1)
		end,
	})
	def({
		id = "Student", name = "Étudiant", title = "University student", category = "Ambient", district = "WestBank",
		where = "Place Saint-Lambert, Passage Lemonnier, Place Cathédrale.", behaviour = "Wander", health = 100, speed = 9, variants = 2,
		lines = { "Professor Gloesener's lecture again. Electricity, he says, will run the world.", "Do you have twenty centimes for a pint?", "Vive l'Université!" },
		outfit = function(K)
			local A, s = K.A, K.s
			local coat = K.vary({ CL.charcoal, CL.bottle })
			K.paint({ skin = K.pick(SKIN), torso = coat, legs = K.vary({ CL.tan, CL.grey }), feet = CL.black })
			townsman(K, { hairC = K.pick(HAIRS), beard = K.vary({ "none", "goatee" }) })
			K.calotte(K.vary({ CL.burgundy, CL.navy }))
			K.vneck(CL.cream, 0.8, 0.4)
			K.shirtFront(CL.white, CL.black, "bow")
			K.skirt(coat, 0.45)
			K.shoes(CL.black)
			K.book(-1, K.vary({ CL.burgundy, CL.brown }), true)
			K.spectacles(nil)
		end,
	})
	def({
		id = "Newsboy", name = "Crieur de journaux", title = "Newsboy", category = "Ambient", district = "WestBank",
		where = "Place Saint-Lambert, Rue Léopold, the Pont des Arches.", behaviour = "Wander", health = 60, speed = 11, variants = 2,
		body = { scale = 0.72, head = 1.22, width = 0.95, limb = 0.92 },
		lines = { "La Meuse! La Meuse! Read all about it!", "Another strike at Seraing, m'sieur, one sou!", "Gazette de Liège, hot off the press!" },
		outfit = function(K)
			local A, s = K.A, K.s
			local jacket = K.vary({ CL.brown, CL.slate })
			K.paint({ skin = K.pick(SKIN), torso = jacket, legs = K.vary({ CL.grey, CL.tan }), shins = C(70, 70, 70), feet = CL.darkleather })
			townsman(K, { hair = "messy", hairC = K.pick(HAIRS) })
			K.flatcap(K.vary({ CL.charcoal, CL.tan }), { big = true, tilt = 0.15 })
			K.vneck(CL.linen, 0.6, 0.35)
			K.shirtFront(CL.linen, CL.red, "neckerchief")
			K.boots(CL.darkleather, 0.4)
			K.papers(-1)
		end,
	})
	def({
		id = "Urchin", name = "Gamin", title = "Street urchin", category = "Ambient", district = "WestBank",
		where = "Back yards behind Hors-Château, the impasses, the goods yard.", behaviour = "Wander", health = 60, speed = 12, variants = 2,
		body = { scale = 0.7, head = 1.24, width = 0.95, limb = 0.9 },
		lines = { "Got a sou?", "I didn't take nothing!", "The Apaches pay ten centimes to watch the corner." },
		outfit = function(K)
			local A, s = K.A, K.s
			local sk = K.pick(SKIN)
			local shirt = K.vary({ CL.linen, C(150, 140, 120) })
			local trousers = K.vary({ CL.brown, CL.grey })
			K.paint({ skin = sk, torso = shirt, arms = shirt, forearms = sk, legs = trousers, shins = sk, feet = sk })
			townsman(K, { hair = "messy", hairC = K.pick(HAIRS), face = { soot = true } })
			K.braces(CL.darkleather)
			K.rolled(shirt)
			K.patches({
				{ "UpperTorso", 0.2 * s, A.yWaist + 0.3 * s, -A.td / 2 - 0.02 * s, 0.6 * s, A.yWaist + 0.7 * s, -A.td / 2 + 0.01, C(120, 90, 70) },
			})
			K.kneePatch(C(140, 120, 90), -1)
		end,
	})
	def({
		id = "Lamplighter", name = "Allumeur de réverbères", title = "Lamplighter", category = "Ambient", district = "WestBank",
		where = "Any street with gas lamps at dusk (Féronstrée, Quai de la Batte, Rue Léopold).", behaviour = "Patrol", health = 100, speed = 8, variants = 1,
		lines = { "Dusk already. Forty lamps to go.", "Mind the pole, mademoiselle.", "The gasworks says the price is going up again." },
		outfit = function(K)
			local A, s = K.A, K.s
			local jacket = C(52, 62, 84)
			K.paint({ skin = K.pick(SKIN), torso = jacket, legs = CL.charcoal, feet = CL.black })
			townsman(K, { hairC = HAIR.grey, beard = "walrus" })
			K.kepi(jacket, { badge = CL.brass })
			K.buttons(CL.brass, 5, { top = A.yNeck - 0.25 * s })
			K.belt(CL.darkleather, CL.brass)
			K.skirt(jacket, 0.35, { closed = true })
			K.boots(CL.black, 0.55)
			K.pole(1, "lamplighter")
			K.lantern(-1)
		end,
	})
	def({
		id = "Beggar", name = "Mendiant", title = "Beggar", category = "Ambient", district = "WestBank",
		where = "Cathedral steps, church doors, the Pont des Arches.", behaviour = "Idle", health = 80, speed = 6, variants = 2,
		lines = { "Pour l'amour de Dieu...", "I was a puddler at Ougrée. Twenty years. Now look.", "A centime, only a centime." },
		outfit = function(K)
			local A, s = K.A, K.s
			local coat = K.vary({ C(92, 80, 64), C(70, 72, 66) })
			K.paint({ skin = K.pick(SKIN), torso = coat, legs = C(84, 78, 70), feet = C(70, 60, 50) })
			townsman(K, { hairC = HAIR.grey, beard = K.vary({ "full", "stubble" }) })
			K.tophat(C(60, 56, 50), { h = 0.8, dent = true, tilt = -0.12 })
			K.skirt(coat, 0.95, { loose = 0.1 })
			K.patches({
				{ "UpperTorso", -0.7 * s, A.yWaist + 0.3 * s, -A.td / 2 - 0.02 * s, -0.25 * s, A.yWaist + 0.75 * s, -A.td / 2 + 0.01, C(120, 100, 76) },
				{ "LowerTorso", 0.4 * s, A.yHip - 0.7 * s, -A.td / 2 - 0.09 * s, 0.85 * s, A.yHip - 0.3 * s, -A.td / 2 - 0.05 * s, C(70, 60, 50) },
			})
			K.sash(C(110, 50, 40))
			K.cup(1)
		end,
	})
	def({
		id = "Nun", name = "Sœur ursuline", title = "Ursuline sister", category = "Ambient", district = "WestBank",
		where = "Impasse des Ursulines, Cathédrale Saint-Paul.", behaviour = "Wander", health = 100, speed = 7, variants = 1,
		body = { width = 0.88, depth = 0.95, limb = 0.82 },
		lines = { "God keep you, my child.", "The orphans need bread more than prayers today.", "Walk softly, this is a holy street." },
		outfit = function(K)
			local A, s = K.A, K.s
			K.paint({ skin = K.pick(SKIN), torso = CL.black, legs = CL.black, feet = CL.black })
			K.hair("none", HAIR.dark)
			K.face({ fem = true, noEars = true })
			K.veil(CL.black, CL.white)
			K.robe(CL.black, { sash = CL.black })
			K.rosary(A.td * -0.5 - 0.1 * s)
			K.book(1, CL.black)
		end,
	})
	def({
		id = "Coachman", name = "Cocher", title = "Omnibus coachman", category = "Ambient", district = "WestBank",
		where = "Beside the omnibus on Place Saint-Lambert, Place de la Gare.", behaviour = "Idle", health = 100, speed = 8, variants = 1,
		lines = { "Omnibus to Guillemins, leaving when it leaves.", "Thirty centimes. The horses don't eat promises.", "Hue!" },
		outfit = function(K)
			local A, s = K.A, K.s
			local coat = C(74, 64, 52)
			K.paint({ skin = C(214, 160, 130), torso = coat, legs = CL.tan, feet = CL.black })
			townsman(K, { hairC = HAIR.white, beard = "friendly" })
			K.tophat(CL.black, { h = 0.7, cockade = true })
			K.buttons(CL.brass, 4, { double = true, top = A.yNeck - 0.9 * s })
			K.capelet(coat, 0.95, { layers = 2 })
			K.skirt(coat, 1.25, { closed = true, loose = 0.1 })
			K.tallboots(CL.black)
			K.whip(1)
		end,
	})

	------------------------------------------------ East bank (Outremeuse, Longdoz)
	def({
		id = "GunsmithJourneyman", name = "Ouvrier armurier", title = "Gunsmith journeyman", category = "Ambient", district = "EastBank",
		where = "Atelier Dolne, the yard workshops off Puits-en-Sock, the Banc d'Épreuves.", behaviour = "Work", health = 100, speed = 8, variants = 2,
		lines = { "Another forty frames for Dolne by Saturday.", "Each piece is proofed at the Banc before it leaves. Every one.", "Liège barrels shoot straight, m'sieur. Ask any Apache." },
		outfit = function(K)
			local A, s = K.A, K.s
			local sk = K.pick(SKIN)
			local shirt = K.vary({ CL.linen, C(170, 180, 196) })
			K.paint({ skin = sk, torso = K.vary({ CL.charcoal, CL.brown }), arms = shirt, forearms = sk, legs = CL.grey, feet = CL.darkleather })
			townsman(K, { hairC = K.pick(HAIRS), beard = K.vary({ "mustache", "stubble" }) })
			K.flatcap(K.vary({ CL.navy, CL.charcoal }))
			K.vneck(shirt, 0.6, 0.35)
			K.shirtFront(shirt, CL.black, "neckerchief")
			K.rolled(shirt)
			K.apron(CL.leather, { bib = true, bottom = A.yHip - 1.1 * s, mat = M.Leather, tie = CL.darkleather })
			K.boots(CL.darkleather, 0.4)
			K.hammer(1)
		end,
	})
	def({
		id = "FoundryWorker", name = "Fondeur", title = "Foundry worker", category = "Ambient", district = "EastBank",
		where = "Fonderie Royale de Canons, at the furnaces and the casting pits.", behaviour = "Work", health = 120, speed = 8, variants = 2,
		body = { limb = 1.08, width = 1.05 },
		lines = { "Stand back from the pit!", "Twelve hours at the furnace. My eyebrows went last year.", "The Maître wants another casting tonight. He always wants another." },
		outfit = function(K)
			local A, s = K.A, K.s
			local sk = shade(K.pick(SKIN), 0.85)
			K.paint({ skin = sk, torso = C(70, 66, 62), arms = sk, legs = C(60, 56, 52), feet = CL.darkleather })
			townsman(K, { hair = "cropped", hairC = K.pick(HAIRS), beard = K.vary({ "stubble", "walrus" }), face = { soot = true } })
			K.flatcap(C(54, 50, 48))
			K.apron(CL.darkleather, { bib = true, bibW = 0.6 * s, bottom = A.yHip - 1.4 * s, mat = M.Leather })
			K.gauntlets(CL.leather)
			K.boots(CL.black, 0.7)
			K.tongs(1)
			K.embers("LowerTorso", { { -0.4, A.yHip - 0.5 * s, -A.td / 2 - 0.08 * s }, { 0.3, A.yHip - 0.9 * s, -A.td / 2 - 0.08 * s } })
		end,
	})
	def({
		id = "CoalHeaver", name = "Porteur de charbon", title = "Coal heaver", category = "Ambient", district = "EastBank",
		where = "The coal yard, the goods yard heap, the barges.", behaviour = "Work", health = 120, speed = 8, variants = 2,
		lines = { "Charbonnages de Longdoz, best coal in the Meuse valley.", "Black from my hat to my soul, me.", "Out of the way, the barge leaves at six." },
		outfit = function(K)
			local A, s = K.A, K.s
			local sk = shade(K.pick(SKIN), 0.75)
			local smock = shade(CL.smock, 0.55)
			K.paint({ skin = sk, torso = smock, arms = smock, legs = C(48, 46, 46), feet = CL.black })
			townsman(K, { hairC = HAIR.black, beard = K.vary({ "stubble", "mustache" }), face = { soot = true } })
			K.flatcap(CL.soot, { big = true })
			K.shirtFront(smock, C(40, 40, 40), "neckerchief")
			K.skirt(smock, 0.55, { closed = true, loose = 0.1, flare = 0.2 })
			K.clogs()
			K.shovel(1)
		end,
	})
	def({
		id = "Hiercheuse", name = "Hiercheuse", title = "Coal-cart pusher", category = "Ambient", district = "EastBank",
		where = "Coal yard, Longdoz goods yard, the east-bank yards.", behaviour = "Work", health = 110, speed = 8, variants = 2,
		body = { width = 0.9, depth = 0.95, limb = 0.88 },
		lines = { "Down the pit at twelve. Twenty now. Still pushing.", "Trousers? Try pushing a tram of coal in a skirt.", "The lamp stays lit or we don't come up." },
		outfit = function(K)
			local A, s = K.A, K.s
			local sk = shade(K.pick(SKIN), 0.85)
			local jacket = K.vary({ C(70, 78, 96), C(86, 74, 60) })
			K.paint({ skin = sk, torso = jacket, legs = C(56, 56, 60), feet = CL.black })
			K.hair("bun", K.pick(HAIRS))
			K.face({ fem = true, soot = true })
			K.scarf(K.vary({ C(180, 60, 50), C(200, 190, 160) }), { knot = "back", dots = CL.white })
			K.belt(CL.darkleather, CL.iron)
			K.skirt(jacket, 0.3, { closed = true })
			K.clogs()
			K.lantern(-1)
		end,
	})
	def({
		id = "RailwayPorter", name = "Porteur de gare", title = "Railway porter", category = "Ambient", district = "EastBank",
		where = "Gare de Longdoz platform and Place de la Gare.", behaviour = "Wander", health = 100, speed = 9, variants = 2,
		lines = { "Train for Namur on platform one!", "Your trunk, madame? Ten centimes.", "The 6:40 from Maastricht is late. It is always late." },
		outfit = function(K)
			local A, s = K.A, K.s
			local blue = C(46, 58, 92)
			K.paint({ skin = K.pick(SKIN), torso = blue, legs = blue, feet = CL.black })
			townsman(K, { hairC = K.pick(HAIRS), beard = K.vary({ "mustache", "muttonchops" }) })
			K.kepi(blue, { band = CL.belgianRed, badge = CL.brass })
			K.buttons(CL.brass, 5, { top = A.yNeck - 0.2 * s })
			K.collar(CL.belgianRed)
			K.belt(CL.black, CL.brass)
			K.skirt(blue, 0.3, { closed = true })
			K.shoes(CL.black)
			K.suitcase(1, K.vary({ CL.leather, C(120, 90, 60) }))
		end,
	})
	def({
		id = "Laundress", name = "Lavandière", title = "Laundress", category = "Ambient", district = "EastBank",
		where = "Under the washing lines in the Outremeuse yard lane, by the river stairs.", behaviour = "Work", health = 100, speed = 7, variants = 2,
		body = { width = 0.9, depth = 0.95, limb = 0.85 },
		lines = { "Soap costs more than bread this winter.", "Don't touch the sheets, they're for the Hôtel de Ville.", "The Meuse is brown again. Lovely for whites." },
		outfit = function(K)
			local A, s = K.A, K.s
			local sk = K.pick(SKIN)
			local bodice = K.vary({ C(120, 110, 140), C(110, 120, 100) })
			K.paint({ skin = sk, torso = bodice, arms = bodice, forearms = sk, legs = CL.charcoal, feet = CL.darkleather })
			K.hair("bun", K.pick(HAIRS))
			K.face({ fem = true, blush = true })
			K.scarf(CL.white, { knot = "back" })
			K.rolled(CL.white)
			K.dress(K.vary({ CL.slate, CL.brown }), { flare = 0.4 })
			K.apron(CL.white, { z = A.td * -0.5 - 0.22 * s, bottom = A.yHip * 0.72, w = A.tw / 2 })
			K.clogs()
			K.laundry(1)
		end,
	})

	------------------------------------------------ River
	def({
		id = "Bargeman", name = "Batelier", title = "Bargeman", category = "Ambient", district = "River",
		where = "On the quays beside the barges (Quai de la Batte, Quai de Longdoz).", behaviour = "Idle", health = 110, speed = 8, variants = 2,
		lines = { "Down to Maastricht and back by Friday, if the locks behave.", "Coal down, Dutch cheese up. That's the Meuse.", "Watch your step on the plank, landlubber." },
		outfit = function(K)
			local A, s = K.A, K.s
			local smock = K.vary({ CL.smock, C(60, 80, 110) })
			K.paint({ skin = shade(K.pick(SKIN), 0.92), torso = smock, arms = smock, legs = CL.charcoal, feet = CL.black })
			townsman(K, { hairC = K.pick(HAIRS), beard = K.vary({ "full", "walrus" }) })
			K.kepi(CL.navy, { h = 0.25 })
			K.shirtFront(smock, CL.red, "neckerchief")
			K.skirt(smock, 0.5, { closed = true, flare = 0.15 })
			K.tallboots(CL.black)
			K.pole(1, "boathook")
			K.pipe()
		end,
	})

	------------------------------------------------ Citadel, police, gendarmerie
	def({
		id = "Soldier", name = "Soldat", title = "Line infantryman", category = "Ambient", district = "CitadelAndPolice",
		where = "Citadel gate, rampart wall-walk, parade ground, Porte Sainte-Marguerite, the water gate.", behaviour = "Guard", health = 120, speed = 9, variants = 2,
		lines = { "Halt! Who goes there?", "Nothing to see. Move along.", "The Commandant forbids civilians on the ramparts." },
		outfit = function(K)
			local A, s = K.A, K.s
			local tunic = C(38, 44, 74)
			K.paint({ skin = K.pick(SKIN), torso = tunic, legs = CL.greyblue, feet = CL.black })
			townsman(K, { hair = "cropped", hairC = K.pick(HAIRS), beard = K.vary({ "mustache", "imperial" }) })
			K.shako(CL.black, { plume = K.vary({ CL.red, CL.white }) })
			K.collar(CL.belgianRed)
			K.buttons(CL.brass, 6, { top = A.yNeck - 0.2 * s })
			K.crossbelts(CL.white, { plate = CL.brass, pouch = CL.black })
			K.belt(CL.white, CL.brass, { h = 0.2 })
			K.skirt(tunic, 0.35, { closed = true })
			K.gaiters(CL.white)
			K.shoes(CL.black)
			K.rifle(1, true)
		end,
	})
	def({
		id = "Officer", name = "Officier", title = "Garrison officer", category = "Ambient", district = "CitadelAndPolice",
		where = "Citadel parade ground, by the flagpole and the barracks.", behaviour = "Idle", health = 150, speed = 9, variants = 1,
		lines = { "You there! Papers.", "The Citadelle has held since 1650. It will hold against your sort.", "Sergeant, double the gate tonight." },
		outfit = function(K)
			local A, s = K.A, K.s
			local tunic = C(30, 36, 62)
			K.paint({ skin = K.pick(SKIN), torso = tunic, legs = CL.charcoal, hands = CL.white, feet = CL.black })
			townsman(K, { hairC = HAIR.dark, beard = "imperial" })
			K.kepi(tunic, { braid = CL.gold, strap = CL.gold, badge = CL.gold, h = 0.38 })
			K.collar(CL.belgianRed)
			K.buttons(CL.gold, 6, { top = A.yNeck - 0.2 * s })
			K.epaulettes(CL.gold, CL.gold)
			K.sash(CL.belgianRed, { out = 0.04 })
			K.skirt(tunic, 0.6)
			K.legStripe(CL.belgianRed)
			K.tallboots(CL.black)
			K.sabre({ scabbard = CL.steel, hilt = CL.gold })
		end,
	})
	def({
		id = "PoliceAgent", name = "Agent de police", title = "City policeman", category = "Ambient", district = "CitadelAndPolice",
		where = "Patrols along Féronstrée and Hors-Château, Puits-en-Sock, both bridgeheads.", behaviour = "Patrol", health = 130, speed = 10, variants = 2,
		lines = { "Move along, nothing to see here.", "I have my eye on you, mon gars.", "Apaches in Outremeuse again. Keep to the lit streets." },
		outfit = function(K)
			local A, s = K.A, K.s
			local coat = C(30, 34, 52)
			K.paint({ skin = K.pick(SKIN), torso = coat, legs = coat, hands = CL.white, feet = CL.black })
			townsman(K, { hairC = K.pick(HAIRS), beard = K.vary({ "walrus", "friendly" }) })
			K.kepi(coat, { badge = CL.steel, strap = CL.steel })
			K.buttons(CL.steel, 6, { top = A.yNeck - 0.2 * s })
			if K.variant == 2 then K.capelet(coat, 0.9) end
			K.belt(CL.black, CL.steel)
			K.skirt(coat, 0.9, { closed = true })
			K.whistle()
			K.sabre({ scabbard = CL.black, hilt = CL.steel })
			K.shoes(CL.black)
		end,
	})
	def({
		id = "Gendarme", name = "Gendarme", title = "Gendarme", category = "Ambient", district = "CitadelAndPolice",
		where = "Gate of the Palais des Princes-Évêques (law courts), Place Saint-Lambert.", behaviour = "Guard", health = 150, speed = 10, variants = 1,
		lines = { "The Palais is closed to the public after five.", "Justice is slow, but she has long arms.", "Keep your hands where I can see them." },
		outfit = function(K)
			local A, s = K.A, K.s
			local coat = C(28, 34, 60)
			K.paint({ skin = K.pick(SKIN), torso = coat, legs = C(196, 180, 140), hands = CL.white, feet = CL.black })
			townsman(K, { hairC = HAIR.dark, beard = "handlebar" })
			K.bicorne(CL.black, { trim = CL.white })
			K.collar(CL.belgianRed)
			K.buttons(CL.steel, 5, { double = true, top = A.yNeck - 0.25 * s })
			K.aiguillette(CL.belgianYellow)
			K.crossbelts(C(220, 200, 150), {})
			K.skirt(coat, 0.8, { tails = true })
			K.tallboots(CL.black)
			K.sabre({ scabbard = CL.steel, hilt = CL.brass })
		end,
	})
	def({
		id = "Barmaid", name = "Serveuse", title = "Barmaid", category = "Ambient", district = "EastBank",
		where = "Estaminet « Au Perron d'Or », between the tables and behind the bar.", behaviour = "Work", health = 100, speed = 8, variants = 2,
		body = { width = 0.9, depth = 0.95, limb = 0.85 },
		lines = { "Peket or a pint?", "No credit, Jef, not after last time.", "Madame doesn't like trouble. Neither do I." },
		outfit = function(K)
			local A, s = K.A, K.s
			local sk = K.pick(SKIN)
			local bodice = K.vary({ CL.burgundy, CL.bottle })
			K.paint({ skin = sk, torso = bodice, arms = CL.white, forearms = sk, legs = CL.charcoal, feet = CL.black })
			K.hair("bun", K.pick(HAIRS))
			K.face({ fem = true, blush = true })
			K.mobcap(CL.white)
			K.vneck(CL.white, 0.5, 0.4)
			K.rolled(CL.white)
			K.dress(K.vary({ CL.charcoal, CL.navy }), { flare = 0.4 })
			K.apron(CL.white, { z = A.td * -0.5 - 0.22 * s, bottom = A.yHip * 0.72, w = A.tw / 2 - 0.05 * s })
			K.shoes(CL.black)
			K.jug(1)
			K.mug(-1)
		end,
	})

	------------------------------------------------ named characters
	def({
		id = "LouisDolne", name = "Louis Dolne", title = "Armurier, maker of the Apache", category = "Named", district = "EastBank",
		where = "Behind the counter of the Atelier L. Dolne, Outremeuse.", behaviour = "Shopkeeper", health = 200, speed = 7, variants = 1, prompt = "Talk",
		lines = {
			"Bienvenue chez Dolne. Knife, knuckleduster and six shots in one frame. Clever, no?",
			"The Paris gangs love it. I only make it; what they do with it is their business.",
			"Every barrel is proofed at the Banc d'Épreuves. Look for the stamp.",
		},
		outfit = function(K)
			local A, s = K.A, K.s
			local shirt = CL.white
			K.paint({ skin = C(226, 186, 156), torso = CL.bottle, arms = shirt, legs = CL.charcoal, feet = CL.black })
			townsman(K, { hairC = HAIR.grey, beard = "imperial" })
			K.spectacles(CL.gold)
			K.vneck(shirt, 0.55, 0.32)
			K.shirtFront(shirt, CL.black, "bow")
			K.buttons(CL.brass, 4, { top = A.yNeck - 0.6 * s })
			K.armband(CL.black)
			K.cuffs(shirt, 0.15)
			K.apron(CL.leather, { bib = true, bottom = A.yHip - 1.0 * s, mat = M.Leather })
			K.watchChain()
			K.shoes(CL.black)
			K.file(1)
		end,
	})
	def({
		id = "ProofMaster", name = "Le Contrôleur", title = "Proof master of the Banc d'Épreuves", category = "Named", district = "EastBank",
		where = "Entrance hall of the Banc d'Épreuves.", behaviour = "Shopkeeper", health = 180, speed = 7, variants = 1, prompt = "Talk",
		lines = {
			"No arm leaves Liège without our stamp. The law of 1846.",
			"Double charge, double ball. If it bursts here, it doesn't burst in your hand.",
			"Someone has been stealing proofed barrels from the racks. Find them, and we will talk.",
		},
		outfit = function(K)
			local A, s = K.A, K.s
			K.paint({ skin = C(232, 196, 168), torso = CL.black, legs = CL.charcoal, feet = CL.black })
			townsman(K, { hair = "bald", hairC = HAIR.grey, beard = "walrus" })
			K.bowler(CL.black)
			K.spectacles(CL.gold, { pincenez = true })
			K.vneck(CL.charcoal, 0.9, 0.4)
			K.shirtFront(CL.white, CL.black, "cravat")
			K.skirt(CL.black, 1.0)
			K.cuffs(CL.white, 0.12)
			K.shoes(CL.black)
			K.book(-1, C(120, 40, 36), true)
			K.stamp(1)
		end,
	})
	def({
		id = "Commissaire", name = "Commissaire Hallet", title = "Police commissioner", category = "Named", district = "WestBank",
		where = "Place du Marché, in front of the Hôtel de Ville.", behaviour = "QuestGiver", health = 250, speed = 9, variants = 1, prompt = "Talk",
		lines = {
			"Three bodies on the Quai since Sunday, all with Dolne's little toy beside them.",
			"The Apaches have a king now. Find out where he holds court.",
			"Officially, you work for no one. Unofficially, the city is grateful.",
		},
		outfit = function(K)
			local A, s = K.A, K.s
			local coat = C(92, 74, 56)
			K.paint({ skin = C(220, 176, 144), torso = coat, legs = CL.charcoal, feet = CL.black })
			townsman(K, { hairC = HAIR.dark, beard = "handlebar" })
			K.bowler(C(46, 40, 36))
			K.buttons(CL.darkwood, 4, { double = true, top = A.yNeck - 0.5 * s })
			K.vneck(CL.charcoal, 0.45, 0.3)
			K.shirtFront(CL.white, CL.black, "cravat")
			K.tricolor({ out = 0.12 })
			K.skirt(coat, 1.2, { loose = 0.1 })
			K.shoes(CL.black)
			K.cane(CL.black, 1, CL.steel)
		end,
	})
	def({
		id = "Patronne", name = "Madame Gilson", title = "La patronne of the Estaminet", category = "Named", district = "EastBank",
		where = "Behind the bar of the Estaminet « Au Perron d'Or ».", behaviour = "Shopkeeper", health = 200, speed = 6, variants = 1, prompt = "Talk",
		body = { width = 1.1, depth = 1.2, limb = 0.95 },
		lines = {
			"Sit, drink, pay. In that order.",
			"The Apaches drink here too. Everybody drinks here. That's how I hear things.",
			"You want the Roi? Try the coal yard after dark. You didn't hear it from me.",
		},
		outfit = function(K)
			local A, s = K.A, K.s
			local sk = C(232, 190, 160)
			K.paint({ skin = sk, torso = CL.navy, arms = CL.navy, legs = CL.charcoal, feet = CL.black })
			K.hair("bun", HAIR.grey)
			K.face({ fem = true, blush = true })
			K.earring(1)
			K.earring(-1)
			K.dress(CL.charcoal, { flare = 0.4, width = 0.26 })
			K.apron(C(220, 210, 190), { z = A.td * -0.5 - 0.26 * s, bottom = A.yHip * 0.72, w = A.tw / 2, bib = true, bibW = 0.5 * s })
			K.shawl(CL.burgundy, { fringe = CL.gold, depth = 0.8 })
			K.keys()
			K.shoes(CL.black)
		end,
	})
	def({
		id = "AbbeSaintPaul", name = "L'abbé Lambrecht", title = "Priest of Saint-Paul", category = "Named", district = "WestBank",
		where = "Before the altar of the Cathédrale Saint-Paul.", behaviour = "QuestGiver", health = 150, speed = 6, variants = 1, prompt = "Talk",
		lines = {
			"Even the Roi des Apaches was baptised in this font, you know.",
			"Confession is at six. Whatever you have done, it can wait until six.",
			"The poor of Outremeuse have no one. Perhaps they have you.",
		},
		outfit = function(K)
			local A, s = K.A, K.s
			K.paint({ skin = C(236, 200, 172), torso = CL.black, legs = CL.black, feet = CL.black })
			townsman(K, { hairC = HAIR.white, hair = "bald" })
			K.biretta(CL.black)
			K.shirtFront(CL.black, CL.white, "roman")
			K.robe(CL.black, { buttons = C(150, 30, 40), sash = C(150, 30, 40) })
			K.cross(CL.gold)
			K.spectacles(CL.steel)
			K.book(1, C(40, 30, 30))
		end,
	})
	def({
		id = "ChefDeGare", name = "Le Chef de gare", title = "Station master of Longdoz", category = "Named", district = "EastBank",
		where = "Platform of the Gare de Longdoz.", behaviour = "QuestGiver", health = 180, speed = 7, variants = 1, prompt = "Talk",
		lines = {
			"The Brussels express is on time. The Brussels express is never on time. Something is wrong.",
			"Crates marked 'machine parts' go out every Thursday. They clank like rifles.",
			"Tickets at the window. I only blow the whistle.",
		},
		outfit = function(K)
			local A, s = K.A, K.s
			local coat = C(30, 36, 64)
			K.paint({ skin = C(226, 186, 156), torso = coat, legs = coat, feet = CL.black })
			townsman(K, { hairC = HAIR.grey, beard = "friendly" })
			K.kepi(coat, { top = CL.belgianRed, braid = CL.gold, badge = CL.gold, h = 0.38 })
			K.buttons(CL.gold, 6, { top = A.yNeck - 0.2 * s })
			K.collar(CL.belgianRed)
			K.skirt(coat, 1.0, { closed = true })
			K.watchChain()
			K.whistle(CL.gold)
			K.shoes(CL.black)
		end,
	})
	def({
		id = "Bourgmestre", name = "Le Bourgmestre", title = "Mayor of Liège", category = "Named", district = "WestBank",
		where = "Top of the Perron steps of the Hôtel de Ville.", behaviour = "QuestGiver", health = 200, speed = 6, variants = 1, prompt = "Talk",
		lines = {
			"Liège does not bow. Not to bishops, not to the Dutch, and certainly not to gangsters.",
			"The Council will not hear of 'Apaches' in my city. Make sure there is nothing to hear.",
			"The Perron stands for our freedom. Do try not to shoot it.",
		},
		outfit = function(K)
			local A, s = K.A, K.s
			K.paint({ skin = C(228, 186, 158), torso = CL.black, legs = CL.charcoal, feet = CL.black })
			townsman(K, { hairC = HAIR.white, beard = "full" })
			K.tophat(CL.black, { h = 1.1 })
			K.vneck(CL.cream, 1.0, 0.44)
			K.shirtFront(CL.white, CL.black, "cravat")
			K.watchChain()
			K.tricolor({ out = 0.04 })
			K.skirt(CL.black, 1.1)
			K.cuffs(CL.white, 0.12)
			K.shoes(CL.black)
			K.cane(CL.black, 1, CL.gold)
		end,
	})

	------------------------------------------------ the Apaches (hostile)
	local function apacheBase(K, o)
		local A, s = K.A, K.s
		local sk = o.skin or K.pick(SKIN)
		K.paint({ skin = sk, torso = CL.white, arms = o.arms or CL.white, forearms = o.forearms, legs = CL.charcoal, feet = CL.black })
		K.hair(o.hair or "short", o.hairC or K.pick(HAIRS))
		K.face({ angry = true, scar = o.scar, noMouth = o.noMouth })
		K.beard(o.beard or "sideburns", o.hairC)
		if o.stripes ~= false then K.stripes(CL.navy, 5, { arms = o.arms == nil, rolled = o.forearms ~= nil }) end
		K.sash(CL.red, { out = 0.05 })
		K.flares(CL.charcoal)
		K.shoes(CL.black)
	end
	def({
		id = "ApacheKnife", name = "Apache", title = "Apache knifeman (surineur)", category = "Hostile", district = "Anywhere",
		where = "Back yards, impasses, the east-bank yards, the coal yard at night.", behaviour = "Hostile", health = 120, speed = 16, variants = 2,
		lines = { "La bourse ou la vie.", "Wrong street, bourgeois.", "Tu vas voir, toi!" },
		outfit = function(K)
			apacheBase(K, { beard = K.vary({ "sideburns", "mustache" }) })
			K.flatcap(K.vary({ CL.black, CL.grey }), { big = true, tilt = K.vary({ 0.15, -0.15 }) })
			K.shirtFront(CL.white, CL.red, "neckerchief")
			K.knife(-1)
		end,
	})
	def({
		id = "ApacheBrawler", name = "Apache", title = "Apache bruiser (cogneur)", category = "Hostile", district = "Anywhere",
		where = "Guarding doors and yard gates; the Estaminet at closing time.", behaviour = "Hostile", health = 200, speed = 14, variants = 2,
		body = { scale = 1.08, width = 1.2, depth = 1.15, limb = 1.15 },
		lines = { "You want to dance?", "The Roi says nobody passes.", "Hah! Again!" },
		outfit = function(K)
			local A, s = K.A, K.s
			local sk = K.pick(SKIN)
			apacheBase(K, { skin = sk, hair = "bald", hairC = HAIR.dark, forearms = sk, beard = K.vary({ "walrus", "stubble" }), scar = K.variant == 2 })
			K.braces(CL.black)
			K.rolled(CL.white)
			K.shirtFront(CL.white, CL.red, "neckerchief")
			K.knuckles(1)
			K.knuckles(-1)
		end,
	})
	def({
		id = "ApacheLookout", name = "Apache", title = "Apache lookout (guetteur)", category = "Hostile", district = "Anywhere",
		where = "Street corners near gang spots, archways over the impasses.", behaviour = "Hostile", health = 100, speed = 17, variants = 2,
		lines = { "Cops! Scatter!", "Psst. Someone's coming.", "I saw nothing, m'sieur l'agent." },
		outfit = function(K)
			local A, s = K.A, K.s
			apacheBase(K, { beard = "none", noMouth = true })
			K.jacketOpen(K.vary({ CL.charcoal, CL.brown }), { open = 0.35, collar = CL.black })
			K.flatcap(K.vary({ CL.charcoal, CL.brown }), { big = true, pitch = -0.15 })
			K.facescarf(K.vary({ CL.belgianRed, CL.charcoal }))
		end,
	})
	def({
		id = "ApacheGunman", name = "Apache", title = "Apache gunman (tireur)", category = "Hostile", district = "Anywhere",
		where = "Covering the others from doorways, the archways, the coal heaps.", behaviour = "Hostile", health = 110, speed = 15, variants = 2, holdsApache = true,
		lines = { "Six shots, and the seventh is the knife.", "Dolne makes them, we use them.", "Stay down!" },
		outfit = function(K)
			local A, s = K.A, K.s
			apacheBase(K, { beard = K.vary({ "mustache", "goatee" }), stripes = false })
			K.vneck(CL.white, 0.8, 0.4)
			K.stripes(CL.navy, 2, {})
			K.bowler(K.vary({ CL.black, C(70, 60, 50) }), { tilt = 0.12 })
			K.jacketOpen(CL.black, { open = 0.45 })
			K.shirtFront(CL.white, CL.red, "neckerchief")
			K.cigarette()
		end,
	})

	------------------------------------------------ bosses
	def({
		id = "BossButcher", name = "Le Boucher de la Batte", title = "Boss: the Butcher", category = "Boss", district = "WestBank",
		where = "Halle aux Viandes on the Quai de la Batte (arena: NPCMarkers/BossArenas/Butcher).", behaviour = "Boss", health = 1800, speed = 13, variants = 1,
		arena = "Butcher",
		body = { scale = 1.35, width = 1.3, depth = 1.35, limb = 1.25, head = 1.05, legs = 0.95 },
		lines = { "Fresh meat walked in on its own!", "Every carcass in this hall was once as brave as you.", "Hold still, I cut clean." },
		moves = {
			"Cleaver sweep: wide horizontal arc in front, heavy damage, slow wind-up.",
			"Hook throw: chain hook pulls the player in for a cleaver chop.",
			"Belly charge: straight-line rush; he stuns himself on the hall columns.",
			"Below 40%: throws carcasses from the meat rails (use the MeatRail in the hall).",
		},
		outfit = function(K)
			local A, s = K.A, K.s
			local sk = C(214, 150, 120)
			local shirt = C(200, 206, 220)
			K.paint({ skin = sk, torso = shirt, arms = shirt, forearms = sk, legs = C(70, 66, 64), feet = CL.black })
			townsman(K, { hair = "bald", hairC = HAIR.ginger, beard = "friendly", face = { angry = true, scar = true } })
			K.stripes(C(110, 130, 170), 4, {})
			K.rolled(shirt)
			K.shirtFront(shirt, CL.red, "neckerchief")
			local bz = K.belly(shirt, 0.45)
			K.apron(CL.white, { z = bz, bottom = A.yHip - 1.3 * s, bib = true, bibW = 0.7 * s, bibZ = bz, stripes = C(150, 170, 200),
				stains = { { -0.4, 1.0, 0.18 }, { 0.3, 0.5, 0.12 }, { 0.1, 1.5, 0.1 } } })
			K.boots(CL.black, 0.7)
			K.cleaver(1)
			K.hook(-1)
		end,
	})
	def({
		id = "BossFounder", name = "Le Maître Fondeur", title = "Boss: the Foundry Master", category = "Boss", district = "EastBank",
		where = "Fonderie Royale de Canons (arena: NPCMarkers/BossArenas/Foundry).", behaviour = "Boss", health = 2600, speed = 10, variants = 1,
		arena = "Foundry",
		body = { scale = 1.55, width = 1.3, depth = 1.2, limb = 1.3, head = 0.95 },
		lines = { "The furnace is hungry.", "I cast the cannon that guard your Citadel. I can cast a coffin.", "Molten iron does not miss." },
		moves = {
			"Sledge slam: ground shockwave ring; the hammer head leaves a burning patch.",
			"Ladle pour: arcs molten iron in a line; burning floor for a few seconds.",
			"Furnace vent: opens a furnace; heat damage near the furnace mouths (FurnaceMouth parts).",
			"Armoured: pauldrons and apron could take reduced damage; hits to the head or back do full.",
		},
		outfit = function(K)
			local A, s = K.A, K.s
			local sk = C(150, 110, 86)
			K.paint({ skin = sk, torso = C(54, 50, 48), arms = C(54, 50, 48), hands = CL.leather, legs = C(48, 44, 42), feet = CL.black, mat = { hands = M.Leather } })
			K.hair("none", HAIR.black)
			K.face({ angry = true, noMouth = true, noEars = true })
			K.hood(CL.darkleather, C(70, 50, 36))
			K.goggles(CL.ember)
			K.mantle(CL.darkleather)
			K.pauldrons(C(70, 72, 76))
			K.crossbelts(C(60, 62, 66), {})
			K.apron(CL.darkleather, { bottom = A.yHip - 1.6 * s, bib = true, bibW = 0.75 * s, mat = M.Leather, tie = CL.black })
			K.gauntlets(CL.leather)
			K.belt(CL.black, CL.iron, { out = 0.1, h = 0.3 })
			K.tallboots(CL.black)
			K.embers("LowerTorso", { { -0.5, A.yHip - 0.6 * s, -A.td / 2 - 0.09 * s }, { 0.4, A.yHip - 1.1 * s, -A.td / 2 - 0.09 * s }, { 0.0, A.yHip - 0.3 * s, -A.td / 2 - 0.09 * s } })
			K.sledge(1)
			K.ladle(-1)
		end,
	})
	def({
		id = "BossApacheKing", name = "Le Roi des Apaches", title = "Boss: the Apache King", category = "Boss", district = "EastBank",
		where = "Charbonnages de Longdoz coal yard (arena: NPCMarkers/BossArenas/ApacheKing).", behaviour = "Boss", health = 1400, speed = 20, variants = 1,
		arena = "ApacheKing", holdsApache = true,
		body = { scale = 1.12, width = 0.95, depth = 0.95, limb = 0.92, head = 0.98, legs = 1.06 },
		lines = { "So. The city sends a dog.", "Liège made this little revolver. Liège will bury you with it.", "Les gars! Finish this one." },
		moves = {
			"Apache revolver: six fast shots, then a reload window (hold his gun at RightGripAttachment).",
			"Knife lunge: dash across the yard behind a coal heap and strike.",
			"Call the gang: two ApacheKnife and one ApacheGunman from the yard gates at 66% and 33%.",
			"Smoke: kicks coal dust (a Smoke burst) and repositions.",
		},
		outfit = function(K)
			local A, s = K.A, K.s
			local sk = C(226, 190, 160)
			K.paint({ skin = sk, torso = CL.white, arms = CL.black, legs = CL.black, feet = CL.black })
			townsman(K, { hairC = HAIR.black, beard = "sideburns", face = { angry = true, scar = true } })
			K.beard("mustache", HAIR.black)
			K.stripes(CL.navy, 5, {})
			K.jacketOpen(CL.black, { open = 0.4, collar = C(20, 20, 24) })
			K.bowler(CL.black, { tilt = 0.2, pitch = -0.1, band = CL.belgianRed })
			K.shirtFront(CL.white, CL.belgianRed, "neckerchief")
			K.sash(CL.belgianRed, { out = 0.06 })
			K.flares(CL.black)
			K.shoes(C(30, 30, 30))
			K.earring(-1)
			K.cigarette()
			K.watchChain(CL.gold)
			K.knife(-1)
		end,
	})

	local byId = {}
	for _, d in ipairs(ROSTER) do
		byId[d.id] = d
	end

	---------------------------------------------------------------- build one character
	local function hash(str)
		local h = 5381
		for i = 1, #str do
			h = (h * 33 + string.byte(str, i)) % 2147483647
		end
		return h
	end

	local function build(id, variant, rig, origin)
		local d = byId[id] or error("unknown NPC id " .. tostring(id))
		variant = variant or 1
		rig = rig or "R15"
		local A = anatomy(d.body)
		local s = A.s
		local O = origin or CFrame.new()
		local boxes = segBoxes(A)

		local model = Instance.new("Model")
		model.Name = id .. (((d.variants or 1) > 1) and ("_" .. variant) or "")

		local seed = (hash(id) + variant * 7919) % 2147483647
		if seed <= 0 then seed = 1 end
		local ctx = { A = A, O = O, rig = rig, boxes = boxes, variant = variant, count = 0, body = {} }
		function ctx.rng()
			seed = (seed * 16807) % 2147483647
			return seed / 2147483647
		end

		-- body
		local names = rig == "R6" and { "HumanoidRootPart", "Torso", "Head", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }
			or { "HumanoidRootPart", "LowerTorso", "UpperTorso", "Head", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm",
				"RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot" }
		for _, n in ipairs(names) do
			local b = boxes[n]
			local p = newPart("Block", n, O * CFrame.new(boxCenter(b)), boxSize(b), SKIN[1], M.SmoothPlastic)
			p.Anchored = false
			p.CanCollide = COLLIDE[n] == true
			p.Parent = model
			ctx.body[n] = p
			ctx.count += 1
		end
		local hrp = ctx.body.HumanoidRootPart
		hrp.Transparency = 1
		hrp.CanCollide = false
		hrp.RootPriority = 127

		local function partName(seg)
			return rig == "R6" and (R6MAP[seg] or seg) or seg
		end
		function ctx.partFor(seg)
			return ctx.body[partName(seg)] or error("no body part for " .. seg)
		end
		local function att(pn, name, point, rot)
			local a = Instance.new("Attachment")
			a.Name = name
			a.CFrame = CFrame.new(point - boxCenter(boxes[pn])) * (rot or CFrame.new())
			a.Parent = ctx.body[pn]
			return a
		end

		-- joints
		if rig == "R6" then
			local function rc(x, y, z, m)
				return CFrame.new(x, y, z, m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8], m[9])
			end
			local RROOT = { -1, 0, 0, 0, 0, 1, 0, 1, 0 }
			local RR = { 0, 0, 1, 0, 1, 0, -1, 0, 0 }
			local RL = { 0, 0, -1, 0, 1, 0, 1, 0, 0 }
			local function m6(name, holder, p0, p1, c0, c1)
				local m = Instance.new("Motor6D")
				m.Name = name
				m.Part0 = ctx.body[p0]
				m.Part1 = ctx.body[p1]
				m.C0 = c0
				m.C1 = c1
				m.Parent = ctx.body[holder]
			end
			local th, tw, aw, lw = A.th, A.tw, A.aw, A.lw
			m6("RootJoint", "HumanoidRootPart", "HumanoidRootPart", "Torso", rc(0, 0, 0, RROOT), rc(0, 0, 0, RROOT))
			m6("Neck", "Torso", "Torso", "Head", rc(0, th / 2, 0, RROOT), rc(0, -A.hh / 2, 0, RROOT))
			m6("Right Shoulder", "Torso", "Torso", "Right Arm", rc(tw / 2, th / 2 - aw / 2, 0, RR), rc(-aw / 2, A.armH / 2 - aw / 2, 0, RR))
			m6("Left Shoulder", "Torso", "Torso", "Left Arm", rc(-tw / 2, th / 2 - aw / 2, 0, RL), rc(aw / 2, A.armH / 2 - aw / 2, 0, RL))
			m6("Right Hip", "Torso", "Torso", "Right Leg", rc(A.hx + lw / 2, -th / 2, 0, RR), rc(lw / 2, A.legH / 2, 0, RR))
			m6("Left Hip", "Torso", "Torso", "Left Leg", rc(-(A.hx + lw / 2), -th / 2, 0, RL), rc(-lw / 2, A.legH / 2, 0, RL))
		else
			local function motor(name, p0, p1, pivot)
				local a0 = att(p0, name .. "RigAttachment", pivot)
				local a1 = att(p1, name .. "RigAttachment", pivot)
				local m = Instance.new("Motor6D")
				m.Name = name
				m.Part0 = ctx.body[p0]
				m.Part1 = ctx.body[p1]
				m.C0 = a0.CFrame
				m.C1 = a1.CFrame
				m.Parent = ctx.body[p1]
			end
			motor("Root", "HumanoidRootPart", "LowerTorso", Vector3.new(0, A.yHip + A.lh / 2, 0))
			motor("Waist", "LowerTorso", "UpperTorso", Vector3.new(0, A.yWaist, 0))
			motor("Neck", "UpperTorso", "Head", Vector3.new(0, A.yNeck, 0))
			for _, sd in ipairs({ -1, 1 }) do
				local L = sd < 0 and "Left" or "Right"
				motor(L .. "Shoulder", "UpperTorso", L .. "UpperArm", Vector3.new(sd * A.tw / 2, A.yNeck - 0.25 * A.aw, 0))
				motor(L .. "Elbow", L .. "UpperArm", L .. "LowerArm", Vector3.new(sd * A.ax, A.yElbow, 0))
				motor(L .. "Wrist", L .. "LowerArm", L .. "Hand", Vector3.new(sd * A.ax, A.yWrist, 0))
				motor(L .. "Hip", "LowerTorso", L .. "UpperLeg", Vector3.new(sd * A.hx, A.yHip, 0))
				motor(L .. "Knee", L .. "UpperLeg", L .. "LowerLeg", Vector3.new(sd * A.hx, A.yKnee, 0))
				motor(L .. "Ankle", L .. "LowerLeg", L .. "Foot", Vector3.new(sd * A.hx, A.yAnkle, 0))
			end
		end

		-- accessory attachments (standard names, so Humanoid:AddAccessory works) + a few extras
		local function acc(seg, name, point, rot)
			att(partName(seg), name, point, rot)
		end
		local yMid = (A.yWaist + A.yNeck) / 2
		acc("Head", "HatAttachment", Vector3.new(0, A.yTop, 0))
		acc("Head", "HairAttachment", Vector3.new(0, A.yTop, 0))
		acc("Head", "FaceFrontAttachment", Vector3.new(0, A.yNeck + A.hh / 2, -A.hd / 2))
		acc("Head", "FaceCenterAttachment", Vector3.new(0, A.yNeck + A.hh / 2, 0))
		acc("Head", "OverheadAttachment", Vector3.new(0, A.yTop + 1.6 * s, 0))
		acc("UpperTorso", "NeckAttachment", Vector3.new(0, A.yNeck, 0))
		acc("UpperTorso", "BodyFrontAttachment", Vector3.new(0, yMid, -A.td / 2))
		acc("UpperTorso", "BodyBackAttachment", Vector3.new(0, yMid, A.td / 2))
		acc("UpperTorso", "LeftCollarAttachment", Vector3.new(-A.tw / 4, A.yNeck, 0))
		acc("UpperTorso", "RightCollarAttachment", Vector3.new(A.tw / 4, A.yNeck, 0))
		acc("UpperTorso", "PromptAttachment", Vector3.new(0, yMid, -A.td / 2 - 0.5))
		acc("LowerTorso", "WaistCenterAttachment", Vector3.new(0, A.yHip + A.lh / 2, 0))
		acc("LowerTorso", "WaistFrontAttachment", Vector3.new(0, A.yHip + A.lh / 2, -A.td / 2))
		acc("LowerTorso", "WaistBackAttachment", Vector3.new(0, A.yHip + A.lh / 2, A.td / 2))
		for _, sd in ipairs({ -1, 1 }) do
			local L = sd < 0 and "Left" or "Right"
			acc(L .. "UpperArm", L .. "ShoulderAttachment", Vector3.new(sd * A.ax, A.yNeck, 0))
			acc(L .. "Hand", L .. "GripAttachment", Vector3.new(sd * A.ax, A.yHand, 0), CFrame.Angles(-PI / 2, 0, 0))
			acc(L .. "Foot", L .. "FootAttachment", Vector3.new(sd * A.hx, 0, 0))
		end
		acc("HumanoidRootPart", "RootAttachment", Vector3.new(0, yMid - A.lh / 2, 0))

		-- outfit
		ctx.outfit = Instance.new("Model")
		ctx.outfit.Name = "Outfit"
		ctx.outfit.Parent = model
		local propsModel
		function ctx.props()
			if not propsModel then
				propsModel = Instance.new("Model")
				propsModel.Name = "Props"
				propsModel.Parent = model
			end
			return propsModel
		end
		local K = makeKit(ctx)
		d.outfit(K)

		-- humanoid
		local hum = Instance.new("Humanoid")
		hum.RigType = rig == "R6" and Enum.HumanoidRigType.R6 or Enum.HumanoidRigType.R15
		hum.HipHeight = rig == "R6" and 0 or A.legH
		hum.AutomaticScalingEnabled = false
		hum.DisplayName = d.name
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		hum.MaxHealth = d.health or 100
		hum.Health = d.health or 100
		hum.WalkSpeed = d.speed or 8
		hum.BreakJointsOnDeath = false
		hum.Parent = model
		local animator = Instance.new("Animator")
		animator.Parent = hum

		if d.prompt then
			local pp = Instance.new("ProximityPrompt")
			pp.Name = "TalkPrompt"
			pp.ActionText = d.prompt
			pp.ObjectText = d.name
			pp.MaxActivationDistance = 10
			pp.RequiresLineOfSight = false
			pp.HoldDuration = 0
			pp.Parent = ctx.partFor("UpperTorso"):FindFirstChild("PromptAttachment")
		end

		-- pivot at the feet, so model:PivotTo(markerCFrame) stands the character on the marker
		hrp.PivotOffset = CFrame.new(0, -(A.yHip + A.yNeck) / 2, 0)
		model.PrimaryPart = hrp
		model.WorldPivot = O
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		model:SetAttribute("NPCId", id)
		model:SetAttribute("Variant", variant)
		model:SetAttribute("DisplayName", d.name)
		model:SetAttribute("Title", d.title)
		model:SetAttribute("Category", d.category)
		model:SetAttribute("District", d.district)
		model:SetAttribute("Behaviour", d.behaviour)
		model:SetAttribute("Hostile", d.category == "Hostile" or d.category == "Boss")
		model:SetAttribute("Rig", rig)
		model:SetAttribute("Scale", s)
		model:SetAttribute("Height", A.yTop)
		if d.holdsApache then model:SetAttribute("HoldsApache", true) end
		if d.arena then model:SetAttribute("Arena", d.arena) end
		model:AddTag("LiegeNPC")
		model:AddTag("Liege" .. d.category)
		return model, ctx.count
	end

	---------------------------------------------------------------- catalogue + gallery
	local function serialize(v, indent)
		indent = indent or ""
		local t = type(v)
		if t == "string" then return string.format("%q", v) end
		if t ~= "table" then return tostring(v) end
		local inner = indent .. "\t"
		local out = {}
		if #v > 0 then
			for _, x in ipairs(v) do
				out[#out + 1] = inner .. serialize(x, inner) .. ","
			end
		else
			local keys = {}
			for k in pairs(v) do
				keys[#keys + 1] = k
			end
			table.sort(keys)
			for _, k in ipairs(keys) do
				local key = string.match(k, "^[%a_][%w_]*$") and k or ("[" .. string.format("%q", k) .. "]")
				out[#out + 1] = inner .. key .. " = " .. serialize(v[k], inner) .. ","
			end
		end
		return "{\n" .. table.concat(out, "\n") .. "\n" .. indent .. "}"
	end

	local function catalogSource()
		local cat = {}
		for _, d in ipairs(ROSTER) do
			local models = {}
			for v = 1, d.variants or 1 do
				models[#models + 1] = d.id .. (((d.variants or 1) > 1) and ("_" .. v) or "")
			end
			cat[d.id] = {
				DisplayName = d.name, Title = d.title, Category = d.category, District = d.district, Where = d.where,
				Behaviour = d.behaviour, Hostile = d.category == "Hostile" or d.category == "Boss", Health = d.health, WalkSpeed = d.speed,
				Models = models, Lines = d.lines, Moves = d.moves, Arena = d.arena, HoldsApache = d.holdsApache,
				Scale = (d.body and d.body.scale) or 1,
			}
		end
		return "--[[\n\tNPCCatalog: data for every character in this folder (generated; no behaviour).\n"
			.. "\tKeys are NPC ids (the model's NPCId attribute). Models lists the variant model names.\n"
			.. "\tWhere, Behaviour, Lines and Moves are suggestions for the scripts you write.\n]]\nreturn "
			.. serialize(cat) .. "\n"
	end

	local GROUPS = {
		{ "Bosses", 18, function(d) return d.category == "Boss" end },
		{ "Named", 8, function(d) return d.category == "Named" end },
		{ "Hostile", 7.5, function(d) return d.category == "Hostile" end },
		{ "Ambient/WestBank", 7, function(d) return d.category == "Ambient" and d.district == "WestBank" end },
		{ "Ambient/EastBank", 7, function(d) return d.category == "Ambient" and d.district == "EastBank" end },
		{ "Ambient/River", 7, function(d) return d.category == "Ambient" and d.district == "River" end },
		{ "Ambient/CitadelAndPolice", 7.5, function(d) return d.category == "Ambient" and d.district == "CitadelAndPolice" end },
	}
	local GALLERY = Vector3.new(-200, 0, 620)

	local function library(rig)
		rig = rig or "R15"
		local root = Instance.new("Folder")
		root.Name = "LiegeNPCs"
		root:SetAttribute("Rig", rig)
		local stats = { models = 0, parts = 0, maxParts = 0, perModel = {} }
		local folders = {}
		local function folderFor(path)
			if folders[path] then return folders[path] end
			local parent, name = root, path
			local slash = string.find(path, "/")
			if slash then
				parent = folderFor(string.sub(path, 1, slash - 1))
				name = string.sub(path, slash + 1)
			end
			local f = Instance.new("Folder")
			f.Name = name
			f.Parent = parent
			folders[path] = f
			return f
		end
		for row, g in ipairs(GROUPS) do
			local col = 0
			for _, d in ipairs(ROSTER) do
				if g[3](d) then
					for v = 1, d.variants or 1 do
						local o = CFrame.new(GALLERY + Vector3.new(col * g[2], 0, (row - 1) * 16))
						local m, count = build(d.id, v, rig, o)
						m.Parent = folderFor(g[1])
						stats.models += 1
						stats.parts += count
						if count > stats.maxParts then stats.maxParts = count end
						stats.perModel[m.Name] = count
						col += 1
					end
				end
			end
		end
		local catalog = Instance.new("ModuleScript")
		catalog.Name = "NPCCatalog"
		catalog.Source = catalogSource()
		catalog.Parent = root
		return root, stats
	end

	return {
		roster = ROSTER,
		byId = byId,
		build = build,
		library = library,
		catalogSource = catalogSource,
		anatomy = anatomy,
		gallery = GALLERY,
	}
end
