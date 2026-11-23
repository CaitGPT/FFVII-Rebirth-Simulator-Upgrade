-- Draws the settings panel (ct_panel_model's view) on the left of the screen: plain UMG Image and TextBlock widgets
-- built at runtime with the game's own HUD sprite, as Training Dummy's meter is (EndTextBlock and EndImage draw
-- nothing when made at runtime). Everything is made once and only what changed is touched. Game thread only.
local M = {}

local X, Y, WIDTH, PAD = 56, 48, 560, 16
local SECTION_H = { enemy = 150, behaviour = 104, difficulty = 104, quantity = 104, meter = 104, tool = 104 }
local GAP, CELL_GAP = 12, 10
local MAX_CELLS = 4
local MAX_SECTIONS = 6 -- the four settings, and the meters' two when that part is there
local VISIBLE, COLLAPSED = 3, 1                          -- ESlateVisibility: HitTestInvisible, Collapsed
local CENTER = 1                                         -- ETextJustify
local WHITE = { R = 1, G = 1, B = 1, A = 1 }
local DIM = { R = 0.62, G = 0.68, B = 0.74, A = 1 }
local CYAN = { R = 0.45, G = 0.90, B = 1.00, A = 1 }
local BOX = { R = 0.05, G = 0.07, B = 0.10, A = 0.88 }
local BOX_EDGE = { R = 0.45, G = 0.52, B = 0.60, A = 0.55 }
local CELL = { R = 0.09, G = 0.12, B = 0.17, A = 0.95 }
local CELL_ON = { R = 0.10, G = 0.22, B = 0.36, A = 0.98 }
local SHADOW = { R = 0, G = 0, B = 0, A = 0.6 }
local SPRITE = "/Game/Menu/Resident/Texture/U_Status_Base_01.U_Status_Base_01"
local MARGIN = { Left = 0, Top = 0.3, Right = 0, Bottom = 0.3 }

local ui = nil

local function safe(f, ...)
    local ok, v = pcall(f, ...)
    if ok then return v end
    return nil
end
local function valid(o) return o ~= nil and safe(function() return o:IsValid() end) == true end
local function find(path)
    local o = safe(StaticFindObject, path)
    return valid(o) and o or nil
end

local function new_name(self, prefix)
    self.count = self.count + 1
    return FName("SimOverhaulCT" .. prefix .. self.count)
end

local function add_image(self, tint, plain)
    local image = StaticConstructObject(self.image_class, self.tree, new_name(self, "Image"))
    if not plain and self.sprite then
        image:SetBrushResourceObject(self.sprite)
        image.Brush.DrawAs = 1
        image.Brush.Margin = MARGIN
    end
    image:SetColorAndOpacity(tint)
    local slot = self.canvas:AddChildToCanvas(image)
    slot:SetAutoSize(false)
    return { widget = image, slot = slot, tint = tint }
end

local function add_text(self, size, color, justify)
    local text = StaticConstructObject(self.text_class, self.tree, new_name(self, "Text"))
    text.Font.Size = size
    text.Font.TypefaceFontName = FName("Bold")
    text:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = 0 })
    text:SetShadowOffset({ X = 2, Y = 1 })
    text:SetShadowColorAndOpacity(SHADOW)
    if justify then text:SetJustification(justify) end
    local slot = self.canvas:AddChildToCanvas(text)
    slot:SetAutoSize(false)
    return { widget = text, slot = slot, color = color }
end

-- A box with an edge: an outer image in the edge colour and an inner one 2 px in.
local function add_box(self, fill, edge)
    return { edge = add_image(self, edge), fill = add_image(self, fill) }
end

local function create(world_object)
    local statics = find("/Script/Engine.Default__GameplayStatics")
    local library = find("/Script/UMG.Default__WidgetBlueprintLibrary")
    local widget_class = find("/Script/UMG.UserWidget")
    local text_class, image_class = find("/Script/UMG.TextBlock"), find("/Script/UMG.Image")
    if not (statics and library and widget_class and text_class and image_class) then return nil, "UMG classes not found" end
    local controller = safe(function() return statics:GetPlayerController(world_object, 0) end)
    if not valid(controller) then return nil, "no player controller" end
    local widget = safe(function() return library:Create(controller, widget_class, controller) end)
    if not valid(widget) then return nil, "Create failed" end
    local tree = StaticConstructObject(find("/Script/UMG.WidgetTree"), widget, FName("SimOverhaulCTTree"))
    widget.WidgetTree = tree
    local canvas = StaticConstructObject(find("/Script/UMG.CanvasPanel"), tree, FName("SimOverhaulCTCanvas"))
    tree.RootWidget = canvas
    local self = { widget = widget, tree = tree, canvas = canvas, text_class = text_class, image_class = image_class,
                   sprite = find(SPRITE), count = 0, sections = {} }
    for i = 1, MAX_SECTIONS do
        local s = { box = add_box(self, BOX, BOX_EDGE), cells = {} }
        s.title = add_text(self, 20, WHITE)
        s.left = add_text(self, 28, WHITE, CENTER)
        s.right = add_text(self, 28, WHITE, CENTER)
        for c = 1, MAX_CELLS do
            s.cells[c] = { box = add_box(self, CELL, BOX_EDGE), text = add_text(self, 16, DIM, CENTER) }
        end
        s.note = add_text(self, 13, DIM, CENTER)
        self.sections[i] = s
    end
    self.footer_box = add_box(self, BOX, BOX_EDGE)
    self.footer = add_text(self, 15, WHITE)
    widget:AddToViewport(1000)
    widget:SetVisibility(VISIBLE)
    return self
