local ssu = require "::/gui/main/stylesheetutil.lua"

function data()
	local result = {}

	local a = ssu.makeAdder(result)

	-- Layouts returned by a recipe shrink to their content by default.
	-- Make our full-screen wrapper fill the screen, so the compass can be positioned on it.
	a("R::CelebrationsContainer > FloatingLayout", {
		gravity = { -1, -1 },
	})

	-- Make the strip's inner layout fill the strip, so the letters can be spread across it.
	a("R::DkCompass FloatingLayout", {
		gravity = { -1, -1 },
	})

	-- Game bar version: spaced like the base game's Earnings / Transported entries.
	a("R::DkCompassGameBarPlugin", {
		gravity = { 0.5, 0.5 },
	})
	a("R::DkCompassGameBarPlugin BoxLayout", {
		innerSpacing = { 8, 0 },
		outerSpacing = { 14, 0 },
	})

	return result
end
