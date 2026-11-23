-- The panel: plain UMG widgets built at runtime (no Blueprint assets), with the game's HUD sprite behind them, as
-- Battle Meters' and Training Dummy's overlay.lua do (the game's EndTextBlock and EndImage draw nothing when made at
-- runtime, so text is the engine's Roboto). Draws a view from meters_view.lua. Called on the game thread.
--
-- Layout, in 1920x1080 units from the panel's top left:
--   tabs (Damage / Tanking / Healing, the shown one bright and underlined)            timer
--   the setup in Custom Training's words, behaviour
--   Wave N   Last clear m:ss (when Custom Training sends waves)
--   what the big number is                                                     big number
--   stats rows
--   By character                                                   per sec          total
--   one row per character: colour chip, name, per second, total, and a share bar under it
--   note (what the rows can't say)
--   key hints (keyboard), where the pad controls are
local M = {}

local WIDTH, PAD = 404, 18
local INNER = WIDTH - PAD * 2
local LABEL = { R = 0.68, G = 0.84, B = 0.95, A = 1 }
local WHITE = { R = 1, G = 1, B = 1, A = 1 }
local DIM = { R = 0.62, G = 0.70, B = 0.76, A = 1 }
local FAINT = { R = 0.45, G = 0.52, B = 0.58, A = 1 }
local TEAL = { R = 0.45, G = 0.90, B = 1.00, A = 1 }
local SHADOW = { R = 0, G = 0, B = 0, A = 0.6 }
local EDGE = { R = 0.8, G = 0.92, B = 1, A = 0.7 }
local GAUGE_BACK = { R = 0.04, G = 0.09, B = 0.14, A = 0.9 }
local SPRITES = "/Game/Menu/Resident/Texture/"
local VISIBLE, COLLAPSED = 3, 1                       -- ESlateVisibility: HitTestInvisible, Collapsed
local RIGHT = 2                                       -- ETextJustify
local TABS, STATS, ROWS = 3, 6, 5
local TAB_W = 96
local NAME_W, RATE_W, TOTAL_W = 150, 92, 110

local ui = nil

local function safe(f, ...)
    local ok, value = pcall(f, ...)
    if ok then return value end
    return nil
end
local function valid(object)
    return object ~= nil and safe(function() return object:IsValid() end) == true
end
local function find(path)
    local object = safe(StaticFindObject, path)
    return valid(object) and object or nil
end
local function sprite(name) return find(SPRITES .. name .. "." .. name) end

local function new_name(self, prefix)
    self.count = self.count + 1
    return FName("SimOverhaulMeters" .. prefix .. self.count)
end

local function add_image(self, resource, margin, tint)
    local image = StaticConstructObject(self.image_class, self.tree, new_name(self, "Image"))
    if resource then
        image:SetBrushResourceObject(resource)
        image.Brush.DrawAs = 1
        image.Brush.Margin = margin
    end
    image:SetColorAndOpacity(tint or WHITE)
    local slot = self.canvas:AddChildToCanvas(image)
    slot:SetAutoSize(false)
    return { widget = image, slot = slot, color = tint or WHITE }
end

local function add_text(self, size, color, justify)
    local text = StaticConstructObject(self.text_class, self.tree, new_name(self, "Text"))
    text.Font.Size = size
    text.Font.TypefaceFontName = FName("Regular")
    text:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = 0 })
    text:SetShadowOffset({ X = 2, Y = 1 })
    text:SetShadowColorAndOpacity(SHADOW)
    if justify then text:SetJustification(justify) end
    local slot = self.canvas:AddChildToCanvas(text)
    slot:SetAutoSize(false)
    return { widget = text, slot = slot, color = color }
end

