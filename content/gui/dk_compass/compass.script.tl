local builtin = ug_require "::/gui/main/builtin.lua" as Builtin
local react = ug_require "::/gui/main/react.lua" as React
local styleutil = ug_require "::/gui/main/styleutil.tl" as StyleUtil
local celebration_react_util = ug_require "::/game_mechanics/celebrations/celebration_react_util.tl" as CelebrationReactUtil
local game_bar_widgets = ug_require "::/gui/game_bar/game_bar_widgets.tl" as GameBarWidgets
local callout_container = ug_require "::/gui/main/callout_container.tl" as RecipeWithApi0<CalloutApi>

local MOD_ID = "dk_compass"

-- Fixed settings. Everything players can change comes from the mod settings (see mod.json params).
-- Sizes are for "Medium" and get multiplied by the chosen size's scale.
local config = {
	width = 200,          -- strip width in pixels
	height = 36,          -- strip height in pixels (letters row)
	degreesRowHeight = 14, -- extra height for the heading number under the letters
	degreesOnlyWidth = 90, -- strip width when it only shows the heading number
	fontSize = 16,        -- size of the direction letters
	highlightFontSize = 24, -- size of the highlighted letter
	degreesFontSize = 12, -- size of the heading number under the letters
	margin = 10,          -- distance from the screen edge in pixels
	markerWidth = 3,      -- center marker (tick at the top of the strip) in pixels
	markerHeight = 4,
	visibleSpanDeg = 120, -- how many degrees of the horizon the strip shows
	edgeInset = 0.06,     -- keeps letters this fraction of the strip away from its ends
	highlightStickinessDeg = 5, -- the highlighted letter changes this many degrees past the boundary
	lockIcon = "::/gui/builtin/window/icons/lock.tga", -- shown while the compass follows a vehicle
	lockIconSize = 14,    -- size of the lock on the screen strip
	lockColumnWidth = 22, -- extra width of the screen strip while it shows the lock
	-- Where the sun stands at noon, as a map heading (degrees clockwise from the top of the minimap),
	-- measured in game. During the day the sun moves counter-clockwise on the map, like in the
	-- southern hemisphere, so the "North: Sun" setting turns the compass so that the noon sun
	-- reads as north. The sun then rises in the east (south of east in summer, Nov-Jan).
	sunNoonMapHeadingDeg = 100,
	backgroundColor = { 40 / 255, 47 / 255, 54 / 255, 1.0 }, -- same as the game's HUD buttons
	textColor = { 0.85, 0.85, 0.85, 1.0 },
	highlightColor = { 1.0, 0.85, 0.2, 1.0 },
	debug = false,        -- log output to stdout.txt
}

-- Options of the "gameBar" mod param (0-based, same order as in mod.json).
local GAME_BAR_OFF = 0
local GAME_BAR_DIRECTION = 1
local GAME_BAR_DEGREES = 2
local GAME_BAR_BOTH = 3

-- Options of the "screenCompass" mod param.
local SCREEN_OFF = 0
local SCREEN_LETTERS = 1
local SCREEN_LETTERS_AND_DEGREES = 2
local SCREEN_DEGREES = 3

-- The layers button in the top left corner (measured in game UI pixels from the screen edge).
local LAYERS_BUTTON_TOP = 12
local LAYERS_BUTTON_CENTER_Y = 32

-- Options of the "compassPosition" mod param, in the same order as in mod.json.
-- h: 0 = left, 0.5 = center, 1 = right; v: 0 = top, 0.5 = middle, 1 = bottom
-- dx, dy: extra offset in pixels to keep clear of the game's own HUD elements.
--         Positive moves right/down, negative moves left/up.
-- There are no top right and middle right positions: the game opens its vehicle, line, station
-- and town windows along the right edge, from the top down to just above the game bar.
local POSITIONS : {{number}} = {
	{ 0.0, 0.0, 56, 0 }, -- Top left (right of the layers button, vertically aligned with it)
	{ 0.5, 0.0, 0, 56 },  -- Top center (below the notification icons, which fill the top center)
	{ 0.0, 0.5, 56, 0 }, -- Middle left (right of the layers menu column)
	{ 0.0, 1.0, 0, -90 }, -- Bottom left (above the Account panel of the game bar)
	{ 1.0, 1.0, 0, -74 }, -- Bottom right (above the right part of the game bar, below the windows)
}
local POSITION_TOP_LEFT = 0
local DEFAULT_POSITION = 1 -- Top center: never covered by the game's windows

