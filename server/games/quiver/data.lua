-- ============================================================================
-- QUIVER 静态数据 —— 全部不变的数据表 + 数值锚点常量。
-- return 单个表 D；main.lua 顶部 local D=require("data") 后用 D.SKILLS 等引用。
-- 派生表(RAR/BP/ARROWS/ARROW/EQUIP_POS/SLOTS_L/SLOTS_R)在本文件构建好再 return。
--
-- ★ 数值锚点（一切由此推导，自洽不膨胀）：
--   武器两条基础属性：攻击力区间 wmin~wmax + 攻速 wspeed(次/秒)。慢弓伤害高/快弓伤害低，武器 DPS 守恒。
--   1 STR=+1攻击(加到攻击区间) ; 1 AGI=+0.6%攻速(乘在武器攻速上)+0.04%暴击 ; 1 STA=+6生命
--   装备预算 budget = GEAR_BUDGET * ilvl * rarity.mult * slot.weight
--   武器 DPS 贡献 = budget * WEAPON_DPS_K（与速度无关）；单发伤害 = 攻击区间随机 × 箭档倍率 × 暴击 × (1-减伤)
--   角色每级 +2力 +2敏 +3耐（慢），经验需求 80*L^1.6
-- ============================================================================

local D = {}

-- ---- 设计空间 / 战斗布景 / 数值锚点常量 ----
D.DESIGN_W, D.DESIGN_H = 480, 800
D.ENTER_TIME, D.DEATH_TIME = 0.6, 0.6
D.ENEMY_HOME_X = D.DESIGN_W * 0.72
-- 遭遇式采集：寻找→遇到→判定→采集 的阶段时长 + 资源节点停靠位
D.GATHER_SEARCH, D.GATHER_FOUND, D.GATHER_DONE = 0.7, 0.35, 0.3
D.NODE_HOME_X = D.DESIGN_W * 0.66
D.GEAR_BUDGET = 4
D.CRIT_MULT = 2.0
D.ARMOR_K = 160
D.WEAPON_DPS_K = 0.55          -- 武器 DPS 系数(= 旧基础攻速)；武器伤害区间由它与攻速反推，保证 DPS 守恒
D.WEAPON_SPEED_DEFAULT = 0.55  -- 无武器时的兜底攻速
D.BAG_SLOTS = 24

-- ============================================================================
-- 数据
-- ============================================================================
D.RARITIES = {
    { id="poor",      name="粗糙",  mult=0.6, affixes=0, color={0.6,0.6,0.62},   src="field"   },
    { id="common",    name="普通",  mult=0.8, affixes=0, color={0.92,0.92,0.95}, src="field"   },
    { id="uncommon",  name="优秀",  mult=1.0, affixes=1, color={0.4,0.85,0.4},   src="field"   },
    { id="rare",      name="精良",  mult=1.6, affixes=2, color={0.35,0.6,1.0},   src="field"   },
    { id="epic",      name="史诗",  mult=2.6, affixes=3, color={0.75,0.4,1.0},   src="dungeon" },
    { id="legendary", name="传说",  mult=4.0, affixes=4, color={1.0,0.62,0.15},  src="dungeon" },
}
D.RAR = {}; for i,r in ipairs(D.RARITIES) do D.RAR[r.id]=r; r.tier=i end

-- WoW 式装备栏：左列防具，右列武器/首饰。kind 决定主属性，w 是该槽预算权重。
D.SLOTS = { "head","shoulder","chest","hands","legs","feet","neck","ring","trinket","bow","quiver" }
D.SLOT_INFO = {
    head     = { name="头部",   kind="armor",   w=0.9,  col="L" },
    shoulder = { name="肩部",   kind="armor",   w=0.75, col="L" },
    chest    = { name="胸甲",   kind="armor",   w=1.0,  col="L" },
    hands    = { name="护手",   kind="armor",   w=0.75, col="L" },
    legs     = { name="腿甲",   kind="armor",   w=1.0,  col="L" },
    feet     = { name="鞋子",   kind="armor",   w=0.75, col="L" },
    neck     = { name="项链",   kind="jewelry", w=0.56, col="R" },
    ring     = { name="戒指",   kind="jewelry", w=0.56, col="R" },
    trinket  = { name="饰品",   kind="jewelry", w=0.7,  col="R" },
    bow      = { name="弓",     kind="weapon",  w=2.0,  col="R" },
    quiver   = { name="箭袋",   kind="quiver",  w=0.7,  col="R" },
}
D.SLOTS_L = { "head","shoulder","chest","hands","legs","feet" }
D.SLOTS_R = { "neck","ring","trinket","bow","quiver" }
D.EQUIP_POS = {}  -- slot -> {col="L"/"R", idx}
for i,s in ipairs(D.SLOTS_L) do D.EQUIP_POS[s]={col="L",idx=i} end
for i,s in ipairs(D.SLOTS_R) do D.EQUIP_POS[s]={col="R",idx=i} end
D.TIER_PREFIX = { "破旧", "精铁", "精钢", "符文", "巨龙" }

