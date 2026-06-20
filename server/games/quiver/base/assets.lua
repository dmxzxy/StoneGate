-- ============================================================================
-- base/assets —— 字体加载。只依赖 love + base/draw（写回字体句柄）。
-- 像素风：Zpix 像素中文字体（整数号 + nearest，硬边不糊）；缺失则退回思源黑体，再退默认。
-- 全局 setDefaultFilter("nearest") → 所有图像/字体默认最近邻，保住像素硬边。
-- ============================================================================
local draw = require("base.draw")

local assets = {}

local PIX = "assets/fonts/zpix.ttf"               -- 像素中文字体（首选）
local CJK = "assets/fonts/NotoSansSC-Regular.otf" -- 兜底（zpix 缺失时）

-- 像素字体：整数号 + nearest，避免子像素糊边。zpix 缺失退 NotoSans，再退默认。
local function mkfont(sz)
    local ok,f = pcall(love.graphics.newFont, PIX, sz)
    if ok then f:setFilter("nearest","nearest"); return f end
    ok,f = pcall(love.graphics.newFont, CJK, sz)
    if ok then f:setFilter("nearest","nearest"); return f end
    return love.graphics.newFont(sz)
end

-- 在 love.load 阶段调用：全局默认最近邻 + 建好四档整数号像素字并写回 base/draw。
function assets.load_fonts()
    if love.graphics.setDefaultFilter then love.graphics.setDefaultFilter("nearest","nearest") end
    local font     = mkfont(12)   -- 正文
    local font_sm  = mkfont(10)   -- 小字/标签
    local font_med = mkfont(16)   -- 小标题
    local font_big = mkfont(24)   -- 大标题/横幅
    draw.set_fonts(font, font_sm, font_med, font_big)
    return font, font_sm, font_med, font_big
end

return assets
