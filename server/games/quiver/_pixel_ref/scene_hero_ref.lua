-- Pixel scene v2: cohesive dusk palette, rooted trees, believable composition.
local LW,LH,SC = 160,267,3
local canvas
-- curated limited palette (cohesive dusk forest)
local sky_top={0.09,0.08,0.18}; local sky_mid={0.17,0.15,0.31}; local sky_hor={0.34,0.27,0.42}; local warm={0.55,0.36,0.44}
local moonC={0.94,0.91,0.80}
local hillFar={0.21,0.21,0.35}; local hillMid={0.15,0.23,0.31}
local grass={0.25,0.44,0.33}; local grassHi={0.35,0.57,0.40}; local grassDk={0.17,0.33,0.26}
local dirt={0.44,0.33,0.23}; local dirtHi={0.55,0.43,0.30}
local fol={0.23,0.50,0.34}; local folHi={0.37,0.65,0.45}; local folDk={0.14,0.33,0.24}
local trunk={0.41,0.28,0.18}; local trunkDk={0.27,0.18,0.11}
local fire1={0.99,0.80,0.38}; local fire2={0.97,0.52,0.21}
local acc={0.96,0.75,0.34}; local fly={0.87,0.93,0.62}
local function C(c,a) love.graphics.setColor(c[1],c[2],c[3],a or 1) end
local function lerp(a,b,t) return {a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t,a[3]+(b[3]-a[3])*t} end
local HOR=150

local function tree(cx,baseY,size,tint)
  tint=tint or 0
  local f=lerp(fol,hillFar,tint); local fh=lerp(folHi,hillFar,tint*0.7); local fd=lerp(folDk,hillFar,tint)
  local tw=math.max(2,math.floor(size*0.16)); local th=math.floor(size*0.55)
  C(trunkDk); love.graphics.rectangle("fill",cx-math.ceil(tw/2),baseY-th,tw+1,th)
  C(trunk); love.graphics.rectangle("fill",cx-math.ceil(tw/2),baseY-th,tw,th)
  local r=size*0.55; local ccy=baseY-th-r*0.7
  C(fd); love.graphics.circle("fill",cx,ccy+1,r+1)            -- outline/shadow
  C(f);  love.graphics.circle("fill",cx,ccy,r)
  C(fh); love.graphics.circle("fill",cx-r*0.32,ccy-r*0.32,r*0.5)  -- top-left highlight
  C(fd); love.graphics.rectangle("fill",cx+r*0.3,ccy+r*0.2,2,2)   -- leaf texture
end
local function bush(cx,by,s)
  C(folDk); love.graphics.circle("fill",cx,by,s+1)
  C(fol); love.graphics.circle("fill",cx,by,s); C(folHi); love.graphics.circle("fill",cx-s*0.3,by-s*0.3,s*0.45)
end
local function rock(cx,by,s) C({0.30,0.31,0.36}); love.graphics.polygon("fill",cx-s,by, cx-s*0.4,by-s, cx+s*0.5,by-s*0.8, cx+s,by); C({0.42,0.43,0.48}); love.graphics.polygon("fill",cx-s*0.4,by-s, cx+s*0.1,by-s*0.5, cx-s*0.2,by-s*0.4) end

-- 骨骼火柴人主角：代码关节驱动(非PNG帧)，大头chibi比例，拉弓姿势 + 呼吸
local OUTL={0.11,0.09,0.12}; local SKIN={0.93,0.74,0.52}; local HOOD={0.28,0.50,0.36}; local HOODHI={0.38,0.64,0.46}
local function bone(x1,y1,x2,y2,w,col)
  C(col); local d=math.sqrt((x2-x1)^2+(y2-y1)^2); local steps=math.max(2,math.ceil(d))
  for i=0,steps do local u=i/steps; love.graphics.circle("fill",x1+(x2-x1)*u,y1+(y2-y1)*u,w) end