D.ATTRS = { "str","agi","sta" }
D.ATTR_NAME = { str="力量", agi="敏捷", sta="耐力" }
D.ATTR_COLOR = { str={0.9,0.4,0.35}, agi={0.5,0.85,0.55}, sta={0.6,0.7,0.95} }

D.AFFIXES = {
    { key="str", name="+%d 力量" }, { key="agi", name="+%d 敏捷" },
    { key="sta", name="+%d 耐力" }, { key="crit", name="暴击 +%d%%", pct=true },
}

-- 原材料：每种由一类挂机产出（中间材料 ironbar/leather 也走 mat，靠制造产出）
D.MATERIALS = { "wood","ore","herb" }   -- 采集主材（活动菜单/采集只产这三种）
D.MAT_NAME = { wood="木材", ore="矿石", herb="草药", ironbar="精铁锭", leather="皮革" }
D.MAT_COLOR = { wood={0.62,0.44,0.24}, ore={0.7,0.72,0.78}, herb={0.45,0.8,0.45},
                ironbar={0.8,0.82,0.88}, leather={0.7,0.5,0.32} }
-- 消耗品（药剂等，走背包可堆叠）
D.POT_NAME = { hppot="疗伤药剂" }
D.POT_COLOR = { hppot={0.9,0.35,0.4} }

-- 物品说明文案
D.MAT_DESC = { wood="砍柴所得。制作各种箭矢的基础材料。", ore="采矿所得。用于铁箭及以上。", herb="采药所得。用于猎手箭、符文箭、药剂。",
    ironbar="由矿石锻造。高级图谱的中间材料。", leather="由草药与精铁锭鞣制。高级制造材料。" }
D.POT_DESC = { hppot="战斗中生命过低时自动饮用，回复部分生命。" }

