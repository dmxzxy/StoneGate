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

-- 采集大类：砍柴/采矿/采药三类(活动 mat 字段引用，决定图标形状/节点 hp/产量)。
-- 具体材料是 8 档×3 系=72 主材(D.MATS)，每个材料带 cat(大类)/tier(1-8)/system(系)。
D.MATERIALS = { "wood","ore","herb" }   -- 采集大类(节点/采集职业仍按这三类分)

-- 三系角色：木=箭杆/弓臂/薪炭，矿=箭簇/兵刃/甲胄，草=疗愈/精萃/毒性
D.MAT_SYSTEMS = {
    -- wood
    shaft  = { name="箭杆", cat="wood", role="轻直，制箭杆" },
    bowarm = { name="弓臂", cat="wood", role="韧弹，造弓" },
    char   = { name="薪炭", cat="wood", role="耐烧，炼锭燃料/护甲衬" },
    -- ore
    head   = { name="箭簇", cat="ore",  role="硬利，造箭头" },
    blade  = { name="兵刃", cat="ore",  role="锋锐，造武器" },
    plate  = { name="甲胄", cat="ore",  role="坚韧，造护甲" },
    -- herb
    heal   = { name="疗愈", cat="herb", role="回复药剂" },
    essence= { name="精萃", cat="herb", role="元素/buff 药" },
    toxic  = { name="毒性", cat="herb", role="毒/debuff 与毒箭" },
}
-- 系在每个大类内的顺序(用于 nodes.kinds 排布 / icon 系标记)
D.SYS_BY_CAT = { wood={"shaft","bowarm","char"}, ore={"head","blade","plate"}, herb={"heal","essence","toxic"} }

-- 8 档主材名表(§3.1)。每行 = {tier, 三系名...}，按 cat 顺序：木(shaft/bowarm/char) 矿(head/blade/plate) 草(heal/essence/toxic)
-- id 规则：cat 首字母 + system 缩写 + 档号，如 w_shaft1；保证唯一、可读、迁移可推。
D.MAT_TIER_NAMES = {
    -- T : shaft / bowarm / char | head / blade / plate | heal / essence / toxic
    {1, "橡木","柳木","松木",  "燧石","铜矿","锡矿",  "三叶草","微光花","毒芹"},
    {2, "桦木","榆木","杉木",  "赤铜","青铜砂","铅矿","薄荷","萤草","颠茄"},
    {3, "梣木","槐木","桤木",  "铁矿","磁石","灰铁",  "鼠尾草","星彩花","乌头"},
    {4, "紫杉","山核桃","雪松","银矿","钴矿","镍矿",  "夜帽菇","月华草","鸩羽叶"},
    {5, "铁木","龙骨木","焦木","秘银","精钢砂","玄铁","炽焰花","灵泉草","蚀骨藤"},
    {6, "黑栎","影桦","炭橡",  "精金","寒钢","厚铸石","霜百合","龙息兰","腐心花"},
    {7, "炽炎木","雷击木","黯杉","星钢","烈焰岩","玄武铸","曼德拉","星髓花","蚀魂菇"},
    {8, "世界根","永恒藤","虚影木","虚空铁","噬星矿","神化晶","虚空花","创世露","湮灭孢"},
}
-- 大类基色(按档调亮)：木=褐、矿=灰蓝、草=绿；系做色相微偏
D.MAT_CAT_BASE = { wood={0.55,0.40,0.22}, ore={0.62,0.66,0.74}, herb={0.40,0.74,0.40} }

