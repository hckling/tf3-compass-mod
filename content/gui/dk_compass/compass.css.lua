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

	-- Rounded strip background: the same nine-patch the game uses for its callouts.
	-- It is tinted with backgroundColor1, which the script sets.
	a("!dk-compass-strip", {
		backgroundImage1 = {
			fileName = "::/gui/builtin/button/default_surface.tga",
			horizontal = { 0, 9, 21, 30 },
			vertical = { 0, 9, 21, 30 },
		},
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
