function widget:GetInfo()
	return {name = "Verification Chili chat observer", layer = -1000001, enabled = true}
end

local lastWriting

function widget:Update()
	if not WG.Chili or Spring.GetGameFrame() < 0 then
		return
	end
	local focused = WG.Chili.Screen0.focusedControl
	local writing = not not (focused and focused.visible and focused.classname == "editbox")
	if writing ~= lastWriting then
		lastWriting = writing
		Spring.Echo("[controls] chat writing=" .. (writing and "1" or "0"))
	end
end
