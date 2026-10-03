local builtin = ug_require "::/gui/main/builtin.lua" as Builtin
local react = ug_require "::/gui/main/react.lua" as React
local styleutil = ug_require "::/gui/main/styleutil.tl" as StyleUtil
local celebration_react_util = ug_require "::/game_mechanics/celebrations/celebration_react_util.tl" as CelebrationReactUtil
local game_bar_widgets = ug_require "::/gui/game_bar/game_bar_widgets.tl" as GameBarWidgets

local MOD_ID = "dk_compass"

-- Fixed settings. Position and size come from the mod settings (see mod.json params).
-- Sizes are for "Medium" and get multiplied by the chosen size's scale.
local config = {
	width = 200,          -- strip width in pixels
	height = 36,          -- strip height in pixels
	fontSize = 16,        -- size of the direction letters
	highlightFontSize = 24, -- size of the highlighted letter
	margin = 10,          -- distance from the screen edge in pixels
	borderWidth = 1,      -- strip border in pixels
	markerWidth = 3,      -- centre marker (tick at the top of the strip) in pixels
	markerHeight = 4,
	visibleSpanDeg = 120, -- how many degrees of the horizon the strip shows
	edgeInset = 0.06,     -- keeps letters this fraction of the strip away from its ends
	northOffsetDeg = 0,   -- adjust if the game's "north" turns out not to be world +y
	backgroundColor = { 0.07, 0.09, 0.12, 0.85 },
	borderColor = { 1.0, 1.0, 1.0, 0.25 },
	textColor = { 0.85, 0.85, 0.85, 1.0 },
	highlightColor = { 1.0, 0.85, 0.2, 1.0 },
	debug = false,        -- log output to stdout.txt
}

-- Options of the "position" mod param, in the same order as in mod.json.
-- h: 0 = left, 0.5 = centre, 1 = right; v: 0 = top, 0.5 = middle, 1 = bottom
local POSITIONS : {{number}} = {
	{ 0.0, 0.0 }, -- Top left
	{ 0.5, 0.0 }, -- Top centre
	{ 1.0, 0.0 }, -- Top right
	{ 0.0, 0.5 }, -- Middle left
	{ 1.0, 0.5 }, -- Middle right
	{ 0.0, 1.0 }, -- Bottom left
	{ 0.5, 1.0 }, -- Bottom centre
	{ 1.0, 1.0 }, -- Bottom right
}
local POSITION_GAME_BAR = #POSITIONS -- the last option, "Game bar", comes right after the screen positions
local DEFAULT_POSITION = 2

-- Options of the "size" mod param, in the same order as in mod.json.
local SCALES : {number} = { 0.75, 1.0, 1.5, 2.0 }
local DEFAULT_SIZE = 1

-- Options of the "gameBarText" mod param, in the same order as in mod.json.
local GAME_BAR_TEXT_DIRECTION = 0
local GAME_BAR_TEXT_BOTH = 1
local GAME_BAR_TEXT_DEGREES = 2

local record Settings
	inGameBar : boolean
	posH : number
	posV : number
	scale : number
	gameBarText : integer
end

-- Reads the chosen mod settings. The game stores the 1-based index of the chosen option
-- (even though "defaultIndex" in mod.json is 0-based); we convert to 0-based here.
-- Falls back to the defaults if the params can't be read.
local function loadSettings() : Settings
	local positionIndex = DEFAULT_POSITION
	local sizeIndex = DEFAULT_SIZE
	local gameBarText = GAME_BAR_TEXT_DIRECTION
	local ok, allParams = pcall(function() : {string : table}
		return api.engine.config.getModParams()
	end)
	if ok and allParams ~= nil and allParams[MOD_ID] ~= nil then
		local params = allParams[MOD_ID] as {string : integer}
		local position = params.position and params.position - 1
		local size = params.size and params.size - 1
		local text = params.gameBarText and params.gameBarText - 1
		if position ~= nil and position >= 0 and position <= POSITION_GAME_BAR then
			positionIndex = position
		end
		if size ~= nil and SCALES[size + 1] ~= nil then
			sizeIndex = size
		end
		if text ~= nil and text >= 0 and text <= GAME_BAR_TEXT_DEGREES then
			gameBarText = text
		end
	end
	print("[dk_compass] settings (0-based): position = " .. tostring(positionIndex) .. ", size = " .. tostring(sizeIndex)
		.. ", gameBarText = " .. tostring(gameBarText)
		.. (ok and "" or " (could not read mod params, using defaults)"))
	local pos = POSITIONS[positionIndex + 1] or { 0.0, 0.0 }
	return {
		inGameBar = positionIndex == POSITION_GAME_BAR,
		posH = pos[1],
		posV = pos[2],
		scale = SCALES[sizeIndex + 1],
		gameBarText = gameBarText,
	}