end

local function place(item, x, y, w, h)
    if item.x ~= x or item.y ~= y then item.slot:SetPosition({ X = X + x, Y = Y + y }); item.x, item.y = x, y end
    if item.w ~= w or item.h ~= h then item.slot:SetSize({ X = w, Y = h }); item.w, item.h = w, h end
    if item.hidden ~= false then item.widget:SetVisibility(VISIBLE); item.hidden = false end
end

local function collapse(item)
    if item.hidden ~= true then item.widget:SetVisibility(COLLAPSED); item.hidden = true end
end

local function tint(item, color)
    if item.tint ~= color then item.widget:SetColorAndOpacity(color); item.tint = color end
end

local function color(item, c)
    if item.color ~= c then item.widget:SetColorAndOpacity({ SpecifiedColor = c, ColorUseRule = 0 }); item.color = c end
end

local function text(item, value, x, y, w, h)
    if item.shown ~= value then item.widget:SetText(FText(value)); item.shown = value end
    place(item, x, y, w, h)
end

local function box(b, x, y, w, h, edge, fill)
    tint(b.edge, edge); tint(b.fill, fill)
    local e = edge == CYAN and 3 or 2
    place(b.edge, x, y, w, h)
    place(b.fill, x + e, y + e, w - 2 * e, h - 2 * e)
end

local function collapse_box(b) collapse(b.edge); collapse(b.fill) end

local function draw(self, view)
    local y = 0
    for i, sv in ipairs(view.sections) do
        local s, h = self.sections[i], SECTION_H[sv.key] or 104
        box(s.box, 0, y, WIDTH, h, sv.focused and CYAN or BOX_EDGE, BOX)
        text(s.title, sv.title, PAD, y + 10, WIDTH - 2 * PAD, 30)
        local arrow_y = y + (sv.key == "enemy" and 62 or 54)
        text(s.left, "<", PAD, arrow_y - 6, 32, 40)
        text(s.right, ">", WIDTH - PAD - 32, arrow_y - 6, 32, 40)
        color(s.left, sv.focused and WHITE or DIM); color(s.right, sv.focused and WHITE or DIM)
        local n = #sv.cells
        local area_x, area_w = PAD + 40, WIDTH - 2 * PAD - 80
        local cell_w = (area_w - CELL_GAP * (n - 1)) / n
        local cell_h = sv.key == "enemy" and 64 or 40
        local cell_y = y + (sv.key == "enemy" and 48 or 48)
        for c = 1, MAX_CELLS do
            local cell, cv = s.cells[c], sv.cells[c]
            if cv then
                local cx = area_x + (c - 1) * (cell_w + CELL_GAP)
                local on = cv.selected
                if sv.key == "quantity" then
                    collapse_box(cell.box)
                else
                    box(cell.box, cx, cell_y, cell_w, cell_h, on and CYAN or BOX_EDGE, on and CELL_ON or CELL)
                end
                text(cell.text, cv.text, cx, cell_y + (cell_h - 24) / 2, cell_w, 26)
                color(cell.text, on and WHITE or DIM)
            else
                collapse_box(cell.box); collapse(cell.text)
            end
        end
        if sv.note then text(s.note, sv.note, PAD, y + h - 30, WIDTH - 2 * PAD, 22) else collapse(s.note) end
        y = y + h + GAP
    end
    for i = #view.sections + 1, MAX_SECTIONS do
        local s = self.sections[i]
        collapse_box(s.box); collapse(s.title); collapse(s.left); collapse(s.right); collapse(s.note)
        for c = 1, MAX_CELLS do collapse_box(s.cells[c].box); collapse(s.cells[c].text) end
    end
    box(self.footer_box, 0, y + 8, WIDTH + 260, 44, BOX_EDGE, BOX)
    text(self.footer, view.footer, PAD, y + 19, WIDTH + 260 - 2 * PAD, 24)
end

-- Shows the view (creating the widgets the first time, and again after a level change took them away).
function M.show(view, world_object)
    if not (ui and valid(ui.widget) and safe(function() return ui.widget:IsInViewport() end)) then
        local made, problem = create(world_object)
        if not made then return false, problem end
        ui = made
    end
    safe(function() ui.widget:SetVisibility(VISIBLE) end)
    local ok, err = pcall(draw, ui, view)
    return ok, err
end

function M.hide()
    if ui and valid(ui.widget) then safe(function() ui.widget:SetVisibility(COLLAPSED) end) end
end

return M