end
local function draw_hero(cx,gy,t)
  local br=math.sin(t*2)*0.6
  local pelvis={cx,gy-12}; local chest={cx,gy-19-br}; local head={cx,gy-27-br}; local hr=6
  local sh={cx,gy-19-br}
  local fElb={cx+5,gy-19-br}; local fHand={cx+10,gy-22-br}
  local bElb={cx-4,gy-18-br}; local bHand={cx-2,gy-20-br}
  local kL={cx-3,gy-6}; local fL={cx-5,gy}; local kR={cx+3,gy-6}; local fR={cx+4,gy}
  bone(pelvis[1],pelvis[2],kL[1],kL[2],1.4,OUTL); bone(kL[1],kL[2],fL[1],fL[2],1.4,OUTL)
  bone(pelvis[1],pelvis[2],kR[1],kR[2],1.4,OUTL); bone(kR[1],kR[2],fR[1],fR[2],1.4,OUTL)
  bone(pelvis[1],pelvis[2],chest[1],chest[2],1.7,OUTL)
  bone(sh[1],sh[2],fElb[1],fElb[2],1.3,OUTL); bone(fElb[1],fElb[2],fHand[1],fHand[2],1.3,SKIN)
  bone(sh[1],sh[2],bElb[1],bElb[2],1.3,OUTL); bone(bElb[1],bElb[2],bHand[1],bHand[2],1.3,SKIN)
  C(OUTL); love.graphics.circle("fill",head[1],head[2],hr+0.6)
  C(SKIN); love.graphics.circle("fill",head[1],head[2],hr)
  C(HOOD); love.graphics.arc("fill","pie",head[1],head[2],hr+0.8,math.pi*1.05,math.pi*1.95)
  C(HOODHI); love.graphics.arc("fill","pie",head[1],head[2],hr-1,math.pi*1.15,math.pi*1.5)
  C(OUTL); love.graphics.rectangle("fill",head[1]+2,head[2]-1,1,1)
  C({0.55,0.37,0.20}); love.graphics.setLineStyle("smooth"); love.graphics.setLineWidth(1.4)
  love.graphics.arc("line","open",fHand[1],fHand[2],6,-1.35,1.35)
  C({0.85,0.83,0.7}); love.graphics.setLineWidth(0.8)
  local t1x,t1y=fHand[1]+6*math.cos(-1.35),fHand[2]+6*math.sin(-1.35)
  local t2x,t2y=fHand[1]+6*math.cos(1.35), fHand[2]+6*math.sin(1.35)
  love.graphics.line(t1x,t1y, bHand[1],bHand[2], t2x,t2y)
  C(acc); love.graphics.setLineWidth(1); love.graphics.line(bHand[1],bHand[2], fHand[1]+5,fHand[2])
  love.graphics.polygon("fill", fHand[1]+6,fHand[2], fHand[1]+3,fHand[2]-1.5, fHand[1]+3,fHand[2]+1.5)
end
local function slime(ox,oy,t)
  local b={0.34,0.72,0.42}; local bd={0.16,0.34,0.20}; local bh={0.46,0.84,0.52}
  local sq=math.sin(t*3)*1
  C(bd); love.graphics.ellipse("fill",ox,oy,9,6-sq)
  C(b);  love.graphics.ellipse("fill",ox,oy-1,8,5-sq)
  C(bh); love.graphics.ellipse("fill",ox-2,oy-2,3,2)
  C({0.95,0.97,0.92}); love.graphics.rectangle("fill",ox-3,oy-2,2,2); love.graphics.rectangle("fill",ox+2,oy-2,2,2)
  C({0.1,0.12,0.1}); love.graphics.rectangle("fill",ox-2,oy-1,1,1); love.graphics.rectangle("fill",ox+3,oy-1,1,1)
end