end

local record Label
	text : string
	angle : number
end

local LABELS : {Label} = {
	{ text = "N", angle = 0 },
	{ text = "NE", angle = 45 },
	{ text = "E", angle = 90 },
	{ text = "SE", angle = 135 },
	{ text = "S", angle = 180 },
	{ text = "SW", angle = 225 },
	{ text = "W", angle = 270 },
	{ text = "NW", angle = 315 },
}

-- Full direction names for the game bar, every 45 degrees starting at north.
local DIRECTION_NAMES : {string} = {
	"North", "North-east", "East", "South-east", "South", "South-west", "West", "North-west",
}

-- Width of the game bar text per "gameBarText" option, so the bar doesn't shift
-- when the text gets longer or shorter while turning the camera.
local GAME_BAR_TEXT_WIDTHS : {integer} = { 110, 160, 50 }

-- atan2 that works on any Lua version (two-argument math.atan is Lua 5.3+ only)
local function atan2(y : number, x : number) : number
	if x > 0 then return math.atan(y / x) end
	if x < 0 then return math.atan(y / x) + (y >= 0 and math.pi or -math.pi) end
	if y > 0 then return math.pi / 2 end
	if y < 0 then return -math.pi / 2 end
	return 0
end

-- Wraps an angle in degrees into the range (-180, 180]
local function wrap180(a : number) : number
	a = a % 360
	if a > 180 then
		a = a - 360
	end
	return a
end

-- Camera heading in degrees, clockwise from north (world +y).
-- Returns nil when looking almost straight down, where the heading is unstable.
local function getHeadingDeg() : number
	local eye = api.gui.camera.getEye()
	local center = api.gui.camera.getCenter()
	local dx, dy, dz = center.x - eye.x, center.y - eye.y, center.z - eye.z
	local horizontalSq = dx * dx + dy * dy
	if horizontalSq < 1e-4 * (horizontalSq + dz * dz) then
		return nil
	end
	return (math.deg(atan2(dx, dy)) - config.northOffsetDeg) % 360
end

-- Hook: camera heading in whole degrees, updated every frame. Only re-renders when it changes.
local function useHeading() : ReactStateT<integer>
	local heading : ReactStateT<integer> = react.useState(0)
	local stepCount : ReactRefT<integer> = react.useRef(0)

	react.onStep(function()
		if heading:hasExpired() then
			return
		end
		local h = getHeadingDeg()
		if config.debug and stepCount:get() % 300 == 0 then
			print("[dk_compass] step " .. tostring(stepCount:get()) .. ", heading = " .. tostring(h))
		end
		stepCount:set(stepCount:get() + 1)
		if h == nil then
			return
		end
		local rounded = math.floor(h + 0.5) % 360
		if rounded ~= heading:old() then
			heading:set(rounded)
		end
	end)

	return heading
end

