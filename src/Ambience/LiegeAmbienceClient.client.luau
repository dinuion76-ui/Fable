--!nocheck
--[[
	Liège ambience (client, RunContext = Client).  Purely cosmetic and local to each player:
	  - a colour grade that eases in when the camera enters a building (Ambience.InteriorZones)
	  - flicker on forge, furnace and hearth lights (PointLights tagged LiegeFire)

	Switch either off with the InteriorGrading / FireFlicker attributes on the Ambience folder.
]]
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local ambience = script.Parent
local root = ambience.Parent
local Core = require(ambience:WaitForChild("AmbienceCore"))
local zones = ambience:WaitForChild("InteriorZones")

local grade = Instance.new("ColorCorrectionEffect")
grade.Name = "LiegeInteriorGrade"
grade.Parent = Lighting

local target = Core.gradeOf(nil)
local current = Core.gradeOf(nil)
local clock, sinceCheck = 0, 0
local connection

local function shutdown()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	grade:Destroy()
end

connection = RunService.Heartbeat:Connect(function(dt)
	if not ambience:IsDescendantOf(workspace) then
		shutdown()
		return
	end
	clock += dt
	sinceCheck += dt

	if sinceCheck >= 0.12 then
		sinceCheck = 0
		local camera = workspace.CurrentCamera
		local zone = nil
		if camera and ambience:GetAttribute("InteriorGrading") ~= false then
			zone = Core.zoneAt(zones, camera.CFrame.Position)
		end
		target = Core.gradeOf(zone)

		if ambience:GetAttribute("FireFlicker") ~= false then
			for i, light in ipairs(CollectionService:GetTagged(Core.TAG_FIRE)) do
				if light:IsDescendantOf(root) then
					local base = light:GetAttribute("BaseBrightness") or 1.5
					light.Brightness = base * (1 + 0.45 * math.noise(clock * 2.2, i * 7.3))
				end
			end
		end
	end

	local a = 1 - math.exp(-dt * 5)
	current.Brightness += (target.Brightness - current.Brightness) * a
	current.Contrast += (target.Contrast - current.Contrast) * a
	current.Saturation += (target.Saturation - current.Saturation) * a
	for i = 1, 3 do
		current.Tint[i] += (target.Tint[i] - current.Tint[i]) * a
	end
	grade.Brightness = current.Brightness
	grade.Contrast = current.Contrast
	grade.Saturation = current.Saturation
	grade.TintColor = Color3.fromRGB(current.Tint[1], current.Tint[2], current.Tint[3])
end)

script.Destroying:Connect(shutdown)