local function create(settings, world_object)
    local statics = find("/Script/Engine.Default__GameplayStatics")
    local library = find("/Script/UMG.Default__WidgetBlueprintLibrary")
    local widget_class = find("/Script/UMG.UserWidget")
    local text_class, image_class = find("/Script/UMG.TextBlock"), find("/Script/UMG.Image")
    if not (statics and library and widget_class and text_class and image_class) then return nil, "UMG classes not found" end
    local controller = safe(function() return statics:GetPlayerController(world_object, 0) end)
    if not valid(controller) then return nil, "no player controller" end
    local widget = safe(function() return library:Create(controller, widget_class, controller) end)
    if not valid(widget) then return nil, "Create failed" end

    local tree = StaticConstructObject(find("/Script/UMG.WidgetTree"), widget, FName("SimOverhaulMetersTree"))
    widget.WidgetTree = tree
    local canvas = StaticConstructObject(find("/Script/UMG.CanvasPanel"), tree, FName("SimOverhaulMetersCanvas"))
    tree.RootWidget = canvas
    local self = { widget = widget, tree = tree, canvas = canvas, text_class = text_class, image_class = image_class,
        x = settings.x, y = settings.y, count = 0, tabs = {}, stats = {}, rows = {} }

    -- Everything is made up front and collapsed when not needed. Drawn in this order, back to front.
    self.panel = add_image(self, sprite("U_Status_Base_01"), { Left = 0, Top = 0.3, Right = 0, Bottom = 0.3 },
        { R = 1, G = 1, B = 1, A = 0.95 })
    self.underline = add_image(self, nil, nil, TEAL)
    for i = 1, ROWS do
        self.rows[i] = { back = add_image(self, nil, nil, GAUGE_BACK), bar = add_image(self, nil, nil, WHITE),
            edge = add_image(self, nil, nil, EDGE), chip = add_image(self, nil, nil, WHITE),
            name = add_text(self, 15, WHITE), rate = add_text(self, 15, WHITE, RIGHT), total = add_text(self, 15, WHITE, RIGHT) }
    end
    for i = 1, TABS do self.tabs[i] = add_text(self, 16, DIM) end
    self.timer = add_text(self, 16, DIM, RIGHT)
    self.subtitle = add_text(self, 13, LABEL)
    self.wave = add_text(self, 13, DIM)
    self.unit = add_text(self, 14, LABEL)
    self.value = add_text(self, 30, WHITE, RIGHT)
    for i = 1, STATS do self.stats[i] = { label = add_text(self, 15, LABEL), value = add_text(self, 17, WHITE, RIGHT) } end
    self.head_name = add_text(self, 12, DIM)
    self.head_rate = add_text(self, 12, DIM, RIGHT)
    self.head_total = add_text(self, 12, DIM, RIGHT)
    self.note = add_text(self, 12, DIM)
    self.hint = add_text(self, 12, FAINT)
    self.pad_hint = add_text(self, 12, FAINT)
    widget:AddToViewport(1000)
    widget:SetVisibility(VISIBLE)
    return self
end

-- Each setter is a reflected call on the game thread, so only what changed is touched.
local function place(self, item, x, y, w, h)
    if item.x ~= x or item.y ~= y then
        item.slot:SetPosition({ X = self.x + x, Y = self.y + y })
        item.x, item.y = x, y
    end
    if item.w ~= w or item.h ~= h then
        item.slot:SetSize({ X = w, Y = h })
        item.w, item.h = w, h
    end
    if item.hidden ~= false then
        item.widget:SetVisibility(VISIBLE)
        item.hidden = false
    end
end

local function collapse(item)
    if item.hidden ~= true then
        item.widget:SetVisibility(COLLAPSED)
        item.hidden = true
    end
end

local function text(self, item, value, x, y, w, h)
    if value == nil or value == "" then collapse(item); return end
    if item.shown ~= value then
        item.widget:SetText(FText(value))
        item.shown = value
    end
    place(self, item, x, y, w, h)
end

local function tint(item, color, is_text)
    if item.color ~= color then
        if is_text then item.widget:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = 0 })
        else item.widget:SetColorAndOpacity(color) end
        item.color = color
    end
end

