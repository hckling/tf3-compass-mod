function data()
	return {
		type = "react-plugin ::GameBarInfoDisplayExtension",
		data = {
			filePath = "dk_compass::/gui/dk_compass/compass.script@DkCompassGameBarPlugin",
			priority = 0, -- the base game's plugins use negative priorities, so this is appended to their right
		}
	}
end