-- 统一制造图谱：制箭只是「造箭类图谱」，与中间材料/药剂共用同一套 can_craft/do_craft。
-- out.kind: arrow(进箭袋,带 mult/color 供战斗) | mat(进背包) | potion(进背包)
-- req=所需制造职业等级；time=制作归一化耗时；learn=start(初始)|level(到级自动)|master(技能大师)
D.ARROW_BATCH = 20
D.CRAFT_BASE  = 0.20   -- 制作进度基准：速率 = CRAFT_BASE * craft.lvl / bp.time
D.BLUEPRINTS = {
    { id="wood",   name="木箭",   req=1, time=4, learn="start",  out={kind="arrow",  id="wood",   qty=D.ARROW_BATCH, mult=1.0,  color={0.62,0.46,0.26}}, cost={ wood=3 } },
    { id="iron",   name="铁箭",   req=2, time=5, learn="level",  out={kind="arrow",  id="iron",   qty=D.ARROW_BATCH, mult=1.35, color={0.72,0.74,0.8}},  cost={ wood=2, ore=3 } },
    { id="hunter", name="猎手箭", req=4, time=6, learn="level",  out={kind="arrow",  id="hunter", qty=D.ARROW_BATCH, mult=1.75, color={0.5,0.85,0.55}},  cost={ wood=2, ore=2, herb=3 } },
    { id="rune",   name="符文箭", req=7, time=8, learn="master", out={kind="arrow",  id="rune",   qty=D.ARROW_BATCH, mult=2.3,  color={0.78,0.5,1.0}},   cost={ wood=3, ore=4, herb=4 } },
    { id="ironbar",name="精铁锭", req=3, time=6, learn="level",  out={kind="mat",    id="ironbar",qty=1,             color={0.8,0.82,0.88}},  cost={ ore=4 } },
    { id="hppot",  name="疗伤药剂",req=2,time=5, learn="level",  out={kind="potion", id="hppot",  qty=1,             color={0.9,0.35,0.4}},   cost={ herb=4 } },
    { id="leather",name="鞣制皮革",req=5,time=7, learn="master", out={kind="mat",    id="leather",qty=2,             color={0.7,0.5,0.32}},   cost={ herb=3, ironbar=1 } },
}
D.BP = {}; for _,b in ipairs(D.BLUEPRINTS) do D.BP[b.id]=b end
-- 箭矢档位（从图谱里 out.kind=="arrow" 派生，供战斗/显示按 id 查倍率与颜色；低→高有序）
D.ARROWS, D.ARROW = {}, {}
for _,b in ipairs(D.BLUEPRINTS) do if b.out.kind=="arrow" then
    local a={ id=b.out.id, name=b.name, mult=b.out.mult, color=b.out.color }
    D.ARROWS[#D.ARROWS+1]=a; D.ARROW[a.id]=a
end end

-- 角色技能（普通攻击也算技能）。数据驱动：
--   effect: shot(发射,可多重) | dot(中毒持续伤害) | heal(回血) | buff(限时攻速/暴击)
--   dmg_mult 乘在「攻击×箭档×暴击」上(主动技能不耗箭,见 do_shot)。dmg_mult 已压低防膨胀。
--   learn: {lvl=N} 到级自动学 | {master=true,cost_g=,cost_mat={}} 技能大师处学
--   prio: 多个技能就绪时按 prio 降序确定性选一个；普通射击 prio=0 兜底。
D.SKILLS = {
    shoot  ={ id="shoot",  name="普通射击", cd=0,    mp_cost=0,  prio=0, effect="shot", dmg_mult=1.0,  multi=1, color={0.8,0.8,0.85}, learn={lvl=1} },
    power  ={ id="power",  name="强力射击", cd=3.0,  mp_cost=8,  prio=5, effect="shot", dmg_mult=1.7,  multi=1, color={1.0,0.7,0.2},  learn={lvl=3} },
    double ={ id="double", name="双重射击", cd=4.5,  mp_cost=10, prio=4, effect="shot", dmg_mult=0.75, multi=2, color={0.5,0.8,1.0},  learn={lvl=6} },
    aimed  ={ id="aimed",  name="瞄准射击", cd=6.0,  mp_cost=14, prio=6, effect="shot", dmg_mult=1.5,  multi=1, color={0.55,0.9,0.75},learn={master=true, cost_g=120, cost_mat={ore=10}} },
    poison ={ id="poison", name="毒箭",     cd=7.0,  mp_cost=12, prio=7, effect="dot",  dmg_mult=0.5,  dot_mult=0.3, dot_dur=4, dot_tick=1, color={0.5,0.85,0.45}, learn={master=true, cost_g=150, cost_mat={herb=12}} },
    rapid  ={ id="rapid",  name="疾风蓄势", cd=12.0, mp_cost=18, prio=8, effect="buff", buff="haste", buff_amt=0.4,  buff_dur=5, color={0.5,0.9,0.9},  learn={lvl=10} },
    hawkeye={ id="hawkeye",name="鹰眼",     cd=16.0, mp_cost=20, prio=8, effect="buff", buff="crit",  buff_amt=0.25, buff_dur=6, color={1.0,0.55,0.2}, learn={master=true, cost_g=220, cost_mat={herb=8,ore=8}} },
    mend   ={ id="mend",   name="包扎",     cd=14.0, mp_cost=14, prio=9, effect="heal", heal_pct=0.30, color={0.5,0.85,0.5}, learn={master=true, cost_g=100, cost_mat={herb=10}} },
}
D.MP_REGEN = 6   -- 法力每秒回复
D.SKILL_ORDER = { "shoot","power","double","aimed","poison","rapid","hawkeye","mend" }

-- 挂机活动：一次只挂一种。group 体现优先级层级：idle(挂机) > combat(战斗) > sub(副职业)。
D.ACTIVITIES = {
    rest    = { name="挂机", kind="rest",   group="idle",   ord=1 },
    combat  = { name="战斗", kind="combat", group="combat", ord=1 },
    woodcut = { name="砍柴", kind="gather", group="sub", ord=1, mat="wood", base=0.8 },
    mining  = { name="采矿", kind="gather", group="sub", ord=2, mat="ore",  base=0.6 },
    herb    = { name="采药", kind="gather", group="sub", ord=3, mat="herb", base=0.7 },
    fletch  = { name="制造", kind="craft",  group="sub", ord=4 },
}
D.ACT_ORDER = { "rest", "combat", "woodcut", "mining", "herb", "fletch" }
D.ACT_GROUPS = {
    { id="idle",   name="挂机",   col={0.5,0.7,0.95} },
    { id="combat", name="战斗",   col={0.88,0.3,0.3} },
    { id="sub",    name="副职业", col={0.6,0.55,0.4} },
}

-- 地区三档 → 玩家等级区间（仅用于地区菜单分组/筛选展示，不参与战斗公式）
D.TIER_BAND = {
    low  = { name="低级", pmin=1,  pmax=15, color={0.5,0.8,0.55} },
    mid  = { name="中级", pmin=16, pmax=35, color={0.95,0.8,0.4} },
    high = { name="高级", pmin=36, pmax=60, color={0.9,0.45,0.5} },
}
D.TIER_ORDER = { "low", "mid", "high" }
-- 第一期 20 区。lo/hi=怪物&节点等级下/上限；ilo/ihi=掉落装等区间；
-- rar=普通掉落稀有度池(4)，rar_elite=精英/稀有掉落池(2)；nodes 同时驱动采集(见 Step5)。
-- kinds 只做展示名+等级载体，产物仍归并到 wood/ore/herb 三种。
D.REGIONS = {
    -- ===== 低级 1-15 =====
    { id="meadow",  name="晨曦绿野", tier="low", lo=1, hi=4,  ilo=2, ihi=6,  rar={"poor","common","common","uncommon"}, rar_elite={"uncommon","rare"}, enemies={"boar","wolf"},          nodes={ wood={kinds={"oak"},lvloff=0},         ore={kinds={"copper"},lvloff=-1},     herb={kinds={"clover"},lvloff=0} } },
    { id="brook",   name="低语溪谷", tier="low", lo=3, hi=6,  ilo=4, ihi=9,  rar={"poor","common","common","uncommon"}, rar_elite={"uncommon","rare"}, enemies={"boar","wolf","bandit"},  nodes={ wood={kinds={"oak","birch"},lvloff=0}, ore={kinds={"copper"},lvloff=0},      herb={kinds={"clover","mint"},lvloff=0} } },
    { id="downs",   name="风吹荒原", tier="low", lo=5, hi=8,  ilo=6, ihi=11, rar={"common","common","uncommon","uncommon"}, rar_elite={"uncommon","rare"}, enemies={"wolf","bandit"},     nodes={ wood={kinds={"birch"},lvloff=-1},      ore={kinds={"copper","tin"},lvloff=1}, herb={kinds={"mint"},lvloff=0} } },
    { id="darkwood",name="幽暗森林", tier="low", lo=7, hi=10, ilo=8, ihi=14, rar={"common","uncommon","uncommon","rare"}, rar_elite={"rare","epic"}, enemies={"wolf","bandit","ogre"},   nodes={ wood={kinds={"birch","ash"},lvloff=1}, ore={kinds={"tin"},lvloff=0},          herb={kinds={"mint","sage"},lvloff=0} } },
    { id="quarry",  name="碎石矿场", tier="low", lo=9, hi=12, ilo=10,ihi=16, rar={"common","uncommon","uncommon","rare"}, rar_elite={"rare","epic"}, enemies={"bandit","ogre"},          nodes={ wood={kinds={"ash"},lvloff=0},         ore={kinds={"tin","iron"},lvloff=2},  herb={kinds={"sage"},lvloff=-1} } },
    { id="fen",     name="腐沼湿地", tier="low", lo=11,hi=14, ilo=12,ihi=18, rar={"uncommon","uncommon","rare","rare"}, rar_elite={"rare","epic"}, enemies={"wolf","ogre","wraith"},     nodes={ wood={kinds={"ash","yew"},lvloff=0},   ore={kinds={"iron"},lvloff=0},        herb={kinds={"sage","nightcap"},lvloff=1} } },
    -- ===== 中级 16-35 =====
    { id="ruins",   name="沉没遗迹", tier="mid", lo=15,hi=19, ilo=16,ihi=23, rar={"uncommon","rare","rare","epic"}, rar_elite={"epic","legendary"}, enemies={"bandit","ogre","wraith"}, nodes={ wood={kinds={"yew"},lvloff=0},         ore={kinds={"iron","silver"},lvloff=1},herb={kinds={"nightcap"},lvloff=0} } },
    { id="canyon",  name="赤红峡谷", tier="mid", lo=18,hi=22, ilo=20,ihi=27, rar={"uncommon","rare","rare","epic"}, rar_elite={"epic","legendary"}, enemies={"ogre","wraith","golem"},  nodes={ wood={kinds={"yew"},lvloff=-1},        ore={kinds={"silver"},lvloff=2},      herb={kinds={"nightcap","emberbloom"},lvloff=1} } },
    { id="hollow",  name="回响洞窟", tier="mid", lo=21,hi=25, ilo=23,ihi=31, rar={"rare","rare","epic","epic"}, rar_elite={"epic","legendary"}, enemies={"wraith","golem","ogre"},      nodes={ wood={kinds={"yew","ironwood"},lvloff=0},ore={kinds={"silver","mithril"},lvloff=1},herb={kinds={"emberbloom"},lvloff=0} } },
    { id="peak",    name="霜寒峰",   tier="mid", lo=24,hi=28, ilo=26,ihi=34, rar={"rare","rare","epic","epic"}, rar_elite={"epic","legendary"}, enemies={"ogre","wraith","golem"},      nodes={ wood={kinds={"ironwood"},lvloff=0},    ore={kinds={"mithril"},lvloff=1},     herb={kinds={"emberbloom","frostlily"},lvloff=1} } },
    { id="wastes",  name="灰烬废土", tier="mid", lo=27,hi=31, ilo=29,ihi=37, rar={"rare","epic","epic","legendary"}, rar_elite={"epic","legendary"}, enemies={"wraith","golem"},        nodes={ wood={kinds={"ironwood"},lvloff=-1},   ore={kinds={"mithril"},lvloff=2},     herb={kinds={"frostlily"},lvloff=0} } },
    { id="catacomb",name="尘封地穴", tier="mid", lo=30,hi=34, ilo=32,ihi=40, rar={"rare","epic","epic","legendary"}, rar_elite={"epic","legendary"}, enemies={"wraith","golem","ogre"}, nodes={ wood={kinds={"ironwood","darkoak"},lvloff=0},ore={kinds={"mithril","adamant"},lvloff=1},herb={kinds={"frostlily","mandrake"},lvloff=0} } },
    -- ===== 高级 36-60 =====
    { id="spire",   name="苍穹尖塔", tier="high",lo=35,hi=40, ilo=37,ihi=46, rar={"epic","epic","legendary","legendary"}, rar_elite={"legendary","legendary"}, enemies={"golem","frost"},   nodes={ wood={kinds={"darkoak"},lvloff=0},     ore={kinds={"adamant"},lvloff=1},     herb={kinds={"mandrake"},lvloff=0} } },
    { id="abyss",   name="深渊裂口", tier="high",lo=39,hi=44, ilo=41,ihi=50, rar={"epic","epic","legendary","legendary"}, rar_elite={"legendary","legendary"}, enemies={"wraith","voidcat"},nodes={ wood={kinds={"darkoak"},lvloff=-1},    ore={kinds={"adamant"},lvloff=2},     herb={kinds={"mandrake","voidbloom"},lvloff=1} } },
    { id="cinder",  name="炽炎熔狱", tier="high",lo=43,hi=48, ilo=45,ihi=54, rar={"epic","legendary","legendary","legendary"}, rar_elite={"legendary","legendary"}, enemies={"drake","golem"}, nodes={ wood={kinds={"darkoak","emberwood"},lvloff=0},ore={kinds={"adamant","starsteel"},lvloff=1},herb={kinds={"voidbloom"},lvloff=0} } },
    { id="glacier", name="永冻冰川", tier="high",lo=47,hi=52, ilo=49,ihi=58, rar={"epic","legendary","legendary","legendary"}, rar_elite={"legendary","legendary"}, enemies={"frost","golem"}, nodes={ wood={kinds={"emberwood"},lvloff=0},   ore={kinds={"starsteel"},lvloff=1},   herb={kinds={"voidbloom","frostlily"},lvloff=-1} } },
    { id="rift",    name="虚空断界", tier="high",lo=51,hi=56, ilo=53,ihi=62, rar={"legendary","legendary","legendary","legendary"}, rar_elite={"legendary","legendary"}, enemies={"voidcat","revenant"}, nodes={ wood={kinds={"emberwood"},lvloff=-1},ore={kinds={"starsteel"},lvloff=2},   herb={kinds={"voidbloom"},lvloff=1} } },
    { id="throne",  name="陨灭王座", tier="high",lo=55,hi=60, ilo=57,ihi=66, rar={"legendary","legendary","legendary","legendary"}, rar_elite={"legendary","legendary"}, enemies={"drake","revenant","golem"}, nodes={ wood={kinds={"emberwood","worldroot"},lvloff=0},ore={kinds={"starsteel","voidiron"},lvloff=1},herb={kinds={"voidbloom","mandrake"},lvloff=0} } },
}
D.ENEMY_ARCH = {
    boar  ={ name="野猪",   hp=1.0, dmg=1.0, armor=0.3, spd=0.55, color={0.6,0.45,0.35} },
    wolf  ={ name="野狼",   hp=0.8, dmg=1.2, armor=0.2, spd=0.85, color={0.5,0.5,0.55} },
    bandit={ name="强盗",   hp=1.1, dmg=1.1, armor=0.5, spd=0.6,  color={0.7,0.5,0.3} },
    ogre  ={ name="食人魔", hp=1.8, dmg=1.5, armor=0.6, spd=0.4,  color={0.45,0.6,0.3} },
    wraith={ name="幽魂",   hp=1.2, dmg=1.6, armor=0.3, spd=0.7,  color={0.55,0.45,0.75} },
    golem ={ name="石巨人", hp=2.6, dmg=1.4, armor=1.2, spd=0.35, color={0.6,0.62,0.68} },
    -- 高级敌型（36-60 高区用）
    frost   ={ name="霜魔",     hp=1.5, dmg=1.7, armor=0.5, spd=0.6,  color={0.6,0.8,0.95} },
    voidcat ={ name="虚空兽",   hp=1.4, dmg=2.0, armor=0.4, spd=0.78, color={0.55,0.4,0.7} },
    drake   ={ name="幼龙",     hp=2.2, dmg=1.8, armor=0.9, spd=0.5,  color={0.75,0.4,0.32} },
    revenant={ name="亡灵骑士", hp=1.9, dmg=1.6, armor=1.1, spd=0.55, color={0.5,0.55,0.62} },
}
-- 精英/稀有：概率 p、hp/atk/armor 放大、装等加成、稀有度升档概率。
-- ★ atk 系数保守（elite 1.15 / rare 1.3），等级用区间随机而非锁上限，避免低区强制阵亡。
D.ENEMY_RANK = {
    normal = { p=1.00, hp=1.0, atk=1.0,  armor=1.0, ilvl_bonus=0, rar_up=0.0, tag="",     color_mul=1.0  },
    elite  = { p=0.07, hp=1.6, atk=1.15, armor=1.2, ilvl_bonus=2, rar_up=0.5, tag="精英", color_mul=1.15 },
    rare   = { p=0.02, hp=2.2, atk=1.3,  armor=1.3, ilvl_bonus=4, rar_up=1.0, tag="稀有", color_mul=1.3  },
}

-- 采集节点：按 mat 给「耐久系数 hp、基础产量 yield」；NODE_NAME 是 kinds 展示名(产物仍归 wood/ore/herb)
D.NODE_BASE = { wood={hp=1.0,yield=1.0}, ore={hp=1.4,yield=0.8}, herb={hp=0.8,yield=0.9} }
D.MAT_REQ_FAIL = { wood="树木等级不足", ore="矿石等级不足", herb="草药等级不足" }
D.NODE_NAME = {
    oak="橡木", birch="桦木", ash="梣木", yew="紫杉", ironwood="铁木", darkoak="黑栎", emberwood="炽炎木", worldroot="世界根",
    copper="铜矿", tin="锡矿", iron="铁矿", silver="银矿", mithril="秘银", adamant="精金", starsteel="星钢", voidiron="虚空铁",
    clover="三叶草", mint="薄荷", sage="鼠尾草", nightcap="夜帽菇", emberbloom="炽焰花", frostlily="霜百合", mandrake="曼德拉", voidbloom="虚空花",
}

D.UI = {
    bg={0.07,0.08,0.12}, panel={0.12,0.13,0.19,0.97}, line={0.26,0.28,0.36},
    text={0.93,0.94,0.97}, dim={0.55,0.57,0.64}, good={0.4,0.85,0.5}, bad={0.88,0.3,0.3},
    gold={1.0,0.84,0.25}, xp={0.45,0.6,1.0}, btn={0.25,0.55,1.0},
}

return D