local function draw(self, view)
    local y = 10
    for i = 1, TABS do
        local tab = view.tabs[i]
        tint(self.tabs[i], tab.current and WHITE or DIM, true)
        text(self, self.tabs[i], tab.text, PAD + (i - 1) * TAB_W, y, TAB_W - 6, 24)
        if tab.current then place(self, self.underline, PAD + (i - 1) * TAB_W, y + 24, 64, 2) end
    end
    text(self, self.timer, view.timer, WIDTH - PAD - 90, y, 90, 24)
    y = y + 32
    text(self, self.subtitle, view.subtitle, PAD, y, INNER, 20)
    y = y + 24
    if view.wave then
        text(self, self.wave, view.wave, PAD, y - 4, INNER, 20)
        y = y + 18
    else
        collapse(self.wave)
    end
    text(self, self.unit, view.unit, PAD, y + 13, INNER * 0.55, 22)
    text(self, self.value, view.value, PAD + INNER * 0.4, y, INNER * 0.6, 42)
    y = y + 46
    for i = 1, STATS do
        local stat, pair = view.stats[i], self.stats[i]
        if stat then
            text(self, pair.label, stat[1], PAD, y + 2, INNER * 0.68, 24)
            text(self, pair.value, stat[2], PAD + INNER * 0.4, y, INNER * 0.6, 24)
            y = y + 24
        else
            collapse(pair.label); collapse(pair.value)
        end
    end
    if #view.rows > 0 then
        y = y + 8
        text(self, self.head_name, "By character", PAD, y, NAME_W, 18)
        text(self, self.head_rate, "per sec", PAD + INNER - TOTAL_W - RATE_W, y, RATE_W, 18)
        text(self, self.head_total, "total", PAD + INNER - TOTAL_W, y, TOTAL_W, 18)
        y = y + 20
    else
        collapse(self.head_name); collapse(self.head_rate); collapse(self.head_total)
    end
    for i = 1, ROWS do
        local row, item = view.rows[i], self.rows[i]
        if row then
            place(self, item.edge, PAD - 1, y + 6, 12, 12)
            tint(item.chip, row.color)
            place(self, item.chip, PAD, y + 7, 10, 10)
            text(self, item.name, row.name, PAD + 18, y, NAME_W, 22)
            text(self, item.rate, row.rate, PAD + INNER - TOTAL_W - RATE_W, y, RATE_W, 22)
            text(self, item.total, row.total, PAD + INNER - TOTAL_W, y, TOTAL_W, 22)
            place(self, item.back, PAD + 18, y + 23, INNER - 18, 4)
            local width = math.floor((INNER - 18) * math.max(0, math.min(1, row.share or 0)) + 0.5)
            if width >= 1 then
                tint(item.bar, row.color)
                place(self, item.bar, PAD + 18, y + 23, width, 4)
            else
                collapse(item.bar)
            end
            y = y + 30
        else
            for _, part in pairs({ item.back, item.bar, item.edge, item.chip, item.name, item.rate, item.total }) do collapse(part) end
        end
    end
    if view.note then
        y = y + 4
        text(self, self.note, view.note, PAD, y, INNER, 18)
        y = y + 18
    else
        collapse(self.note)
    end
    y = y + 8
    text(self, self.hint, view.hint, PAD, y, INNER, 18)
    y = y + 18
    text(self, self.pad_hint, view.pad_hint, PAD, y, INNER, 18)
    y = y + 18
    place(self, self.panel, 0, 0, WIDTH, y + 10)
end

-- Is the panel on screen now?
function M.shown() return ui ~= nil and not ui.hidden end

function M.show(view, settings, world_object)
    -- A level change takes the panel off the screen without destroying it: make it again.
    if not (ui and valid(ui.widget) and safe(function() return ui.widget:IsInViewport() end) == true) then
        local made, problem = create(settings, world_object)
        if not made then
            if M.last_error ~= problem then print("[SimOverhaulMeters] overlay: " .. tostring(problem) .. "\n") end
            M.last_error = problem
            return false
        end
        ui = made
        print("[SimOverhaulMeters] overlay created\n")
    end
    if ui.hidden then
        ui.widget:SetVisibility(VISIBLE)
        ui.hidden = false
    end
    draw(ui, view)
    return true
end

function M.hide()
    if ui and not ui.hidden and valid(ui.widget) then
        ui.widget:SetVisibility(COLLAPSED)
        ui.hidden = true
    end
end

return M
