-- Headless smoke test: mock the LÖVE API enough to load main.lua and run
-- init() + many update/draw frames across all activities. Catches nil-derefs
-- and logic errors that luac -p can't. Run: lua test_headless.lua
--
-- 运行约定：cd 到 quiver 目录后 `lua test_headless.lua`（cwd=quiver），故把
-- 设计空间子模块路径前置进 package.path，让重构后的 require("data") /
-- require("base.draw") / require("sys.combat") / require("helium") 等能解析。
package.path = "./?.lua;./?/init.lua;" .. package.path

local W,H = 480, 800
local function noop() end
-- 通用安全假对象：任何方法调用返回它自己 + 一对维度数字，足以让 helium 的
-- canvas/quad/image 链式调用与 :getDimensions() 不崩。
local fakeobj
fakeobj = setmetatable({}, { __index = function() return function() return fakeobj, W, H end end })
local fontobj = setmetatable({}, { __index=function() return function() return 12 end end })
local g = {}
local gfuncs = { "setColor","rectangle","circle","polygon","line","arc","print","printf",
  "push","pop","translate","setLineWidth","setLineStyle","setLineJoin","setFont",
  "setBackgroundColor","setScissor","ellipse","scale","origin","clear","present","points",
  -- helium require/draw 期会捕获/调用这些：保持 noop 或返回假对象
  "setCanvas","draw","setBlendMode","applyTransform","replaceTransform","intersectScissor",
  "rotate","shear","reset","setShader","stencil","setStencilTest","setColorMask" }
for _,n in ipairs(gfuncs) do g[n]=noop end
g.getWidth=function() return W end
g.getHeight=function() return H end
g.getDimensions=function() return W,H end
-- helium 非缓存元素渲染路径会调用 transformPoint 求屏幕坐标做 scissor（element.lua）
g.transformPoint=function(x,y) return x or 0, y or 0 end
g.inverseTransformPoint=function(x,y) return x or 0, y or 0 end
g.newFont=function() return fontobj end
g.getFont=function() return fontobj end
-- helium element.lua / atlas.lua 在 require 期把这些捕获进 local，必须是函数：
g.newCanvas=function() return fakeobj end
g.newImage=function() return fakeobj end
g.newQuad=function() return fakeobj end
g.getCanvas=function() return nil end
love = { graphics=g, timer={ getTime=function() return 0 end }, window={}, mouse={}, system={},
  -- helium core/input.lua 在 require 期读 love.handlers['mousepressed'] 等做 orig 快照，
  -- 然后写回包裹函数。给个空表即可让它塞；种入 noop 防被包裹函数调用 orig.X 时 nil 调用。
  handlers = setmetatable({}, { __index = function() return noop end }),
  -- helium 不用 math.newTransform，但 base/draw 等将来可能用；给最小桩。
  math = { newTransform = function() return fakeobj end, random = math.random,
           noise = function() return 0 end, colorFromBytes = function(...) return ... end },
  graphics_ok=true }

