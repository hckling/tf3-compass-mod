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

	-- The compass on the callout overlay is only for the views where the game hides its
	-- normal interface: follow view (action-follow) and free camera (action-camera).
	-- (The callout overlay's own rule already makes its FloatingLayouts fill the screen.)
	a("!dk-camera-view", {
		visibility = "none",
	})
	a([[!action-follow !dk-camera-view,
		!action-camera !dk-camera-view]], {
		visibility = "visible",
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
	-- Only the outer layout gets the spacing: on the inner layout (inside the fixed-width
	-- text box below) it would eat 2 x 14 px of the box and cut the text off.
	a("R::DkCompassGameBarPlugin > BoxLayout", {
		innerSpacing = { 8, 0 },
		outerSpacing = { 14, 0 },
	})

	-- Fixed text width per text style and font size setting (headline font: 16 / 19 / 21 px),
	-- wide enough for the longest text: "Northwest", "Northwest 359°", "359°", "NW", "NW 359°".
	-- The rule without a font class is the fallback, sized for the large font.
	local widths = {
		{ font = nil,             direction = 116, both = 176, degrees = 56, directionCompact = 38, bothCompact = 84 },
		{ font = "!font-small ",  direction = 84,  both = 132, degrees = 44, directionCompact = 30, bothCompact = 66 },
		{ font = "!font-medium ", direction = 104, both = 160, degrees = 51, directionCompact = 35, bothCompact = 76 },
		{ font = "!font-large ",  direction = 116, both = 176, degrees = 56, directionCompact = 38, bothCompact = 84 },
	}
	for _, w in ipairs(widths) do
		local prefix = w.font or ""
		a(prefix .. "!dk-gamebar-direction", { size = { w.direction, -1 } })
		a(prefix .. "!dk-gamebar-both", { size = { w.both, -1 } })
		a(prefix .. "!dk-gamebar-degrees", { size = { w.degrees, -1 } })
		a(prefix .. "!dk-gamebar-direction-compact", { size = { w.directionCompact, -1 } })
		a(prefix .. "!dk-gamebar-both-compact", { size = { w.bothCompact, -1 } })
	end

	return result
end
