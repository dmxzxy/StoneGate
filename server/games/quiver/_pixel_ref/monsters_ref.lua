-- Monster pixel sprite sheet (full-colour, cohesive dusk palette). Renders a labelled
-- grid on a low-res canvas (nearest x4) and screenshots for review.
local CELL=28; local COLS=4; local SC=4
local canvas
local function C(c,a) love.graphics.setColor(c[1],c[2],c[3],a or 1) end
-- generic sprite: rows of chars -> 1px rects via per-sprite palette
local function spr(a,pal,ox,oy) for r=1,#a do local row=a[r] for c=1,#row do local p=pal[row:sub(c,c)]
  if p then C(p); love.graphics.rectangle("fill",ox+c-1,oy+r-1,1,1) end end end end

local M = {}  -- name -> {pal=, rows=}
M.slime={ pal={O={0.12,0.28,0.16},b={0.34,0.72,0.42},h={0.5,0.86,0.56},d={0.2,0.46,0.28},w={0.95,0.97,0.9},e={0.1,0.12,0.1}},
 rows={"....OOOOOO....","..OObbbbbbOO..",".ObbhhhhbbbbO.","ObbbbbbbbbbbbO","ObwwbbbbwwbbbO","ObweObbbbweObO","ObbbbbbbbbbbbO","ObbbbbbbbbbbbO","Odbbbbbbbbbbd O".."",".OdddddddddddO","..OOOOOOOOOO.."} }
M.bat={ pal={O={0.10,0.08,0.12},b={0.42,0.30,0.52},h={0.58,0.44,0.7},e={0.95,0.7,0.2},f={0.95,0.95,0.95}},
 rows={"O..........O","OO........OO","ObO.OOOO.ObO","ObbOObbOObbO","ObbbbbbbbbbO",".ObbeeeebO..",".ObbbbbbbO..","..ObffffbO..","...OffffO...","....OOOO...."} }
M.boar={ pal={O={0.16,0.10,0.08},b={0.45,0.30,0.22},h={0.6,0.42,0.3},d={0.30,0.20,0.14},e={0.9,0.5,0.2},t={0.92,0.92,0.85}},
 rows={".....OOOOO....","...OOhhhhhO...","..OdbbbbbbbO..",".ObbbbbbbbbbbO","Obhhbbbbbbbbb O".."","Obbbbbbbbbbe bO".."","tObbbbbbbbbbbO",".ObbbbbbbbbbO.",".O.OO..OO.O..","..O.O..O.O..."} }
M.wolf={ pal={O={0.10,0.10,0.14},b={0.46,0.48,0.55},h={0.62,0.64,0.72},d={0.30,0.31,0.38},e={0.95,0.75,0.25}},
 rows={"O.O.........","OhO.OOOO....","OhhOhhhhO...","OdhhhhhhhO.OO",".OhhhhhhhhhhO",".OhhhhhhhhdO.","OebhhhhhhbO..",".OhhhhhhhhO..","..O.OO.OO.O..","..O.OO.OO...."} }
M.ghost={ pal={O={0.55,0.6,0.78},b={0.78,0.84,0.96},h={0.92,0.95,1.0},e={0.2,0.25,0.45}},
 rows={"...OOOOOO...","..ObbbbbbO..",".ObhhhhhbbO.","ObhhhhhhhhbO","ObheeheehhbO","Obhhhhhhhh bO".."","ObbbbbbbbbbO","Obb O bb O bbO".."",".O.O..O..O.."} }
M.golem={ pal={O={0.14,0.14,0.16},b={0.45,0.46,0.52},h={0.6,0.62,0.68},d={0.30,0.31,0.36},e={0.5,0.85,0.95}},
 rows={"..OOOOOOOO..",".OhhhhhhhhO.","OhheehheehhO","OhhhhhhhhhhO","OdhhhhhhhhdO","OhhOhhhhOhhO","OhhhhhhhhhhO",".OdhhhhhhdO.",".O.OOOO.O O.".."",".OO....OO..."} }