-- in-memory mock filesystem (for save/load round-trip tests)
local FS = {}
love.filesystem = {
  write = function(path,data) FS[path]=data; return true end,
  read = function(path) if FS[path] then return FS[path], #FS[path] end; return nil,"nf" end,
  getInfo = function(path) if FS[path]~=nil then return {type="file", size=#FS[path]} end; return nil end,
  load = function(path) if not FS[path] then return nil,"nf" end; return load(FS[path]) end,
  append = function(path,data) FS[path]=(FS[path] or "")..data; return true end,
  createDirectory = function() return true end,
  getSaveDirectory = function() return "/mock/save" end,
}

-- enable the guarded test hook in main.lua
QUIVER_TEST = {}

-- deterministic-ish RNG seeded fixed
math.randomseed(12345)

-- load the game file
local chunk, err = loadfile("main.lua")
if not chunk then print("LOAD FAIL: "..tostring(err)); os.exit(1) end
local ok, e = pcall(chunk)
if not ok then print("CHUNK RUN FAIL: "..tostring(e)); os.exit(1) end

-- run callbacks
local function try(label, fn)
  local ok,e = pcall(fn)
  if not ok then print("FAIL ["..label.."]: "..tostring(e)); os.exit(1) end
end

try("love.load", function() love.load() end)

-- exercise every activity + panels by driving press() via love handlers,
-- and run many update/draw frames so all branches tick.
local function frames(n) for _=1,n do try("update", function() love.update(0.05) end); try("draw", function() love.draw() end) end end
local function tap(x,y) try("press@"..x..","..y, function() if love.mousepressed then love.mousepressed(x,y,1) end; if love.mousereleased then love.mousereleased(x,y,1) end end) end
-- activity menu row centers under grouped layout (480x800); skills entry is 2nd bottom button
local ACT_OPEN = {55, 772}
local SKILLS_OPEN = {147, 772}
local ROW = { rest=150, combat=236, woodcut=322, mining=386, herb=450, fletch=514 }
local function pick(act) tap(ACT_OPEN[1],ACT_OPEN[2]); frames(2); tap(120, ROW[act]); frames(2) end

frames(10)
-- accumulate materials via each gather, then craft (exercises do_craft / add_craft_xp / unlock_blueprints),
-- then fight (exercises make_enemy ranks / drop_loot / projectile).
pick("woodcut"); frames(800)
pick("mining");  frames(800)
pick("herb");    frames(800)
pick("fletch");  frames(2000)         -- craft until materials drain, then auto-stop
-- tap a blueprint card in the craft view (lower half) to switch blueprint
tap(W/2, 460); frames(200)
pick("combat");  frames(2500)
-- 技能面板：打开、点各行学习按钮(可能金/料不足)、关闭
tap(SKILLS_OPEN[1],SKILLS_OPEN[2]); frames(20)
for r=0,7 do tap(W-50, 130+r*60); frames(4) end
tap(W/2, H-70); frames(4)
-- open every panel + region scroll/select
for i=0,3 do tap(40+i*100, H-30); frames(40); tap(W/2, H-70); frames(4) end
tap(W-40, H-30); frames(4)
if love.wheelmoved then for _=1,40 do pcall(love.wheelmoved,0,-3) end end
frames(4); tap(W/2, 300); frames(20)          -- 选一个(可能更高级的)地区
pick("woodcut"); frames(600)                   -- 在高区采集：可能反复"等级不足"，验证跳过路径
pick("mining");  frames(400)
pick("rest"); frames(60)

-- ===== 存档系统 round-trip（含稀疏 inv 空洞）=====
local fails = 0
local function check(name, cond) if cond then print("PASS "..name) else print("FAIL "..name); fails=fails+1 end end
local S = QUIVER_TEST
check("love.quit 是函数(顶层定义)", type(love.quit)=="function")
check("test hook 暴露 save", type(S.save)=="table" and type(S.save.write)=="function")

local p = S.state().player
p.gold = 1234; p.level = 5; p.xp = 42
-- 造一个 inv 空洞：1/3 格有物、第2格空 —— 验证稀疏存不丢洞后物品
p.inv = {}; p.inv[1]={kind="mat",id="wood",qty=7}; p.inv[3]={kind="mat",id="ore",qty=3}
check("save.write 成功", S.save.write()==true)
local raw = FS["quiver/save.lua"]
check("存档文件已写入", type(raw)=="string" and #raw>0)
local data = assert(load(raw))()
check("序列化含 gold=1234", data.gold==1234)
check("inv 稀疏：洞(第2格)保留为空", data.inv[1]~=nil and data.inv[2]==nil and data.inv[3]~=nil)

-- 篡改内存后读档，应从磁盘完整复原
p.gold=0; p.level=1; p.inv={}
check("save.load 成功", S.save.load()==true)
local q = S.state().player
check("读档 gold 复原", q.gold==1234)
check("读档 level 复原", q.level==5)
check("读档 inv 洞后物品不丢", q.inv[1] and q.inv[1].qty==7 and q.inv[3] and q.inv[3].id=="ore" and q.inv[2]==nil)
check("读档后 max_mp 由 recalc 重算", q.max_mp==30+q.level*5 and q.mp~=nil)

-- 坏档不崩：写入垃圾，load 应 return false（调用方会 init 回退）
FS["quiver/save.lua"] = "this is not lua {{{"
check("坏档 save.load 返回 false 不崩", S.save.load()==false)

-- ===== helium require 烟测（验证 mock love 桩对未来 UI 阶段够用）=====
-- 后续阶段 main.lua 将 require("helium")。helium core/input.lua 在 require 期会
-- 读 love.handlers 做 orig 快照并写回包裹函数；atlas/element 捕获 love.graphics.*。
-- 这里在 harness 里先单独 require 一次，确保桩齐全、不崩。若 helium 目录尚不存在
-- 则跳过（标 PASS），不阻塞 harness。
if love.filesystem.getInfo and io.open then
  local f = io.open("helium/init.lua","r")
  if f then
    f:close()
    local hok, helium = pcall(require, "helium")
    check("require('helium') 在 mock love 下不崩", hok)
    if hok then
      check("helium 返回模块表(可调用)", type(helium)=="table" or type(helium)=="function")
      check("require helium 后 love.handlers.mousepressed 可调用",
            type(love.handlers.mousepressed)=="function")
    else
      print("  helium require 失败: "..tostring(helium))
    end
  else
    print("PASS helium 目录暂缺，跳过 require 烟测")
  end
end

if fails>0 then print("SAVE FAILURES: "..fails); os.exit(1) end
print("SMOKE OK")