-- 构建 72 主材：D.MATS(有序列表) / D.MAT(id->def)，并回填 MAT_NAME/COLOR/DESC
D.MATS, D.MAT = {}, {}
do
    local cat_order = { "wood", "ore", "herb" }
    for _,row in ipairs(D.MAT_TIER_NAMES) do
        local tier = row[1]
        local ni = 2
        for _,cat in ipairs(cat_order) do
            local base = D.MAT_CAT_BASE[cat]
            -- 档亮度：T1 暗→T8 亮
            local lift = (tier-1)/7*0.4
            for si,sys in ipairs(D.SYS_BY_CAT[cat]) do
                local name = row[ni]; ni = ni + 1
                local id = cat:sub(1,1).."_"..sys..tier
                -- 系做轻微色相偏移(让三系不撞色)：si=1 偏暖、2 中性、3 偏冷/深
                local tint = { (si-2)*0.06, 0, (2-si)*0.05 }
                local col = { math.min(1, base[1]+lift+tint[1]),
                              math.min(1, base[2]+lift),
                              math.min(1, base[3]+lift+tint[3]) }
                local sysinfo = D.MAT_SYSTEMS[sys]
                local def = { id=id, name=name, cat=cat, tier=tier, system=sys, color=col }
                D.MATS[#D.MATS+1] = def; D.MAT[id] = def
            end
        end
    end
end

-- 二级/特殊材料(本期登记需要用到的；来源接在 gather 副产/怪掉)
D.SECONDARY = {
    feather   = { name="羽毛",   color={0.85,0.85,0.9},  desc="所有箭必需。砍柴偶得鸟巢、野兽怪掉。" },
    eaglefeat = { name="鹰羽",   color={0.7,0.55,0.3},   desc="高级翎羽。+暴击，配弩/物理。" },
    windfeat  = { name="风羽",   color={0.7,0.9,0.95},   desc="轻盈翎羽。+攻速，配短弓叠层。" },
    heavyfeat = { name="重羽",   color={0.5,0.45,0.4},   desc="厚重翎羽。单发更稳更重。" },
    oil       = { name="油",     color={0.35,0.3,0.2},   desc="火箭用。野兽/食人魔怪掉。" },
    hide      = { name="兽皮",   color={0.65,0.45,0.3},  desc="护甲链原料。野兽/人形怪掉，鞣制成皮革。" },
    leather   = { name="皮革",   color={0.7,0.5,0.32},   desc="由兽皮鞣制。护甲与高级制造材料。" },
    bladestone= { name="利刃石", color={0.6,0.62,0.7},   desc="流血箭附材。矿区采矿副产。" },
    sulfur    = { name="硫磺",   color={0.85,0.8,0.3},   desc="爆裂箭附材。矿区副产。" },
    venomsac  = { name="毒囊",   color={0.5,0.75,0.35},  desc="毒箭附材。虫系怪掉。" },
}

-- 原材料表(展示/tooltip 统一查表)：72 主材 + 二级材料 + 旧中间材料(锭/皮)
D.MAT_NAME  = { wood="木材", ore="矿石", herb="草药", ironbar="精铁锭" }
D.MAT_COLOR = { wood={0.62,0.44,0.24}, ore={0.7,0.72,0.78}, herb={0.45,0.8,0.45},
                ironbar={0.8,0.82,0.88} }
D.MAT_DESC  = { wood="砍柴大类。", ore="采矿大类。", herb="采药大类。",
                ironbar="由矿石锻造。高级图谱的中间材料。" }
for _,d in ipairs(D.MATS) do
    local sysn = D.MAT_SYSTEMS[d.system].name
    D.MAT_NAME[d.id]  = d.name
    D.MAT_COLOR[d.id] = d.color
    D.MAT_DESC[d.id]  = sysn.."系 T"..d.tier.."。"..D.MAT_SYSTEMS[d.system].role.."。"
end
for id,s in pairs(D.SECONDARY) do
    D.MAT_NAME[id]=s.name; D.MAT_COLOR[id]=s.color; D.MAT_DESC[id]=s.desc
end

-- 按 cat+tier+system 取材料 id（配方/采集用）。无则 nil。
function D.mat_id(cat, tier, system)
    local d = D.MAT[cat:sub(1,1).."_"..system..tier]
    return d and d.id
end

-- 消耗品（药剂等，走背包可堆叠）
D.POT_NAME = { hppot="疗伤药剂" }
D.POT_COLOR = { hppot={0.9,0.35,0.4} }
D.POT_DESC = { hppot="战斗中生命过低时自动饮用，回复部分生命。" }

-- 统一制造图谱：制箭只是「造箭类图谱」，与中间材料/药剂共用同一套 can_craft/do_craft。
-- out.kind: arrow(进箭袋,带 mult/color 供战斗) | mat(进背包) | potion(进背包)
-- req=所需制造职业等级；time=制作归一化耗时；learn=start(初始)|level(到级自动)|master(技能大师)
D.ARROW_BATCH = 20
D.CRAFT_BASE  = 0.20   -- 制作进度基准：速率 = CRAFT_BASE * craft.lvl / bp.time
D.BLUEPRINTS = {
    { id="wood",   name="木箭",   req=1, time=4, learn="start",  out={kind="arrow",  id="wood",   qty=D.ARROW_BATCH, mult=1.0,  color={0.62,0.46,0.26}}, cost={ w_shaft1=3, feather=1 } },
    { id="iron",   name="铁箭",   req=2, time=5, learn="level",  out={kind="arrow",  id="iron",   qty=D.ARROW_BATCH, mult=1.35, color={0.72,0.74,0.8}},  cost={ w_shaft1=2, o_head1=3, feather=1 } },
    { id="hunter", name="猎手箭", req=4, time=6, learn="level",  out={kind="arrow",  id="hunter", qty=D.ARROW_BATCH, mult=1.75, color={0.5,0.85,0.55}},  cost={ w_shaft2=2, o_head2=2, h_essence1=3, feather=2 } },
    { id="rune",   name="符文箭", req=7, time=8, learn="master", out={kind="arrow",  id="rune",   qty=D.ARROW_BATCH, mult=2.3,  color={0.78,0.5,1.0}},   cost={ w_shaft3=3, o_head3=4, h_essence2=4, feather=2 } },
    { id="ironbar",name="精铁锭", req=3, time=6, learn="level",  out={kind="mat",    id="ironbar",qty=1,             color={0.8,0.82,0.88}},  cost={ o_blade2=4, w_char1=2 } },
    { id="hppot",  name="疗伤药剂",req=2,time=5, learn="level",  out={kind="potion", id="hppot",  qty=1,             color={0.9,0.35,0.4}},   cost={ h_heal1=4 } },
    { id="leather",name="鞣制皮革",req=5,time=7, learn="master", out={kind="mat",    id="leather",qty=2,             color={0.7,0.5,0.32}},   cost={ hide=2, h_heal2=1 } },
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
    aimed  ={ id="aimed",  name="瞄准射击", cd=6.0,  mp_cost=14, prio=6, effect="shot", dmg_mult=1.5,  multi=1, color={0.55,0.9,0.75},learn={master=true, cost_g=120, cost_mat={o_blade1=10}} },
    poison ={ id="poison", name="毒箭",     cd=7.0,  mp_cost=12, prio=7, effect="dot",  dmg_mult=0.5,  dot_mult=0.3, dot_dur=4, dot_tick=1, color={0.5,0.85,0.45}, learn={master=true, cost_g=150, cost_mat={h_toxic1=12}} },
    rapid  ={ id="rapid",  name="疾风蓄势", cd=12.0, mp_cost=18, prio=8, effect="buff", buff="haste", buff_amt=0.4,  buff_dur=5, color={0.5,0.9,0.9},  learn={lvl=10} },
    hawkeye={ id="hawkeye",name="鹰眼",     cd=16.0, mp_cost=20, prio=8, effect="buff", buff="crit",  buff_amt=0.25, buff_dur=6, color={1.0,0.55,0.2}, learn={master=true, cost_g=220, cost_mat={h_essence1=8,o_head1=8}} },
    mend   ={ id="mend",   name="包扎",     cd=14.0, mp_cost=14, prio=9, effect="heal", heal_pct=0.30, color={0.5,0.85,0.5}, learn={master=true, cost_g=100, cost_mat={h_heal1=10}} },
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
-- nodes.<cat>.mtier = 该区该大类的材料档(1-8)；kinds 由 mtier 在下方循环填成"该档三系"具体材料 id。
D.REGIONS = {
    -- ===== 低级 1-15 =====
    { id="meadow",  name="晨曦绿野", tier="low", lo=1, hi=4,  ilo=2, ihi=6,  rar={"poor","common","common","uncommon"}, rar_elite={"uncommon","rare"}, enemies={"boar","wolf"},          nodes={ wood={mtier=1,lvloff=0},  ore={mtier=1,lvloff=-1}, herb={mtier=1,lvloff=0} } },
    { id="brook",   name="低语溪谷", tier="low", lo=3, hi=6,  ilo=4, ihi=9,  rar={"poor","common","common","uncommon"}, rar_elite={"uncommon","rare"}, enemies={"boar","wolf","bandit"},  nodes={ wood={mtier=1,lvloff=0},  ore={mtier=1,lvloff=0},  herb={mtier=1,lvloff=0} } },
    { id="downs",   name="风吹荒原", tier="low", lo=5, hi=8,  ilo=6, ihi=11, rar={"common","common","uncommon","uncommon"}, rar_elite={"uncommon","rare"}, enemies={"wolf","bandit"},     nodes={ wood={mtier=2,lvloff=-1}, ore={mtier=2,lvloff=1},  herb={mtier=2,lvloff=0} } },
    { id="darkwood",name="幽暗森林", tier="low", lo=7, hi=10, ilo=8, ihi=14, rar={"common","uncommon","uncommon","rare"}, rar_elite={"rare","epic"}, enemies={"wolf","bandit","ogre"},   nodes={ wood={mtier=2,lvloff=1},  ore={mtier=2,lvloff=0},  herb={mtier=2,lvloff=0} } },
    { id="quarry",  name="碎石矿场", tier="low", lo=9, hi=12, ilo=10,ihi=16, rar={"common","uncommon","uncommon","rare"}, rar_elite={"rare","epic"}, enemies={"bandit","ogre"},          nodes={ wood={mtier=2,lvloff=0},  ore={mtier=3,lvloff=2},  herb={mtier=2,lvloff=-1} } },
    { id="fen",     name="腐沼湿地", tier="low", lo=11,hi=14, ilo=12,ihi=18, rar={"uncommon","uncommon","rare","rare"}, rar_elite={"rare","epic"}, enemies={"wolf","ogre","wraith"},     nodes={ wood={mtier=3,lvloff=0},  ore={mtier=3,lvloff=0},  herb={mtier=3,lvloff=1} } },
    -- ===== 中级 16-35 =====
    { id="ruins",   name="沉没遗迹", tier="mid", lo=15,hi=19, ilo=16,ihi=23, rar={"uncommon","rare","rare","epic"}, rar_elite={"epic","legendary"}, enemies={"bandit","ogre","wraith"}, nodes={ wood={mtier=3,lvloff=0},  ore={mtier=4,lvloff=1},  herb={mtier=3,lvloff=0} } },
    { id="canyon",  name="赤红峡谷", tier="mid", lo=18,hi=22, ilo=20,ihi=27, rar={"uncommon","rare","rare","epic"}, rar_elite={"epic","legendary"}, enemies={"ogre","wraith","golem"},  nodes={ wood={mtier=4,lvloff=-1}, ore={mtier=4,lvloff=2},  herb={mtier=4,lvloff=1} } },
    { id="hollow",  name="回响洞窟", tier="mid", lo=21,hi=25, ilo=23,ihi=31, rar={"rare","rare","epic","epic"}, rar_elite={"epic","legendary"}, enemies={"wraith","golem","ogre"},      nodes={ wood={mtier=4,lvloff=0},  ore={mtier=4,lvloff=1},  herb={mtier=4,lvloff=0} } },
    { id="peak",    name="霜寒峰",   tier="mid", lo=24,hi=28, ilo=26,ihi=34, rar={"rare","rare","epic","epic"}, rar_elite={"epic","legendary"}, enemies={"ogre","wraith","golem"},      nodes={ wood={mtier=5,lvloff=0},  ore={mtier=5,lvloff=1},  herb={mtier=5,lvloff=1} } },
    { id="wastes",  name="灰烬废土", tier="mid", lo=27,hi=31, ilo=29,ihi=37, rar={"rare","epic","epic","legendary"}, rar_elite={"epic","legendary"}, enemies={"wraith","golem"},        nodes={ wood={mtier=5,lvloff=-1}, ore={mtier=5,lvloff=2},  herb={mtier=5,lvloff=0} } },
    { id="catacomb",name="尘封地穴", tier="mid", lo=30,hi=34, ilo=32,ihi=40, rar={"rare","epic","epic","legendary"}, rar_elite={"epic","legendary"}, enemies={"wraith","golem","ogre"}, nodes={ wood={mtier=5,lvloff=0},  ore={mtier=6,lvloff=1},  herb={mtier=5,lvloff=0} } },
    -- ===== 高级 36-60 =====
    { id="spire",   name="苍穹尖塔", tier="high",lo=35,hi=40, ilo=37,ihi=46, rar={"epic","epic","legendary","legendary"}, rar_elite={"legendary","legendary"}, enemies={"golem","frost"},   nodes={ wood={mtier=6,lvloff=0},  ore={mtier=6,lvloff=1},  herb={mtier=6,lvloff=0} } },
    { id="abyss",   name="深渊裂口", tier="high",lo=39,hi=44, ilo=41,ihi=50, rar={"epic","epic","legendary","legendary"}, rar_elite={"legendary","legendary"}, enemies={"wraith","voidcat"},nodes={ wood={mtier=6,lvloff=-1}, ore={mtier=6,lvloff=2},  herb={mtier=6,lvloff=1} } },
    { id="cinder",  name="炽炎熔狱", tier="high",lo=43,hi=48, ilo=45,ihi=54, rar={"epic","legendary","legendary","legendary"}, rar_elite={"legendary","legendary"}, enemies={"drake","golem"}, nodes={ wood={mtier=7,lvloff=0},  ore={mtier=7,lvloff=1},  herb={mtier=7,lvloff=0} } },
    { id="glacier", name="永冻冰川", tier="high",lo=47,hi=52, ilo=49,ihi=58, rar={"epic","legendary","legendary","legendary"}, rar_elite={"legendary","legendary"}, enemies={"frost","golem"}, nodes={ wood={mtier=7,lvloff=0},  ore={mtier=7,lvloff=1},  herb={mtier=7,lvloff=-1} } },
    { id="rift",    name="虚空断界", tier="high",lo=51,hi=56, ilo=53,ihi=62, rar={"legendary","legendary","legendary","legendary"}, rar_elite={"legendary","legendary"}, enemies={"voidcat","revenant"}, nodes={ wood={mtier=7,lvloff=-1}, ore={mtier=8,lvloff=2}, herb={mtier=7,lvloff=1} } },
    { id="throne",  name="陨灭王座", tier="high",lo=55,hi=60, ilo=57,ihi=66, rar={"legendary","legendary","legendary","legendary"}, rar_elite={"legendary","legendary"}, enemies={"drake","revenant","golem"}, nodes={ wood={mtier=8,lvloff=0}, ore={mtier=8,lvloff=1}, herb={mtier=8,lvloff=0} } },
}
-- 填 nodes.<cat>.kinds = 该档三系材料 id（采集随机抽一系→产出具体材料）
for _,rg in ipairs(D.REGIONS) do
    for cat,nd in pairs(rg.nodes) do
        nd.kinds = {}
        for _,sys in ipairs(D.SYS_BY_CAT[cat]) do
            nd.kinds[#nd.kinds+1] = D.mat_id(cat, nd.mtier, sys)
        end
    end
end
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

-- 采集节点：按 mat 大类给「耐久系数 hp、基础产量 yield」。节点展示名 = 具体材料名(MAT_NAME[kind])。
D.NODE_BASE = { wood={hp=1.0,yield=1.0}, ore={hp=1.4,yield=0.8}, herb={hp=0.8,yield=0.9} }
D.MAT_REQ_FAIL = { wood="树木等级不足", ore="矿石等级不足", herb="草药等级不足" }

D.UI = {
    bg={0.07,0.08,0.12}, panel={0.12,0.13,0.19,0.97}, line={0.26,0.28,0.36},
    text={0.93,0.94,0.97}, dim={0.55,0.57,0.64}, good={0.4,0.85,0.5}, bad={0.88,0.3,0.3},
    gold={1.0,0.84,0.25}, xp={0.45,0.6,1.0}, btn={0.25,0.55,1.0},
}

return D