local DkCompass = react.RegisterRecipe("DkCompass", function(settings : Settings) : TreeNodeId
	local scale = settings.scale
	local heading = useHeading()

	-- clicks pass through the compass to the map below
	react.setMouseTransparent(true)

	if config.debug then
		print("[dk_compass] render, heading = " .. tostring(heading:old()))
	end

	-- styles are created fresh on every render, like the base game does
	local function px(value : number) : integer
		return math.max(1, math.floor(value * scale + 0.5))
	end
	local border = px(config.borderWidth)
	local stripStyle = styleutil.makeStyle{
		size = { px(config.width), px(config.height) },
		backgroundColor = config.backgroundColor,
		borderColor = config.borderColor,
		borderWidth = { border, border, border, border },
	}
	local marginStyle = api.gui.StyleSheet.new()
	marginStyle.padding = api.type.Vec4f.new(config.margin, config.margin, config.margin, config.margin)

	-- the label closest to the centre of the strip is highlighted
	local halfSpan = config.visibleSpanDeg / 2
	local closestText : string = nil
	local closestDist = 360
	for _, label in ipairs(LABELS) do
		local dist = math.abs(wrap180(label.angle - heading:old()))
		if dist < closestDist then
			closestDist = dist
			closestText = label.text
		end
	end

	local children : {TreeNodeId} = {}
	for _, label in ipairs(LABELS) do
		local rel = wrap180(label.angle - heading:old())
		if math.abs(rel) < halfSpan then
			local isClosest = label.text == closestText
			children[#children + 1] = builtin.FloatingLayoutChild{
				localKey = label.text,
				h = 0.5 + (1 - 2 * config.edgeInset) * rel / (2 * halfSpan),
				v = 0.5,
				item = builtin.TextView{
					meta = {
						class = isClosest and "font-scale-headline" or nil,
						styleSheet = styleutil.makeStyle{
							color = isClosest and config.highlightColor or config.textColor,
							fontSize = px(isClosest and config.highlightFontSize or config.fontSize),
						},
					},
					text = label.text,
				},
			}
		end
	end

	-- centre marker: a small yellow tick hanging from the top edge of the strip
	children[#children + 1] = builtin.FloatingLayoutChild{
		localKey = "marker",
		h = 0.5,
		v = 0.0,
		item = builtin.Component{
			meta = {
				styleSheet = styleutil.makeStyle{
					size = { px(config.markerWidth), px(config.markerHeight) },
					backgroundColor = config.highlightColor,
				},
			},
		},
	}

	local rootChildren : {TreeNodeId} = {}
	rootChildren[#rootChildren + 1] = builtin.Component{
		meta = { styleSheet = marginStyle },
		layout = builtin.BoxLayout{
			child = builtin.Component{
				meta = { styleSheet = stripStyle },
				layout = builtin.FloatingLayout{ children = children },
			},
		},
	}

	-- a recipe must return a layout at its top level, not a component
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Vertical,
		children = rootChildren,
	}
end)

-- The celebrations overlay is a full-screen, click-through layer inside the main HUD.
-- We wrap it in a full-screen FloatingLayout so the compass can be placed anywhere
-- on screen according to the "position" mod setting.
local CelebrationsContainerWithCompass = react.RegisterRecipe("CelebrationsContainer", function(param : CelebrationsContainerParams) : TreeNodeId
	react.setMouseTransparent(true)
	if config.debug then
		print("[dk_compass] CelebrationsContainer wrapper render")
	end
	local settings : ReactRefT<Settings> = react.useRefLazy(loadSettings)

	local children : {TreeNodeId} = {
		builtin.FloatingLayoutChild{
			localKey = "celebrations",
			h = -1,
			v = -1,
			item = react.CallOriginalRecipe(celebration_react_util.CelebrationsContainer, param),
		},
	}
	-- in "Game bar" mode the compass is shown by DkCompassGameBarPlugin instead
	if not settings:get().inGameBar then
		children[#children + 1] = builtin.FloatingLayoutChild{
			localKey = "dk-compass",
			h = settings:get().posH,
			v = settings:get().posV,
			item = DkCompass(settings:get()),
		}
	end

	return builtin.FloatingLayout{ children = children }
end)

-- Text version of the compass for the info row of the bottom game bar (next to Earnings).
-- Registered through compass_gamebar.res.lua; only shown when the position is "Game bar".
local DkCompassGameBarPlugin = react.RegisterPluginRecipe(game_bar_widgets.GameBarInfoDisplayExtension, "DkCompassGameBarPlugin", function() : TreeNodeId
	local settings : ReactRefT<Settings> = react.useRefLazy(loadSettings)
	if not settings:get().inGameBar then
		return nil
	end

	local heading = useHeading()
	local degrees = heading:old()
	local name = DIRECTION_NAMES[(math.floor((degrees + 22.5) / 45) % 8) + 1]
	local mode = settings:get().gameBarText
	local text : string
	if mode == GAME_BAR_TEXT_DEGREES then
		text = tostring(degrees) .. "°"
	elseif mode == GAME_BAR_TEXT_BOTH then
		text = name .. " " .. tostring(degrees) .. "°"
	else
		text = name
	end

	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			builtin.Component{
				meta = {
					tooltip = "Camera direction",
					styleSheet = styleutil.makeStyle{ size = { GAME_BAR_TEXT_WIDTHS[mode + 1], -1 } },
				},
				layout = builtin.BoxLayout{
					orientation = builtin.type.Orientation.Horizontal,
					children = {
						builtin.TextView{
							meta = { class = "font-scale-headline" },
							text = text,
						},
					},
				},
			},
		},
	}
end)

local function doReplaceFn(replacementApi : ReactReplacementApi)
	replacementApi.ReplaceRecipe(celebration_react_util.CelebrationsContainer, CelebrationsContainerWithCompass)
end

local result = {
	doReplaceFn = doReplaceFn,
	DkCompassGameBarPlugin = DkCompassGameBarPlugin,
}

return result