M.ogre={ pal={O={0.12,0.16,0.10},b={0.40,0.58,0.32},h={0.52,0.72,0.42},d={0.26,0.40,0.22},e={0.95,0.85,0.3},t={0.92,0.9,0.8}},
 rows={"...OOOOOO...","..OhhhhhhO..",".OheeeehhO..",".OhhhhhhhhO.","tOhhhbbhhhOt","OhhhhhhhhhhO","OdhhhhhhhhdO",".OhhhhhhhhO.",".OhO..OhO...",".OO....OO..."} }
M.dragon={ pal={O={0.30,0.10,0.10},h={0.80,0.32,0.27},e={0.98,0.85,0.32},w={0.50,0.18,0.16}},
 rows={"...O....O...","..OhO..OhO..","..OhhOOhhO..",".OhhhhhhhhO.",".OheehheehO.",".OhhhhhhhhO.","OwhhhhhhhhwO","OwwOhhhhOwwO",".OOOhhhhOOO.","...OhhhhO...","...OO..OO..."} }
M.skeleton={ pal={O={0.2,0.2,0.18},b={0.86,0.86,0.8},h={0.96,0.96,0.92},e={0.9,0.3,0.2},d={0.6,0.6,0.55}},
 rows={"...OOOO...","..ObbbbO..",".ObheehbO.",".ObhhhhbO.","..ObbbbO..","...ObO O...".."","O.ObbbbO.O","OObbbbbbOO",".O.ObbO.O.","...O..O...","..OO..OO.."} }
M.beetle={ pal={O={0.10,0.12,0.08},b={0.30,0.50,0.24},h={0.46,0.7,0.34},e={0.95,0.8,0.2},d={0.18,0.32,0.14}},
 rows={"..O.OO.O..",".ObOOOObO.","O.ObhhbO.O","OObhhhhbOO","ObhdhhdhbO","ObhhhhhhbO","ObheehbO..".."","OObhhhhbOO",".O.OOOO.O.","..O....O.."} }

local order={"slime","bat","boar","wolf","ghost","golem","ogre","dragon","skeleton","beetle"}
local font
function love.load()
  font=love.graphics.newFont("assets/NotoSansSC-Regular.otf",10); font:setFilter("nearest","nearest")
  local rows=math.ceil(#order/COLS)
  canvas=love.graphics.newCanvas(COLS*CELL+8, rows*(CELL+8)+8); canvas:setFilter("nearest","nearest")
end
local fr=0
function love.update(dt) fr=fr+1; if fr==3 then love.event.quit() end end
function love.draw()
  love.graphics.setCanvas(canvas); love.graphics.clear(0.12,0.13,0.18)
  for i,nm in ipairs(order) do local c=(i-1)%COLS; local r=math.floor((i-1)/COLS)
    local ox=4+c*CELL+6; local oy=4+r*(CELL+8)+2
    -- tile bg
    C({0.16,0.17,0.22}); love.graphics.rectangle("fill",4+c*CELL,4+r*(CELL+8),CELL,CELL)
    local m=M[nm]; if m then spr(m.rows,m.pal,ox,oy) end
  end
  love.graphics.setCanvas()
  love.graphics.setColor(1,1,1,1); love.graphics.draw(canvas,0,0,0,SC,SC)
  -- labels (smooth font on top, just for the sheet)
  love.graphics.setFont(font)
  for i,nm in ipairs(order) do local c=(i-1)%COLS; local r=math.floor((i-1)/COLS)
    love.graphics.setColor(0.7,0.72,0.8); love.graphics.printf(nm,(4+c*CELL)*SC,(4+r*(CELL+8)+CELL)*SC+1,CELL*SC,"center") end
  if fr==1 then love.graphics.captureScreenshot("monsters.png") end
end