-- Earlier versions stored the position in other lists: "position" (revision 1-2: top left,
-- top right, middle left, middle right, bottom left, bottom right, game bar) and "screenPosition"
-- (revision 3-5: the same six, then top center). Maps their 1-based option to the new 0-based
-- index; top right and middle right (nil) become the default.
local OLD_POSITION_MAP : {integer : integer} = { [1] = 0, [3] = 2, [5] = 3, [6] = 4, [7] = 1 }

-- Options of the "size" mod param.
local SCALES : {number} = { 0.75, 1.0, 1.5 }
local DEFAULT_SIZE = 1

-- Revision 1 and 2 had a single "position" param (six screen positions, then "Game bar")
-- and a "gameBarText" param (Direction, Direction and degrees, Degrees).
local OLD_POSITION_COUNT = 7
local OLD_GAME_BAR_TEXT : {integer} = { GAME_BAR_DIRECTION, GAME_BAR_BOTH, GAME_BAR_DEGREES }

local record Settings
	gameBar : integer
	compactNames : boolean
	screenCompass : integer
	posH : number
	posV : number
	offsetX : number
	offsetY : number
	alignWithLayersButton : boolean
	scale : number
	northOffsetDeg : number
	cameraViews : boolean
	vehicleHeading : boolean -- the "Follow view shows" setting
	isCameraView : boolean   -- the compass instance for free camera and follow view
end