function love.load() canvas=love.graphics.newCanvas(LW,LH); canvas:setFilter("nearest","nearest") end
local function draw_low()
  -- sky gradient (3-stop) + warm horizon band
  for yy=0,HOR-1 do local t=yy/HOR; local col
    if t<0.6 then col=lerp(sky_top,sky_mid,t/0.6) else col=lerp(sky_mid,sky_hor,(t-0.6)/0.4) end
    C(col); love.graphics.rectangle("fill",0,yy,LW,1) end
  C(warm,0.5); love.graphics.rectangle("fill",0,HOR-10,LW,10)
  -- moon + glow + crescent + stars
  C(moonC,0.10); love.graphics.circle("fill",126,30,18)
  C(moonC); love.graphics.circle("fill",126,30,11); C(sky_mid); love.graphics.circle("fill",121,27,10)
  C({1,1,1},0.8); for _,s in ipairs({{20,28},{42,18},{70,40},{150,55},{30,70},{96,22},{60,88}}) do love.graphics.rectangle("fill",s[1],s[2],1,1) end
  -- hills (far cool, mid teal) — sit on horizon
  C(hillFar); love.graphics.ellipse("fill",36,HOR+16,72,30); love.graphics.ellipse("fill",128,HOR+18,64,26)
  C(hillMid); love.graphics.ellipse("fill",92,HOR+24,96,24)
  -- ground plane
  C(grass); love.graphics.rectangle("fill",0,HOR,LW,LH-HOR)
  C(grassHi); love.graphics.rectangle("fill",0,HOR,LW,3)            -- lit top edge
  -- winding dirt path (narrows toward horizon)
  C(dirt); love.graphics.polygon("fill", 60,HOR, 76,HOR, 96,LH, 40,LH)
  C(dirtHi); love.graphics.polygon("fill", 64,HOR, 70,HOR, 74,LH, 58,LH)
  -- grass texture tufts
  for _,g in ipairs({{12,HOR+10},{30,HOR+30},{120,HOR+14},{146,HOR+40},{100,HOR+50},{18,HOR+55}}) do
    C(grassDk); love.graphics.rectangle("fill",g[1],g[2],2,1); C(grassHi); love.graphics.rectangle("fill",g[1],g[2]-1,1,1) end
  -- trees rooted on ground, depth-sorted (back small/cool → front big)
  tree(20,HOR+14,16,0.45); tree(140,HOR+18,18,0.35)
  tree(132,HOR+60,30,0.0); tree(16,HOR+92,40,0.0)
  bush(54,HOR+44,5); bush(150,HOR+96,7); rock(112,HOR+100,6)
  -- campfire (glow halo + logs + flame)
  local fx,fy=86,HOR+78
  C(fire2,0.10); love.graphics.circle("fill",fx,fy,26); C(fire1,0.10); love.graphics.circle("fill",fx,fy,16)
  C(trunkDk); love.graphics.rectangle("fill",fx-7,fy+3,14,3)
  C(fire2); love.graphics.polygon("fill",fx-4,fy+3, fx,fy-9, fx+4,fy+3); C(fire1); love.graphics.polygon("fill",fx-2,fy+3, fx,fy-4, fx+2,fy+3)
  -- characters rooted on ground
  draw_hero(48,HOR+66,0.6); slime(120,HOR+70,1.2)
  -- fireflies
  C(fly,0.9); for _,p in ipairs({{72,HOR+40},{100,HOR+30},{52,HOR+62},{128,HOR+44}}) do love.graphics.rectangle("fill",p[1],p[2],1,1) end
  -- HUD
  C({0.08,0.07,0.10},0.92); love.graphics.rectangle("fill",4,4,LW-8,22); C({0.32,0.27,0.21}); love.graphics.rectangle("line",4,4,LW-8,22)
  C({0.86,0.32,0.30}); for _,p in ipairs({{10,9},{12,9},{9,10},{10,10},{11,10},{12,10},{13,10},{10,11},{11,11},{12,11},{11,12}}) do love.graphics.rectangle("fill",p[1],p[2],1,1) end
  C({0,0,0},0.5); love.graphics.rectangle("fill",18,9,58,5); C({0.40,0.78,0.46}); love.graphics.rectangle("fill",18,9,40,5)
  C(acc); love.graphics.circle("fill",LW-22,12,4); C({0.7,0.5,0.1}); love.graphics.rectangle("fill",LW-22,11,1,2)
end
local fr=0
function love.update(dt) fr=fr+1; if fr==3 then love.event.quit() end end
function love.draw()
  love.graphics.setCanvas(canvas); love.graphics.clear(); draw_low(); love.graphics.setCanvas()
  love.graphics.setColor(1,1,1,1); love.graphics.draw(canvas,0,0,0,SC,SC)
  if fr==1 then love.graphics.captureScreenshot("pixel3.png") end
end
