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

	-- Fixed text width per text style and font size setting (headline font: 16 / 19 / 21 px),
	-- wide enough for the longest text: "Northwest", "Northwest 359°" and "359°".
	-- The rule without a font class is the fallback, sized for the large font.
	local widths = {
		{ font = nil,             direction = 144, both = 204, degrees = 54 },
		{ font = "!font-small ",  direction = 112, both = 160, degrees = 43 },
		{ font = "!font-medium ", direction = 132, both = 188, degrees = 50 },
		{ font = "!font-large ",  direction = 144, both = 204, degrees = 54 },
	}
	for _, w in ipairs(widths) do
		local prefix = w.font or ""
		a(prefix .. "!dk-gamebar-direction", { size = { w.direction, -1 } })
		a(prefix .. "!dk-gamebar-both", { size = { w.both, -1 } })
		a(prefix .. "!dk-gamebar-degrees", { size = { w.degrees, -1 } })
	end

	return result
end
