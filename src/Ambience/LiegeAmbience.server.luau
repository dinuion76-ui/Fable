--!nocheck
--[[
	Liège ambience (server).  Applies the map's lighting mood as soon as the map is in Workspace,
	optionally runs a day/night cycle, lights the gas lamps after dark, and puts Lighting back
	the way it found it when the map is removed.

	Configure it with the attributes on the Ambience folder (see AmbienceCore.start).
]]
local ambience = script.Parent
local Core = require(ambience:WaitForChild("AmbienceCore"))

local controller = Core.start(ambience)
if not controller then return end

local alive = true
local function stop()
	if not alive then return end
	alive = false
	controller.stop()
end

-- Map unloaded (round-based games): hand Lighting back.
ambience.AncestryChanged:Connect(function()
	if not ambience:IsDescendantOf(workspace) then stop() end
end)
ambience.Destroying:Connect(stop)

while alive do
	local dt = task.wait(1)
	if not alive then break end
	if ambience:GetAttribute("ManageLighting") == false then
		stop()
		break
	end
	controller.step(dt)
end
