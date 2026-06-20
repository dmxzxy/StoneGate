-- ============================================================================
-- base/assets —— 字体加载。只依赖 love + base/draw（写回字体句柄）。
-- 中文字体（思源黑体）；缺失则退回 LÖVE 默认字体（中文显示为方块，不崩）。
-- ============================================================================
local draw = require("base.draw")

local assets = {}

local CJK = "assets/fonts/NotoSansSC-Regular.otf"
local function mkfont(sz)
    local ok,f = pcall(love.graphics.newFont, CJK, sz)
    if ok then f:setFilter("linear","linear"); return f else return love.graphics.newFont(sz) end
end

-- 在 love.load 阶段调用：建好四档字体并写回 base/draw 的句柄供绘制取用。
function assets.load_fonts()
    local font     = mkfont(15)
    local font_sm  = mkfont(12)
    local font_med = mkfont(19)
    local font_big = mkfont(30)
    draw.set_fonts(font, font_sm, font_med, font_big)
    return font, font_sm, font_med, font_big
end

return assets
