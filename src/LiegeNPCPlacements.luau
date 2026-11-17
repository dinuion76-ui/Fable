--!nocheck
--[[
	Where the characters from LiegeNPCs belong on the Liège map: spawn markers, patrol routes and boss arenas.
	Pure data plus a builder for the marker parts; nothing here moves an NPC.

	local P = require(path)(R)
	P.spawns   { { npc, x, y, z, face, behaviour, extra }, ... }   face: N S E W (N = -Z); y is a level hint
	P.routes   { Name = { npc =, loop =, points = { {x, y, z}, ... } } }
	P.arenas   { Name = { boss =, bounds = {x0, y0, z0, x1, y1, z1}, spawn = {x, y, z, face}, entry = {x, y, z, face},
	                      doors = { Name = {x0, y0, z0, x1, y1, z1} } } }
	P.build(floorAt, roster)  -> Folder "NPCMarkers"
	    floorAt(x, z, yHint) returns the walkable height there (the build script snaps markers with it).
]]
return function(R)
	R = R or {}
	local Instance = R.Instance or Instance
	local Vector3 = R.Vector3 or Vector3
	local CFrame = R.CFrame or CFrame
	local Color3 = R.Color3 or Color3
	local Enum = R.Enum or Enum

	local PI = math.pi
	local YAW = { N = 0, S = PI, W = PI / 2, E = -PI / 2 }

	-- npc, x, y, z, face, behaviour, extra
	local SPAWNS = {
		-- Place du Marché
		{ "MarketVendor", -222, 0.2, -121.5, "S", "Work" },
		{ "MarketVendor", -196, 0.2, -121.5, "S", "Work" },
		{ "MarketWoman", -122, 0.2, -121.5, "S", "Work" },
		{ "MarketVendor", -96, 0.2, -121.5, "S", "Work" },
		{ "MarketWoman", -216, 0.2, -68.5, "N", "Work" },
		{ "MarketVendor", -100, 0.2, -70.5, "N", "Work" },
		{ "Gentleman", -178, 0.2, -99, "E", "Wander", { radius = 18 } },
		{ "Lady", -140, 0.2, -100, "W", "Wander", { radius = 15 } },
		{ "Urchin", -205, 0.2, -110, "S", "Wander", { radius = 20 } },
		{ "Commissaire", -175, 0.2, -82, "E", "QuestGiver" },
		{ "Bourgmestre", -158, 5, -64, "N", "QuestGiver" },
		-- Place Saint-Lambert
		{ "Newsboy", -240, 0.2, 0, "E", "Wander", { radius = 20 } },
		{ "Coachman", -298, 0.2, 64, "E", "Idle" },
		{ "Gentleman", -230, 0.2, 90, "W", "Wander", { radius = 20 } },
		{ "Lady", -250, 0.2, 20, "N", "Wander", { radius = 15 } },
		{ "Student", -300, 0.2, -20, "S", "Wander", { radius = 20 } },
		{ "MarketWoman", -255, 0.2, 30, "E", "Idle" },
		-- Palais des Princes-Évêques gate
		{ "Gendarme", -336, 0, -2, "E", "Guard" },
		{ "Gendarme", -336, 0, 10, "E", "Guard" },
		-- En Hors-Château, Féronstrée, the yards
		{ "Botteresse", -226, 0, -300, "N", "Wander", { radius = 40 } },
		{ "Nun", -232, 0, -356, "W", "Wander", { radius = 12 } },
		{ "Urchin", -158, 0.15, -270, "E", "Wander", { radius = 10 } },
		-- Quai de la Batte (market, Halle, barges)
		{ "MarketVendor", 78.5, 0.2, -424, "E", "Work" },
		{ "MarketWoman", 95.5, 0.2, -398, "W", "Work" },
		{ "MarketVendor", 78.5, 0.2, -372, "E", "Work" },
		{ "Botteresse", 88, 0.2, -330, "S", "Wander", { radius = 30 } },
		{ "Gentleman", 100, 0.2, -150, "S", "Wander", { radius = 25 } },
		{ "Bargeman", 100, 0.2, -266, "E", "Idle" },
		{ "CoalHeaver", 100, 0.2, 55, "E", "Work" },
		-- Rue Léopold, Pont des Arches
		{ "PoliceAgent", 100, 0.2, -22, "E", "Guard" },
		{ "Beggar", 115, 0.2, -12, "S", "Idle" },
		{ "Newsboy", 60, 0, 0, "E", "Wander", { radius = 25 } },
		{ "Gentleman", -40, 0, 0, "E", "Wander", { radius = 25 } },
		{ "Lady", 20, 0, 0, "W", "Wander", { radius = 25 } },
		-- Passage Lemonnier
		{ "Student", -50, 0.2, 102, "E", "Wander", { radius = 12 } },
		{ "Lady", -30, 0.2, 102, "W", "Wander", { radius = 12 } },
		-- Cathédrale Saint-Paul and its square, Théâtre Royal
		{ "AbbeSaintPaul", -133, 0.2, 281, "W", "QuestGiver" },
		{ "Nun", -215, 0.2, 281, "E", "Wander", { radius = 6 } },
		{ "Beggar", -232, 0, 244, "N", "Idle" },
		{ "Lady", -300, 0.2, 196, "E", "Wander", { radius = 20 } },
		{ "Gentleman", -150, 0.2, 200, "W", "Wander", { radius = 20 } },
		{ "Lady", -350, 0.2, 181, "E", "Idle" },
		{ "Gentleman", -350, 0.2, 170, "E", "Idle" },
		-- Sauvenière, goods yard, west gate
		{ "CoalHeaver", 28, 0.15, 400, "S", "Work" },
		{ "Hiercheuse", 5, 0.15, 416, "E", "Work" },
		{ "Urchin", -214, 0.15, 392, "N", "Wander", { radius = 15 } },
		{ "Soldier", -486, 0, 101, "E", "Guard" },
		-- hillside and Citadel
		{ "Botteresse", -290, 16, -160, "E", "Idle" },
		{ "Soldier", -396, 64.3, -194, "E", "Guard" },
		{ "Soldier", -396, 64.3, -166, "E", "Guard" },
		{ "Officer", -450, 64.3, -228, "E", "Idle" },
		{ "Soldier", -472, 64.3, -298, "E", "Guard" },
		{ "Soldier", 170, 22, -482, "S", "Guard" },
		-- Outremeuse: Dolne, the Banc d'Épreuves, yards
		{ "LouisDolne", 377.5, 0.15, -161.5, "W", "Shopkeeper" },
		{ "GunsmithJourneyman", 399, 0.15, -135, "S", "Work" },
		{ "GunsmithJourneyman", 409, 0.15, -419, "N", "Work" },
		{ "ProofMaster", 416, 0.15, -350, "W", "Shopkeeper" },
		{ "GunsmithJourneyman", 429.5, 0.15, -381, "E", "Work" },
		{ "Urchin", 301, 0.15, -200, "N", "Wander", { radius = 20 } },
		{ "Laundress", 301, 0.15, -296, "E", "Work" },
		{ "Laundress", 301, 0.15, 210, "W", "Work" },
		{ "Hiercheuse", 425, 0.15, -140, "W", "Work" },
		{ "PoliceAgent", 240, 0.2, 22, "W", "Guard" },
		-- Estaminet « Au Perron d'Or »
		{ "Patronne", 294, 0.15, 38, "W", "Shopkeeper" },
		{ "Barmaid", 294, 0.15, 26, "W", "Work" },
		{ "Barmaid", 275, 0.15, 29, "S", "Work" },
		{ "CoalHeaver", 282, 0.15, 42, "S", "Idle" },
		-- Fonderie
		{ "FoundryWorker", 434, 0.15, 65, "E", "Work" },
		{ "FoundryWorker", 434, 0.15, 115, "E", "Work" },
		{ "FoundryWorker", 399, 0.15, 105, "S", "Work" },
		-- east quay, station
		{ "Bargeman", 238, 0.2, 247, "W", "Idle" },
		{ "CoalHeaver", 244, 0.2, 270, "W", "Work" },
		{ "RailwayPorter", 330, 0.8, 432, "S", "Wander", { radius = 25 } },
		{ "RailwayPorter", 390, 0.8, 432, "S", "Wander", { radius = 25 } },
		{ "ChefDeGare", 356, 0.8, 431, "S", "QuestGiver" },
		{ "Gentleman", 300, 0.2, 340, "E", "Wander", { radius = 20 } },
		{ "Lady", 320, 0.2, 350, "W", "Wander", { radius = 20 } },
		{ "Coachman", 420, 0.2, 345, "W", "Idle" },
		-- the Apaches
		{ "ApacheKnife", -158, 0.15, -255, "N", "Hostile", { gang = "BackYards" } },
		{ "ApacheBrawler", -158, 0.15, -236, "S", "Hostile", { gang = "BackYards" } },
		{ "ApacheGunman", -158, 0.15, -322, "S", "Hostile", { gang = "BackYards" } },
		{ "ApacheLookout", -236, 0, -268, "E", "Hostile", { gang = "BackYards" } },
		{ "ApacheLookout", 426, 0.15, -250, "N", "Hostile", { gang = "EastYards" } },
		{ "ApacheKnife", 446, 0.15, -225, "W", "Hostile", { gang = "EastYards" } },
		{ "ApacheGunman", 450, 0.15, -160, "W", "Hostile", { gang = "EastYards" } },
		{ "ApacheLookout", 371, 0, -350, "W", "Hostile", { gang = "ProofHouse" } },
		{ "ApacheBrawler", 358, 0, 228, "W", "Hostile", { gang = "CoalYard" } },
		{ "ApacheLookout", 358, 0, 252, "W", "Hostile", { gang = "CoalYard" } },
	}

	-- Waypoints generated by tools/plan_routes.py (path-found around street clutter; re-run it after map changes).
	local ROUTES = {
		PoliceWest = { npc = "PoliceAgent", loop = true, points = { { -200, 0, -100 }, { -167, 0, -107 }, { -126, 0, -110 }, { -109, 0, -109 }, { -90, 0, -100 }, { -89, 0, -129 }, { -96, 0, -189 }, { -92, 0, -454 }, { -90, 0, -458 }, { -226, 0, -458 }, { -220, 0, -416 }, { -221, 0, -131 }, { -230, 0, -122 }, { -230, 0, -115 }, { -226, 0, -110 }, { -221, 0, -110 } } },
		PoliceEast = { npc = "PoliceAgent", loop = false, points = { { 353, 0, -440 }, { 342, 0, -410 }, { 342, 0, -346 }, { 345, 0, -343 }, { 345, 0, -12 }, { 349, 0, -4 }, { 350, 0, -5 }, { 371, 0, -4 }, { 374, 0, -1 }, { 379, 0, 0 }, { 412, 0, 1 }, { 440, 0, 0 } } },
		QuayWest = { npc = "PoliceAgent", loop = false, points = { { 100, 0.2, -440 }, { 96, 0.2, -333 }, { 94, 0.2, -331 }, { 94, 0.2, -322 }, { 99, 0.2, -316 }, { 96, 0.2, -261 }, { 85, 0.2, -250 }, { 87, 0.2, -206 }, { 96, 0.2, -197 }, { 100, 0.2, 54 }, { 102, 0.2, 56 }, { 100, 0.2, 136 }, { 100, 0.2, 328 }, { 102, 0.2, 330 }, { 100, 0.2, 365 }, { 100, 0.2, 430 } } },
		QuayEast = { npc = "Gendarme", loop = false, points = { { 248, 0.2, -440 }, { 242, 0.2, -292 }, { 238, 0.2, 128 }, { 239, 0.2, 145 }, { 247, 0.2, 390 }, { 248, 0.2, 430 } } },
		Feronstree = { npc = "Lamplighter", loop = false, points = { { -90, 0, -110 }, { -89, 0, -119 }, { -96, 0, -190 }, { -92, 0, -436 }, { -90, 0, -440 } } },
		CitadelRampart = { npc = "Soldier", loop = false, points = { { -411, 76, -488 }, { -411, 76, -108 } } },
		CitadelParade = { npc = "Soldier", loop = true, points = { { -470, 64.3, -460 }, { -430, 64.3, -460 }, { -433, 64.3, -400 }, { -430, 64.3, -140 }, { -470, 64.3, -140 } } },
	}

	local ARENAS = {
		Butcher = {
			boss = "BossButcher", name = "Halle aux Viandes",
			bounds = { 36, 0, -230, 68, 20, -198 },
			spawn = { 52, 0.15, -214, "E" },
			entry = { 78, 0.2, -214, "W" },
			-- doorways and the windows a player can jump through (sills at 4 studs)
			doors = { East = { 69, 0, -218, 71, 10, -210 }, South = { 44, 0, -197, 52, 10, -195 },
				WindowEastN = { 68, 4, -230, 70, 12, -222 }, WindowEastS = { 68, 4, -206, 70, 12, -198 }, WindowSouth = { 57, 4, -198, 65, 12, -196 } },
		},
		Foundry = {
			boss = "BossFounder", name = "Fonderie Royale de Canons",
			bounds = { 378, 0, 32, 468, 24, 148 },
			spawn = { 415, 0.15, 92, "W" },
			entry = { 368, 0, 88, "E" },
			doors = { West = { 375, 0, 80, 377, 14, 96 }, North = { 400, 0, 29, 408, 9, 31 }, South = { 420, 0, 149, 430, 10, 151 },
				Window1 = { 376, 6, 40, 378, 16, 52 }, Window2 = { 376, 6, 58, 378, 16, 70 }, Window3 = { 376, 6, 106, 378, 16, 118 },
				Window4 = { 376, 6, 124, 378, 16, 136 } },
		},
		ApacheKing = {
			boss = "BossApacheKing", name = "Charbonnages de Longdoz",
			bounds = { 367.5, 0, 179.5, 470, 30, 298.5 },
			spawn = { 440, 0.15, 241, "W" },
			entry = { 356, 0, 238, "E" },
			doors = { West = { 365.5, 0, 230, 368, 9, 246 }, North = { 420, 0, 177.5, 432, 9, 180 }, South = { 406, 0, 298, 418, 9, 300.5 } },
			adds = { { "ApacheKnife", 380, 0.15, 238, "E" }, { "ApacheKnife", 426, 0.15, 186, "S" }, { "ApacheGunman", 412, 0.15, 293, "N" } },
		},
	}

	local function marker(parent, name, cf, size, color)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Transparency = 1
		p.Size = size or Vector3.new(2, 0.2, 2)
		p.CFrame = cf
		p.Color = color or Color3.fromRGB(255, 200, 60)
		p.Material = Enum.Material.SmoothPlastic
		p.Parent = parent
		return p
	end
	local function folder(parent, name)
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
		return f
	end

	local function build(floorAt, roster)
		floorAt = floorAt or function(_, _, y) return y end
		local root = Instance.new("Folder")
		root.Name = "NPCMarkers"

		local spawns = folder(root, "Spawns")
		local count = {}
		for _, s in ipairs(SPAWNS) do
			local npc, x, y, z, face, behaviour, extra = s[1], s[2], s[3], s[4], s[5], s[6], s[7] or {}
			count[npc] = (count[npc] or 0) + 1
			local fy = floorAt(x, z, y)
			local m = marker(spawns, string.format("%s_%02d", npc, count[npc]), CFrame.new(x, fy + 0.1, z) * CFrame.Angles(0, YAW[face], 0))
			m:SetAttribute("NPCType", npc)
			m:SetAttribute("Behaviour", behaviour)
			if roster and roster[npc] then m:SetAttribute("Category", roster[npc].category) end
			if extra.radius then m:SetAttribute("WanderRadius", extra.radius) end
			if extra.gang then m:SetAttribute("Gang", extra.gang) end
			m:AddTag("LiegeNPCSpawn")
		end

		local routes = folder(root, "PatrolRoutes")
		for name, r in pairs(ROUTES) do
			local f = folder(routes, name)
			f:SetAttribute("NPCType", r.npc)
			f:SetAttribute("Loop", r.loop)
			for i, p in ipairs(r.points) do
				local nxt = r.points[i + 1] or (r.loop and r.points[1]) or r.points[i - 1]
				local here = Vector3.new(p[1], floorAt(p[1], p[3], p[2]) + 0.1, p[3])
				local look = Vector3.new(nxt[1], here.Y, nxt[3])
				local m = marker(f, string.format("P%02d", i), CFrame.new(here, look), nil, Color3.fromRGB(80, 160, 255))
				m:SetAttribute("Route", name)
				m:SetAttribute("Index", i)
				m:AddTag("LiegePatrolPoint")
			end
			-- one patrolling NPC per route, spawned at the first waypoint
			local p1 = r.points[1]
			local fy = floorAt(p1[1], p1[3], p1[2])
			count[r.npc] = (count[r.npc] or 0) + 1
			local m = marker(spawns, string.format("%s_%02d", r.npc, count[r.npc]), f:FindFirstChild("P01").CFrame)
			m:SetAttribute("NPCType", r.npc)
			m:SetAttribute("Behaviour", "Patrol")
			m:SetAttribute("Route", name)
			if roster and roster[r.npc] then m:SetAttribute("Category", roster[r.npc].category) end
			m:AddTag("LiegeNPCSpawn")
		end

		local arenas = folder(root, "BossArenas")
		for name, a in pairs(ARENAS) do
			local f = folder(arenas, name)
			f:SetAttribute("Boss", a.boss)
			f:SetAttribute("Place", a.name)
			local b = a.bounds
			local bounds = marker(f, "Bounds", CFrame.new((b[1] + b[4]) / 2, (b[2] + b[5]) / 2, (b[3] + b[6]) / 2),
				Vector3.new(b[4] - b[1], b[5] - b[2], b[6] - b[3]), Color3.fromRGB(255, 60, 60))
			bounds:AddTag("LiegeBossArena")
			local sp = a.spawn
			local bs = marker(f, "BossSpawn", CFrame.new(sp[1], floorAt(sp[1], sp[3], sp[2]) + 0.1, sp[3]) * CFrame.Angles(0, YAW[sp[4]], 0))
			bs:SetAttribute("NPCType", a.boss)
			local en = a.entry
			marker(f, "PlayerEntry", CFrame.new(en[1], floorAt(en[1], en[3], en[2]) + 0.1, en[3]) * CFrame.Angles(0, YAW[en[4]], 0), nil, Color3.fromRGB(60, 255, 120))
			local doors = folder(f, "Barriers")
			for dn, d in pairs(a.doors) do
				local p = marker(doors, dn, CFrame.new((d[1] + d[4]) / 2, (d[2] + d[5]) / 2, (d[3] + d[6]) / 2),
					Vector3.new(d[4] - d[1], d[5] - d[2], d[6] - d[3]), Color3.fromRGB(255, 60, 60))
				p:SetAttribute("Barrier", true)
			end
			if a.adds then
				local adds = folder(f, "Reinforcements")
				for i, ad in ipairs(a.adds) do
					local p = marker(adds, string.format("%s_%02d", ad[1], i), CFrame.new(ad[2], floorAt(ad[2], ad[4], ad[3]) + 0.1, ad[4]) * CFrame.Angles(0, YAW[ad[5]], 0))
					p:SetAttribute("NPCType", ad[1])
				end
			end
		end
		return root
	end

	return { spawns = SPAWNS, routes = ROUTES, arenas = ARENAS, build = build, yaw = YAW }
end