-- Reads the chosen mod settings. The game stores the 1-based index of the chosen option
-- (even though "defaultIndex" in mod.json is 0-based); we convert to 0-based here.
-- Missing or invalid values fall back to the defaults.
local function loadSettings() : Settings
	local ok, allParams = pcall(function() : {string : table}
		return api.engine.config.getModParams()
	end)
	local params : {string : integer} = {}
	if ok and allParams ~= nil and allParams[MOD_ID] ~= nil then
		params = allParams[MOD_ID] as {string : integer}
	end

	-- 0-based option index of a param, or nil if it is missing or out of range
	local function option(key : string, count : integer) : integer
		local value = params[key]
		if value == nil or value < 1 or value > count then
			return nil
		end
		return value - 1
	end

	local gameBar = GAME_BAR_DIRECTION
	local screenCompass = SCREEN_OFF
	local positionIndex = DEFAULT_POSITION

	-- Carry over the settings of revision 1 and 2 until the new settings have been saved.
	local oldPosition = option("position", OLD_POSITION_COUNT)
	local oldText = option("gameBarText", #OLD_GAME_BAR_TEXT)
	if params["screenCompass"] == nil and oldPosition ~= nil and oldPosition < 6 then
		-- the strip was shown at a screen position, and the game bar text was off
		screenCompass = SCREEN_LETTERS
		positionIndex = OLD_POSITION_MAP[oldPosition + 1] or DEFAULT_POSITION
		gameBar = GAME_BAR_OFF
	end
	-- revision 3-5: "screenPosition"
	local oldScreenPosition = option("screenPosition", 7)
	if params["compassPosition"] == nil and oldScreenPosition ~= nil then
		positionIndex = OLD_POSITION_MAP[oldScreenPosition + 1] or DEFAULT_POSITION
	end
	if params["gameBar"] == nil and oldText ~= nil and gameBar ~= GAME_BAR_OFF then
		gameBar = OLD_GAME_BAR_TEXT[oldText + 1]
	end

	gameBar = option("gameBar", 4) or gameBar
	screenCompass = option("screenCompass", 4) or screenCompass
	positionIndex = option("compassPosition", #POSITIONS) or positionIndex
	local sizeIndex = option("size", #SCALES) or DEFAULT_SIZE
	local compactNames = option("gameBarNames", 2) == 1
	local sunNorth = option("north", 2) == 1
	local cameraViews = option("cameraViews", 2) == 1
	local vehicleHeading = option("followHeading", 2) == 1

	local okEnv, sunRotation = pcall(function() : number
		return api.gui.rendering.getEnvironment().atmosphere.sunRotation
	end)
	print("[dk_compass] settings (0-based): gameBar = " .. tostring(gameBar)
		.. ", compactNames = " .. tostring(compactNames)
		.. ", screenCompass = " .. tostring(screenCompass)
		.. ", compassPosition = " .. tostring(positionIndex)
		.. ", size = " .. tostring(sizeIndex)
		.. ", sunNorth = " .. tostring(sunNorth)
		.. ", cameraViews = " .. tostring(cameraViews)
		.. ", vehicleHeading = " .. tostring(vehicleHeading)
		.. ", environment sunRotation = " .. (okEnv and tostring(sunRotation) or "n/a")
		.. (ok and "" or " (could not read mod params, using defaults)"))

	local pos = POSITIONS[positionIndex + 1]
	return {
		gameBar = gameBar,
		compactNames = compactNames,
		screenCompass = screenCompass,
		posH = pos[1],
		posV = pos[2],
		offsetX = pos[3],
		offsetY = pos[4],
		alignWithLayersButton = positionIndex == POSITION_TOP_LEFT,
		scale = SCALES[sizeIndex + 1],
		northOffsetDeg = sunNorth and config.sunNoonMapHeadingDeg or 0,
		cameraViews = cameraViews,
		vehicleHeading = vehicleHeading,
		isCameraView = false,
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
	"North", "Northeast", "East", "Southeast", "South", "Southwest", "West", "Northwest",
}

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

-- Heading of a direction vector in degrees, clockwise from north (world +y, the top of the
-- minimap, turned by northOffsetDeg). Returns nil when the vector points almost straight up or down.
local function headingOf(dx : number, dy : number, dz : number, northOffsetDeg : number) : number
	local horizontalSq = dx * dx + dy * dy
	if horizontalSq < 1e-4 * (horizontalSq + dz * dz) then
		return nil
	end
	return (math.deg(atan2(dx, dy)) - northOffsetDeg) % 360
end

-- Camera heading in degrees. Returns nil when looking almost straight down.
local function getCameraHeadingDeg(northOffsetDeg : number) : number
	local eye = api.gui.camera.getEye()
	local center = api.gui.camera.getCenter()
	return headingOf(center.x - eye.x, center.y - eye.y, center.z - eye.z, northOffsetDeg)
end

-- Travel direction for follow view, measured from how the camera moves. The game's
-- api.gui.camera.getFollowEntity() only works when following was started from Lua (e.g. the line
-- manager); in the game's own follow view it returns -1.
-- While the camera follows a vehicle, one of the camera's two points is attached to the vehicle:
-- the center (look-at point) in follow view, the eye in cockpit view. The other one moves when
-- the player moves the camera (orbiting, looking around, zooming), and the chase camera of the
-- initial follow view turns along with the vehicle. Every few metres the movement of both points
-- is compared: if they moved the same way, that's the travel direction; if not, the one that
-- continues the last travel direction is used.
local TRAVEL_MIN_DISTANCE = 3   -- metres both points must move before a direction is measured
local TRAVEL_MAX_JUMP = 200     -- larger jumps (switching to another vehicle) start over
local TRAVEL_AGREE_DEG = 15     -- eye and center moving within this angle count as the same way
local TRAVEL_CONTINUE_DEG = 30  -- otherwise, a point within this angle of the last direction is used
local TRAVEL_STALE_DISTANCE = 50 -- one point this far with the other one still: start the measurement over
local TRAVEL_HOLD_STEPS = 300   -- without a measurement for this many steps (~5 s), use the camera again
local TRAVEL_SMOOTHING = 0.5    -- each measurement moves the shown direction this far towards the new value

-- Moves a heading part of the way towards a new measurement, to smooth out measuring noise.
local function blendHeading(old : number, new : number) : number
	if old == nil then
		return new
	end
	return (old + TRAVEL_SMOOTHING * wrap180(new - old)) % 360
end

local record TravelState
	cx : number          -- center and eye when the direction was last measured
	cy : number
	ex : number
	ey : number
	heading : number     -- last measured travel heading, nil if none
	stillSteps : integer -- steps without a measurement
end

-- Direction of the followed vehicle as reported by the game. Only works when the camera
-- follows via api.gui.camera.followEntity() (e.g. from the line or vehicle manager);
-- returns nil otherwise.
local function getFollowedVehicleHeadingDeg(northOffsetDeg : number) : number
	local ok, heading = pcall(function() : number
		local followed = api.gui.camera.getFollowEntity()
		local entity = followed and followed[1]
		if entity == nil or entity < 0 then
			return nil
		end
		local dir = api.engine.util.vehicle.getDirection(entity)
		if dir == nil then
			return nil
		end
		return headingOf(dir.x, dir.y, dir.z, northOffsetDeg)
	end)
	return ok and heading or nil
end

-- Updates the travel state with the current camera and returns the travel heading,
-- or nil if no travel could be measured recently.
local function updateTravelHeading(state : TravelState, northOffsetDeg : number) : number
	local c = api.gui.camera.getCenter()
	local e = api.gui.camera.getEye()
	if state.cx == nil then
		state.cx, state.cy, state.ex, state.ey, state.stillSteps = c.x, c.y, e.x, e.y, 0
		return nil
	end

	local dcx, dcy = c.x - state.cx, c.y - state.cy -- movement of the center since the anchor
	local dex, dey = e.x - state.ex, e.y - state.ey -- movement of the eye since the anchor
	local dcSq, deSq = dcx * dcx + dcy * dcy, dex * dex + dey * dey
	local minSq, jumpSq = TRAVEL_MIN_DISTANCE * TRAVEL_MIN_DISTANCE, TRAVEL_MAX_JUMP * TRAVEL_MAX_JUMP
	local measured = false

	if dcSq > jumpSq or deSq > jumpSq then
		-- jumped to another place or vehicle: start over
		state.heading = nil
		state.cx, state.cy, state.ex, state.ey = c.x, c.y, e.x, e.y
	elseif dcSq >= minSq and deSq >= minSq then
		-- Only decide once BOTH points moved far enough. The point moved by the player usually
		-- gets there much sooner; starting over at that moment would never let the point attached
		-- to the vehicle get far enough.
		local hc = headingOf(dcx, dcy, 0, northOffsetDeg)
		local he = headingOf(dex, dey, 0, northOffsetDeg)
		if math.abs(wrap180(hc - he)) <= TRAVEL_AGREE_DEG then
			-- eye and center moved the same way: that's the travel direction
			state.heading = blendHeading(state.heading, headingOf(dcx + dex, dcy + dey, 0, northOffsetDeg))
			measured = true
		elseif state.heading ~= nil then
			-- the player moves the camera: whichever point continues the last direction is
			-- the one attached to the vehicle (center in follow view, eye in cockpit view)
			local diffC = math.abs(wrap180(hc - state.heading))
			local diffE = math.abs(wrap180(he - state.heading))
			local best, bestDiff = hc, diffC
			if diffE < diffC then
				best, bestDiff = he, diffE
			end
			if bestDiff <= TRAVEL_CONTINUE_DEG then
				state.heading = blendHeading(state.heading, best)
				measured = true
			end
		end
		state.cx, state.cy, state.ex, state.ey = c.x, c.y, e.x, e.y
	elseif dcSq > TRAVEL_STALE_DISTANCE * TRAVEL_STALE_DISTANCE or deSq > TRAVEL_STALE_DISTANCE * TRAVEL_STALE_DISTANCE then
		-- one point moved far while the other hardly moved (e.g. orbiting a stopped vehicle): start over
		state.cx, state.cy, state.ex, state.ey = c.x, c.y, e.x, e.y
	end

	if measured then
		state.stillSteps = 0
	else
		state.stillSteps = state.stillSteps + 1
		if state.stillSteps > TRAVEL_HOLD_STEPS then
			state.heading = nil
		end
	end
	return state.heading
end

-- Hook: heading in whole degrees, updated every frame. Only re-renders when it changes.
-- With useFollowedVehicle, it shows the direction of the vehicle the camera follows when the game
-- reports one (pinned from the line or vehicle manager). With useTravel, it otherwise measures the
-- travel direction from the camera's movement (follow and cockpit view, where the game doesn't
-- report the vehicle). Without either, or when neither gives a direction, it shows the camera's.
-- Also returns whether the heading currently comes from a vehicle ("locked") rather than the camera.
local function useHeading(northOffsetDeg : number, useFollowedVehicle? : boolean, useTravel? : boolean) : ReactStateT<integer>, ReactStateT<boolean>
	local heading : ReactStateT<integer> = react.useState(0)
	local locked : ReactStateT<boolean> = react.useState(false)
	local stepCount : ReactRefT<integer> = react.useRef(0)
	local travel : ReactRefT<TravelState> = react.useRef({ stillSteps = 0 })

	react.onStep(function()
		if heading:hasExpired() then
			return
		end
		local h : number = nil
		if useFollowedVehicle then
			h = getFollowedVehicleHeadingDeg(northOffsetDeg)
		end
		if useTravel and h == nil then
			h = updateTravelHeading(travel:get(), northOffsetDeg)
		end
		local isLocked = h ~= nil
		if isLocked ~= locked:old() then
			locked:set(isLocked)
		end
		if h == nil then
			h = getCameraHeadingDeg(northOffsetDeg)
		end
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

	return heading, locked
end

-- Index (1-8) of the closest of the eight directions
local function directionIndex(degrees : integer) : integer
	return (math.floor((degrees + 22.5) / 45) % 8) + 1
end

local DkCompass = react.RegisterRecipe("DkCompass", function(settings : Settings) : TreeNodeId
	local scale = settings.scale
	-- a pinned vehicle's direction everywhere; the measured travel direction only in free camera / follow view
	local heading, locked = useHeading(settings.northOffsetDeg, settings.vehicleHeading, settings.isCameraView and settings.vehicleHeading)
	local degrees = heading:old()

	-- The highlighted direction only changes once the heading is clearly past the boundary
	-- between two directions, so it doesn't flicker when the heading is right in between.
	local highlightRef : ReactRefT<integer> = react.useRef(nil)
	local highlight = directionIndex(degrees)
	local previous = highlightRef:get()
	if previous ~= nil and previous ~= highlight
		and math.abs(wrap180(LABELS[previous].angle - degrees)) <= 22.5 + config.highlightStickinessDeg then
		highlight = previous
	end
	highlightRef:set(highlight)

	-- clicks pass through the compass to whatever is below it
	react.setMouseTransparent(true)

	local backgroundColor = config.backgroundColor
	local textColor = config.textColor
	local highlightColor = config.highlightColor

	if config.debug then
		print("[dk_compass] render, heading = " .. tostring(degrees))
	end

	local showLetters = settings.screenCompass == SCREEN_LETTERS or settings.screenCompass == SCREEN_LETTERS_AND_DEGREES
	local showDegreesRow = settings.screenCompass == SCREEN_LETTERS_AND_DEGREES

	-- styles are created fresh on every render, like the base game does
	local function px(value : number) : integer
		return math.max(1, math.floor(value * scale + 0.5))
	end
	local stripWidth = px(showLetters and config.width or config.degreesOnlyWidth)
	local rowHeight = px(config.height)
	local degreesRowHeight = showDegreesRow and px(config.degreesRowHeight) or 0
	local stripHeight = rowHeight + degreesRowHeight

	local function text(value : string, color : {number}, fontSize : number, headline : boolean) : TreeNodeId
		return builtin.TextView{
			meta = {
				-- not in the type definitions, but the base game uses it in meta too (game_bar.tl)
				mouseTransparent = true,
				class = headline and "font-scale-headline" or nil,
				styleSheet = styleutil.makeStyle{ color = color, fontSize = px(fontSize) },
			},
			text = value,
		}
	end

	-- main row: scrolling letters, or just the heading number
	local rowChildren : {TreeNodeId} = {}
	if showLetters then
		-- the label closest to the center of the strip is highlighted
		local halfSpan = config.visibleSpanDeg / 2
		local closest = LABELS[highlight].text
		for _, label in ipairs(LABELS) do
			local rel = wrap180(label.angle - degrees)
			if math.abs(rel) < halfSpan then
				local isClosest = label.text == closest
				rowChildren[#rowChildren + 1] = builtin.FloatingLayoutChild{
					localKey = label.text,
					h = 0.5 + (1 - 2 * config.edgeInset) * rel / (2 * halfSpan),
					v = 0.5,
					item = text(label.text,
						isClosest and highlightColor or textColor,
						isClosest and config.highlightFontSize or config.fontSize,
						isClosest),
				}
			end
		end
	else
		rowChildren[#rowChildren + 1] = builtin.FloatingLayoutChild{
			localKey = "degrees",
			h = 0.5,
			v = 0.5,
			item = text(tostring(degrees) .. "°", highlightColor, config.highlightFontSize, true),
		}
	end

	-- center marker: a small yellow tick hanging from the top edge of the strip
	rowChildren[#rowChildren + 1] = builtin.FloatingLayoutChild{
		localKey = "marker",
		h = 0.5,
		v = 0.0,
		item = builtin.Component{
			mouseTransparent = true,
			meta = {
				styleSheet = styleutil.makeStyle{
					size = { px(config.markerWidth), px(config.markerHeight) },
					backgroundColor = highlightColor,
				},
			},
		},
	}

	-- empty fixed-size component, used for spacing
	local function spacer(w : number, hgt : number) : TreeNodeId
		return builtin.Component{
			mouseTransparent = true,
			meta = { styleSheet = styleutil.makeStyle{ size = { w, hgt } } },
		}
	end

	-- a fixed-size area whose children are placed with FloatingLayoutChild h/v
	-- (compass.css.lua makes the FloatingLayout fill the area)
	local function area(hgt : number, children : {TreeNodeId}, width? : number) : TreeNodeId
		return builtin.Component{
			mouseTransparent = true,
			meta = { styleSheet = styleutil.makeStyle{ size = { width or stripWidth, hgt } } },
			layout = builtin.FloatingLayout{ children = children },
		}
	end

	local stripRows : {TreeNodeId} = { area(rowHeight, rowChildren) }
	if showDegreesRow then
		-- heading number under the letters
		stripRows[#stripRows + 1] = area(degreesRowHeight, {
			builtin.FloatingLayoutChild{
				localKey = "degrees",
				h = 0.5,
				v = 0.0,
				item = text(tostring(degrees) .. "°", textColor, config.degreesFontSize, false),
			},
		})
	end

	-- the rounded shape comes from the "dk-compass-strip" rule in compass.css.lua,
	-- which sets a nine-patch image that gets tinted with backgroundColor1
	local stripContent : TreeNodeId = builtin.BoxLayout{
		orientation = builtin.type.Orientation.Vertical,
		children = stripRows,
	}
	local totalWidth = stripWidth
	if locked:old() then
		-- locked to a vehicle: a lock in an extra column on the left, so the letters and the
		-- center notch stay exactly where they are
		local lockColumnWidth = px(config.lockColumnWidth)
		local lockSize = px(config.lockIconSize)
		totalWidth = stripWidth + lockColumnWidth
		stripContent = builtin.BoxLayout{
			orientation = builtin.type.Orientation.Horizontal,
			children = {
				area(stripHeight, {
					builtin.FloatingLayoutChild{
						localKey = "lock",
						h = 0.75,
						v = 0.5,
						item = builtin.ImageView{
							meta = {
								mouseTransparent = true,
								styleSheet = styleutil.makeStyle{ size = { lockSize, lockSize } },
							},
							path = config.lockIcon,
						},
					},
				}, lockColumnWidth),
				stripContent,
			},
		}
	end

	local strip = builtin.Component{
		mouseTransparent = true,
		meta = {
			class = "dk-compass-strip",
			styleSheet = styleutil.makeStyle{
				size = { totalWidth, stripHeight },
				backgroundColor1 = backgroundColor,
			},
		},
		layout = stripContent,
	}

	-- horizontal offset: spacer on the left (dx > 0) or right (dx < 0) of the strip
	local row : {TreeNodeId} = {}
	if settings.offsetX > 0 then row[#row + 1] = spacer(settings.offsetX, 1) end
	row[#row + 1] = strip
	if settings.offsetX < 0 then row[#row + 1] = spacer(-settings.offsetX, 1) end

	-- vertical offset: spacer above (dy > 0) or below (dy < 0) the strip
	local column : {TreeNodeId} = {}
	local offsetY = settings.offsetY
	if settings.alignWithLayersButton then
		-- center on the layers button; strips taller than the button align with its top edge instead
		offsetY = math.max(LAYERS_BUTTON_TOP - config.margin,
			math.floor(LAYERS_BUTTON_CENTER_Y - config.margin - stripHeight / 2 + 0.5))
	end
	if offsetY > 0 then column[#column + 1] = spacer(1, offsetY) end
	column[#column + 1] = builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = row,
	}
	if offsetY < 0 then column[#column + 1] = spacer(1, -offsetY) end

	local marginStyle = api.gui.StyleSheet.new()
	marginStyle.padding = api.type.Vec4f.new(config.margin, config.margin, config.margin, config.margin)

	-- a recipe must return a layout at its top level, not a component
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Vertical,
		children = {
			builtin.Component{
				mouseTransparent = true,
				meta = { styleSheet = marginStyle },
				layout = builtin.BoxLayout{
					orientation = builtin.type.Orientation.Vertical,
					children = column,
				},
			},
		},
	}
end)

-- The celebrations overlay is a full-screen, click-through layer inside the main HUD.
-- We wrap it in a full-screen FloatingLayout so the on-screen compass can be placed
-- anywhere on screen according to the "compassPosition" mod setting.
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
	if settings:get().screenCompass ~= SCREEN_OFF then
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
-- Registered through compass_gamebar.res.lua.
local DkCompassGameBarPlugin = react.RegisterPluginRecipe(game_bar_widgets.GameBarInfoDisplayExtension, "DkCompassGameBarPlugin", function() : TreeNodeId
	local settings : ReactRefT<Settings> = react.useRefLazy(loadSettings)
	local mode = settings:get().gameBar
	if mode == GAME_BAR_OFF then
		return nil
	end

	local compact = settings:get().compactNames
	local heading, locked = useHeading(settings:get().northOffsetDeg, settings:get().vehicleHeading)
	local degrees = heading:old()
	local index = directionIndex(degrees)
	local name = compact and LABELS[index].text or DIRECTION_NAMES[index]

	-- each text style gets a fixed width per font size from compass.css.lua, so the bar
	-- doesn't shift when the text gets longer or shorter while turning the camera
	local text : string
	local class : string
	if mode == GAME_BAR_DEGREES then
		text = tostring(degrees) .. "°"
		class = "dk-gamebar-degrees"
	elseif mode == GAME_BAR_BOTH then
		text = name .. " " .. tostring(degrees) .. "°"
		class = compact and "dk-gamebar-both-compact" or "dk-gamebar-both"
	else
		text = name
		class = compact and "dk-gamebar-direction-compact" or "dk-gamebar-direction"
	end

	local isLocked = locked:old()
	local children : {TreeNodeId} = {}
	if isLocked then
		-- locked to a vehicle: a lock in front of the text (outside the fixed-width text box,
		-- like the icons in front of the Transported numbers)
		children[#children + 1] = builtin.ImageView{
			meta = { tooltip = "Direction of the followed vehicle" },
			path = config.lockIcon,
		}
	end
	children[#children + 1] = builtin.Component{
		meta = {
			tooltip = isLocked and "Direction of the followed vehicle" or "Camera direction",
			class = class,
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
	}

	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = children,
	}
end)

-- The game hides its whole normal interface (including the celebrations overlay above) in
-- follow view and free camera. The callout overlay is a full-screen, click-through layer outside
-- that interface, so with "Show in free camera and follow view" on, a second compass is added
-- there. It carries the "dk-camera-view" class, which compass.css.lua only shows in those views
-- (!action-follow / !action-camera).
-- The callout container provides an interface (Api) that the game and the menus reach through a
-- reference to this wrapper's node. The original container is a separate node inside the wrapper
-- and provides its Api there, so the wrapper forwards every Api call to that inner node.
local CalloutContainerWithCompass = react.RegisterRecipe("CalloutContainer", function() : TreeNodeId
	react.setMouseTransparent(true)
	local settings : ReactRefT<Settings> = react.useRefLazy(loadSettings)

	local innerRef = react.useNodeRef()
	react.provideApi(setmetatable({}, {
		__index = function(_ : table, key : string) : any
			local inner = innerRef:get()
			local innerApi = inner and inner:getApi() as table
			return innerApi and innerApi[key]
		end,
	}))

	local children : {TreeNodeId} = {
		builtin.FloatingLayoutChild{
			localKey = "callouts",
			h = -1,
			v = -1,
			item = react.CallOriginalRecipe(callout_container, react.ref(innerRef)),
		},
	}
	local s = settings:get()
	if s.cameraViews then
		local cameraSettings : Settings = {
			gameBar = s.gameBar,
			compactNames = s.compactNames,
			-- same style as the screen compass, or letters if the screen compass is off
			screenCompass = s.screenCompass ~= SCREEN_OFF and s.screenCompass or SCREEN_LETTERS,
			posH = s.posH,
			posV = s.posV,
			offsetX = s.offsetX,
			offsetY = s.offsetY,
			alignWithLayersButton = s.alignWithLayersButton,
			scale = s.scale,
			northOffsetDeg = s.northOffsetDeg,
			cameraViews = true,
			vehicleHeading = s.vehicleHeading,
			isCameraView = true,
		}
		children[#children + 1] = builtin.FloatingLayoutChild{
			localKey = "dk-compass-camera-view",
			h = s.posH,
			v = s.posV,
			item = builtin.Component{
				mouseTransparent = true,
				meta = { class = "dk-camera-view" },
				layout = builtin.BoxLayout{ child = DkCompass(cameraSettings) },
			},
		}
	end

	return builtin.FloatingLayout{ children = children }
end)

local function doReplaceFn(replacementApi : ReactReplacementApi)
	replacementApi.ReplaceRecipe(celebration_react_util.CelebrationsContainer, CelebrationsContainerWithCompass)
	replacementApi.ReplaceRecipe(callout_container, CalloutContainerWithCompass as RecipeWithApi0<CalloutApi>)
end

local result = {
	doReplaceFn = doReplaceFn,
	DkCompassGameBarPlugin = DkCompassGameBarPlugin,
}

return result
