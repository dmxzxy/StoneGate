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
--   角色每级 +2力 +2敏 +3耐（慢），经验需求 floor(55*L^2.15)，等级上限 60
-- ============================================================================

local D = {}

-- 等级上限(§0/§1)：到 60 停止升级，溢出 xp 转「战斗精通」点。
D.LEVEL_CAP = 60

-- ---- 设计空间 / 战斗布景 / 数值锚点常量 ----
D.DESIGN_W, D.DESIGN_H = 480, 800
D.ENTER_TIME, D.DEATH_TIME = 0.6, 0.6
D.ENEMY_HOME_X = D.DESIGN_W * 0.72
-- 遭遇式采集：寻找→遇到→判定→采集 的阶段时长 + 资源节点停靠位
D.GATHER_SEARCH, D.GATHER_FOUND, D.GATHER_DONE = 0.7, 0.35, 0.3
D.NODE_HOME_X = D.DESIGN_W * 0.66
D.GEAR_BUDGET = 2.6   -- 装备预算系数(4→2.6 压数值爆炸；稀有度倍率保留差距大，传说仍远强于精良)
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

-- ============================================================================
-- 武器三类型（§2.1）：差异轴 = 攻速带 + 内置暴击，三类型裸 DPS 守恒。
--   spd = 攻速带(次/秒)，roll 时在带内随机；wmid*wspeed=budget*WEAPON_DPS_K 保持守恒。
--   crit = 内置暴击修正(写进 gear.stats.crit_innate，recalc 计入)。
--   程序名材料前缀用此处 prefix(无武器材料系统时的兜底类型名)。
-- ============================================================================
D.WEAPON_TYPES = {
    shortbow = { id="shortbow", name="短弓", spd={0.72,0.92}, crit=-0.02, tag="快攻：每击触发多，利流血/毒/冰减速叠加" },
    longbow  = { id="longbow",  name="长弓", spd={0.50,0.64}, crit= 0.00, tag="均衡通用：元素 DOT 覆盖稳" },
    crossbow = { id="crossbow", name="弩",   spd={0.34,0.46}, crit= 0.06, tag="重击高暴：利大伤技能/穿甲重箭" },
}
D.WEAPON_TYPE_ORDER = { "shortbow", "longbow", "crossbow" }

-- 签名特效字段说明（NAMED_WEAPONS.sig 里的键；战斗接最小可用子集，未接的留登记不报错）：
--   haste=bool/num     攻速提升(true=默认 8%，数值=该比例)        —— recalc 接(乘攻速)
--   crit=num           额外暴击率(0.08=+8%)                       —— recalc 接(加暴击)
--   armor_pierce=num   命中无视该比例护甲(0.25=穿 25%)            —— do_shot 接(减敌减伤)
--   bleed_on_hit=num   命中挂物理流血 DOT(每秒该比例单发伤害)     —— do_shot 接(挂 dot，无视护甲)
--   ele_amp_fire/chill_amp/big_hit/...  其余喂 build 的字段先登记，后续期接(TODO)
D.WEAPON_SIG_DESC = {
    haste        = "出手如风：攻速提升",
    crit         = "致命：暴击率提升",
    armor_pierce = "破甲：命中无视部分护甲",
    bleed_on_hit = "见血：命中叠加物理流血(无视护甲)",
    ele_amp_fire = "焰盛：火属性伤害增幅",
    chill_amp    = "霜噬：冰冻效果增强",
    big_hit      = "重击：偶发额外重伤",
}

-- 命名武器（§2.2）：蓝(精良)+武器从这里抽，唯一名 + 签名特效。
--   每条 = {name, wtype, min_ilvl, sig=固定签名特效, flavor}。
--   roll 蓝+武器时在「类型匹配 且 ilvl 够 且 未拥有」池里抽一个，叠加随机词缀。
--   覆盖低/中/高三段每类型若干（low ~10-18 / mid ~26-40 / high ~46-58）。
D.NAMED_WEAPONS = {
    -- ---- 低段(low, min_ilvl ~10-18) ----
    { name="裂风",     wtype="shortbow", min_ilvl=10, sig={haste=0.08, bleed_on_hit=0.08}, flavor="出手如风，箭箭见血" },
    { name="林语长弓", wtype="longbow",  min_ilvl=12, sig={ele_amp_fire=0.2},               flavor="附火之箭灼焰更盛" },
    { name="贯石弩",   wtype="crossbow", min_ilvl=14, sig={armor_pierce=0.25, crit=0.08},   flavor="一矢洞穿顽石" },
    { name="疾隼",     wtype="shortbow", min_ilvl=16, sig={haste=0.10, crit=0.04},          flavor="如隼扑食，迅疾连珠" },
    { name="苍翠",     wtype="longbow",  min_ilvl=15, sig={crit=0.06, bleed_on_hit=0.06},   flavor="林间猎手的信物" },
    { name="碎甲钉",   wtype="crossbow", min_ilvl=18, sig={armor_pierce=0.3, big_hit=0.15}, flavor="专破重甲" },
    -- ---- 中段(mid, min_ilvl ~26-40) ----
    { name="霜噬",     wtype="shortbow", min_ilvl=30, sig={chill_amp=0.3, haste=0.1},       flavor="箭锋裹霜，所触皆寒" },
    { name="风暴之眼", wtype="shortbow", min_ilvl=34, sig={haste=0.14, bleed_on_hit=0.12},  flavor="叠流血的风暴核心" },
    { name="赤焰长弓", wtype="longbow",  min_ilvl=28, sig={ele_amp_fire=0.3, crit=0.06},     flavor="燃尽不死的烈焰" },
    { name="月辉",     wtype="longbow",  min_ilvl=36, sig={crit=0.1, armor_pierce=0.15},     flavor="清辉所照，无可遁形" },
    { name="碎山弩",   wtype="crossbow", min_ilvl=32, sig={armor_pierce=0.35, crit=0.12},    flavor="一击碎山的重弩" },
    { name="雷霆裁断", wtype="crossbow", min_ilvl=38, sig={crit=0.15, big_hit=0.2},          flavor="雷霆之下无活口" },
    -- ---- 高段(high, min_ilvl ~46-58) ----
    { name="嗜血风刃", wtype="shortbow", min_ilvl=46, sig={haste=0.16, bleed_on_hit=0.16},   flavor="越战越快，血流不止" },
    { name="永霜",     wtype="shortbow", min_ilvl=52, sig={chill_amp=0.4, haste=0.14, crit=0.06}, flavor="万物归于永冻" },
    { name="天罚长弓", wtype="longbow",  min_ilvl=48, sig={ele_amp_fire=0.4, crit=0.1},       flavor="天罚之焰，灼尽群敌" },
    { name="星陨",     wtype="longbow",  min_ilvl=55, sig={crit=0.14, armor_pierce=0.25, big_hit=0.2}, flavor="坠星之力凝于一箭" },
    { name="噬星弩",   wtype="crossbow", min_ilvl=50, sig={armor_pierce=0.4, crit=0.15},      flavor="连星辰也能贯穿" },
    { name="王座裁决", wtype="crossbow", min_ilvl=57, sig={armor_pierce=0.4, crit=0.18, big_hit=0.25}, flavor="毕业级·陨灭王座的判决" },
}

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

-- ============================================================================
-- 锭(§5 锻造)：矿→锭，stackable，造箭头/武器/护甲的中间材料。
--   每锭绑一档兵刃矿(o_blade<otier>)为主料 + 薪炭木燃料；高档需更高 forge 等级。
--   id=<金属>_ingot；color 由档调亮(承接矿石灰蓝基色)。tier 仅作展示/排序。
-- ============================================================================
D.INGOTS = {
    { id="copper_ingot",  name="铜锭",   otier=2, tier=2, color={0.78,0.5,0.32} },
    { id="iron_ingot",    name="铁锭",   otier=4, tier=4, color={0.72,0.74,0.8} },
    { id="silver_ingot",  name="银锭",   otier=6, tier=6, color={0.85,0.88,0.95} },
    { id="mithril_ingot", name="秘银锭", otier=6, tier=7, color={0.6,0.85,0.9} },
    { id="adamant_ingot", name="精金锭", otier=7, tier=8, color={0.5,0.8,0.6} },
    { id="starsteel_ingot",name="星钢锭",otier=7, tier=9, color={0.7,0.7,0.95} },
    { id="voidiron_ingot",name="虚空铁锭",otier=8,tier=10,color={0.55,0.4,0.7} },
}
D.INGOT = {}; for _,ig in ipairs(D.INGOTS) do
    D.INGOT[ig.id]=ig
    D.MAT_NAME[ig.id]=ig.name; D.MAT_COLOR[ig.id]=ig.color
    D.MAT_DESC[ig.id]="T"..ig.tier.." 锭。由矿石炼成，造箭头/武器/护甲。"
end

-- 按 cat+tier+system 取材料 id（配方/采集用）。无则 nil。
function D.mat_id(cat, tier, system)
    local d = D.MAT[cat:sub(1,1).."_"..system..tier]
    return d and d.id
end

-- ============================================================================
-- 箭矢三轴（§2.3）：一支成品箭 = 箭头档(head) × 元素(element) × 翎羽(feather)。
--   head    决定物理伤害倍率(phys_mult)，吃箭簇矿锭。10 档。
--   element 决定 on-hit 玩法(点燃/减速/中毒/流血/穿甲/雷/爆/破甲/净化/纯物理)。10 种。
--   feather 决定手感微调(暴击/攻速/穿透)。4 种。
--   成品箭存在弹药槽：{head=, element=, feather=, qty=}；派生名/色由 D.arrow_* 计算。
-- ============================================================================
-- 箭头档：tier 1-10 → phys_mult。col 仅做箭杆/箭簇基调。mat=造此档箭头所需箭簇矿档(o_head<tier..>)。
D.ARROW_HEADS = {
    { id="flint",   name="燧石",   tier=1,  phys_mult=0.9,  mtier=1, color={0.55,0.5,0.45} },
    { id="copper",  name="铜簇",   tier=2,  phys_mult=1.1,  mtier=2, color={0.78,0.5,0.32} },
    { id="bronze",  name="青铜簇", tier=3,  phys_mult=1.3,  mtier=3, color={0.72,0.6,0.35} },
    { id="iron",    name="铁簇",   tier=4,  phys_mult=1.55, mtier=4, color={0.72,0.74,0.8} },
    { id="steel",   name="钢簇",   tier=5,  phys_mult=1.85, mtier=5, color={0.78,0.82,0.9} },
    { id="silver",  name="银簇",   tier=6,  phys_mult=2.15, mtier=6, color={0.85,0.88,0.95} },
    { id="mithril", name="秘银簇", tier=7,  phys_mult=2.5,  mtier=6, color={0.6,0.85,0.9} },
    { id="adamant", name="精金簇", tier=8,  phys_mult=2.85, mtier=7, color={0.5,0.8,0.6} },
    { id="starsteel",name="星钢簇",tier=9,  phys_mult=3.2,  mtier=7, color={0.7,0.7,0.95} },
    { id="void",    name="虚空簇", tier=10, phys_mult=3.6,  mtier=8, color={0.55,0.4,0.7} },
}
D.AHEAD = {}; for _,h in ipairs(D.ARROW_HEADS) do D.AHEAD[h.id]=h end

-- 元素/特效：proc 数据喂战斗 do_shot。kind 决定命中行为：
--   dot     → 命中挂持续伤害(火点燃/毒叠层/流血)；mult=每秒该比例本发伤害，dur/tick，stack/no_armor 可选
--   debuff  → 命中挂减益(冰减速 slow / 破甲 sunder)；amt/dur
--   pierce  → 命中无视该比例护甲(穿甲)
--   bonus   → 对特定 family 增伤(净化对不死/虚空)
--   splash/chain → 群战预留(单体先记数值，不实际分裂)
--   none    → 纯物理
D.ARROW_ELEMENTS = {
    { id="phys",   name="物理", kind="none",   color={0.8,0.8,0.85}, desc="纯物理，吃满暴击。" },
    { id="fire",   name="火焰", kind="dot",    color={1.0,0.5,0.2},  dot_mult=0.30, dur=4, tick=1, stack=true,            desc="点燃 DOT，可叠新覆旧。对不死 +20%。", vs={undead=1.2} },
    { id="frost",  name="冰霜", kind="debuff", color={0.5,0.8,1.0},  debuff="slow",  amt=0.20, dur=3,                     desc="减速：敌出手速 -20%。" },
    { id="poison", name="剧毒", kind="dot",    color={0.5,0.85,0.45},dot_mult=0.06, dur=6, tick=1, stack=true, maxstack=10,desc="中毒叠层，每层 0.06×/s，上限10。" },
    { id="bleed",  name="流血", kind="dot",    color={0.85,0.2,0.2}, dot_mult=0.10, dur=5, tick=1, stack=true, maxstack=8, no_armor=true, desc="物理流血叠层，无视护甲。" },
    { id="pierce", name="穿甲", kind="pierce", color={0.7,0.7,0.78}, pierce=0.30, heavy=0.12,                            desc="无视 30% 护甲，单发更重略降速。" },
    { id="thunder",name="雷击", kind="chain",  color={0.7,0.8,1.0},  chain_p=0.35, chain_mult=0.5,                       desc="命中有概率连跳(群战预留)。" },
    { id="blast",  name="爆裂", kind="splash", color={1.0,0.7,0.3},  splash_mult=0.4,                                    desc="命中小范围溅射(群战预留)。" },
    { id="sunder", name="破甲", kind="debuff", color={0.85,0.6,0.35},debuff="sunder", amt=0.08, dur=5, maxstack=6,        desc="命中降敌护甲 8%/层(可叠)。" },
    { id="purify", name="净化", kind="bonus",  color={0.95,0.95,0.7},vs={undead=1.35, void=1.35},                        desc="对不死/虚空 +35% 伤，对其它无加成。" },
}
D.AELEM = {}; for _,e in ipairs(D.ARROW_ELEMENTS) do D.AELEM[e.id]=e end

-- 翎羽：手感微调(小幅 build 杠杆)。crit/haste/pierce 加成；single=单发伤害微调。
D.ARROW_FEATHERS = {
    { id="plain", name="普通羽", color={0.85,0.85,0.9},                       desc="无修正。" },
    { id="eagle", name="鹰羽",   color={0.7,0.55,0.3},  crit=0.05,            desc="+5% 暴击率，配弩/物理。" },
    { id="wind",  name="风羽",   color={0.7,0.9,0.95},  haste=0.06,           desc="+6% 攻速，配短弓叠层。" },
    { id="heavy", name="重羽",   color={0.5,0.45,0.4},  single=0.05, haste=-0.03, pierce=0.05, desc="单发 +5% 但 -3% 速，配长弓/穿甲。" },
}
D.AFEAT = {}; for _,f in ipairs(D.ARROW_FEATHERS) do D.AFEAT[f.id]=f end

-- 翎羽 id → 制箭所需二级材料(羽毛变体)；普通羽用基础羽毛。
D.FEATHER_MAT = { plain="feather", eagle="eaglefeat", wind="windfeat", heavy="heavyfeat" }

-- 成品箭派生：稳定 key(用于弹药堆叠/相等判定) / 显示名 / 颜色 / 物理倍率。
-- key 形如 "steel|bleed|wind"；缺轴兜底 flint/phys/plain（旧档/坏数据安全）。
function D.arrow_key(a)
    return (a.head or "flint").."|"..(a.element or "phys").."|"..(a.feather or "plain")
end
function D.arrow_head(a)  return D.AHEAD[a.head] or D.ARROW_HEADS[1] end
function D.arrow_elem(a)  return D.AELEM[a.element] or D.AELEM.phys end
function D.arrow_feat(a)  return D.AFEAT[a.feather] or D.AFEAT.plain end
function D.arrow_mult(a)  return D.arrow_head(a).phys_mult end
function D.arrow_name(a)
    local h,e,f = D.arrow_head(a), D.arrow_elem(a), D.arrow_feat(a)
    -- 名 = 元素 + 箭头(物理则只箭头)；翎羽非普通则后缀
    local base = (e.id=="phys") and (h.name.."箭") or (e.name..h.name.."箭")
    if f.id~="plain" then base = base.."·"..f.name end
    return base
end
function D.arrow_color(a)
    -- 元素色为主，物理则取箭头色
    local e = D.arrow_elem(a)
    if e.id=="phys" then return D.arrow_head(a).color end
    return e.color
end

-- 签名箭(§2.3)：稀有配方解锁，自带组合特效 + 更高数值，作毕业目标。
-- 数据上仍是成品箭(head+element+feather) + 可选 sig 增益；这里登记供配方/未来扩展。
D.SIGNATURE_ARROWS = {
    { id="dragonbreath", name="龙息箭", head="starsteel", element="fire",   feather="heavy", flavor="火+爆裂的毁灭之矢" },
    { id="godslayer",    name="弑神箭", head="void",      element="pierce", feather="eagle", flavor="穿甲+净化+星钢的弑神之矢" },
}

-- 消耗品（药剂等，走背包可堆叠）
D.POT_NAME = { hppot="疗伤药剂" }
D.POT_COLOR = { hppot={0.9,0.35,0.4} }
D.POT_DESC = { hppot="战斗中生命过低时自动饮用，回复部分生命。" }

-- 统一制造图谱：制箭只是「造箭类图谱」，与中间材料/药剂共用同一套 can_craft/do_craft。
-- out.kind: arrow(进箭袋,成品箭三轴 head/element/feather) | mat(进背包) | potion(进背包) | gear(进背包,roll 稀有度)
-- 制箭 out = {kind="arrow", head=, element=, feather=, qty=}；战斗按三轴查 D.AHEAD/AELEM/AFEAT。
-- req=所需职业等级；time=制作归一化耗时；learn=start(初始)|level(到级自动)|master(技能大师)
-- job=该图谱吃哪个子职业的等级/经验：craft(制造,默认) | forge(锻造)。
-- cat=制造页分类 tab：fletch(制箭) | mat(材料药剂) | ingot(炼锭) | armor(造甲) | bow(造弓)。
D.ARROW_BATCH = 20
D.CRAFT_BASE  = 0.20   -- 制作进度基准：速率 = CRAFT_BASE * job.lvl / bp.time
-- 制箭图谱按系取材：箭杆木(w_shaft)+箭簇矿(o_head) + 元素附材(精萃/油/毒囊/利刃石...) + 翎羽变体。
-- 三轴自由组合数远大于单表 → 这里只铺“代表性常用箭”，玩家按 head/element/feather 区分。
D.BLUEPRINTS = {
    -- ---- 物理箭(头档进阶，纯物理兜底) ----
    { id="ar_flint",  name="燧石箭", cat="fletch", req=1, time=4, learn="start",  out={kind="arrow", head="flint",  element="phys", feather="plain", qty=D.ARROW_BATCH}, cost={ w_shaft1=3, feather=1 } },
    { id="ar_iron",   name="铁簇箭", cat="fletch", req=2, time=5, learn="level",  out={kind="arrow", head="iron",   element="phys", feather="plain", qty=D.ARROW_BATCH}, cost={ w_shaft2=2, o_head4=3, feather=1 } },
    { id="ar_steel",  name="钢簇箭", cat="fletch", req=5, time=6, learn="level",  out={kind="arrow", head="steel",  element="phys", feather="eagle", qty=D.ARROW_BATCH}, cost={ w_shaft3=2, o_head5=3, eaglefeat=1 } },
    { id="ar_mithril",name="秘银箭", cat="fletch", req=8, time=7, learn="level",  out={kind="arrow", head="mithril",element="phys", feather="eagle", qty=D.ARROW_BATCH}, cost={ w_shaft4=2, o_head6=3, eaglefeat=2 } },
    -- ---- 元素箭(代表性 build 箭) ----
    { id="ar_fire",   name="火焰箭", cat="fletch", req=3, time=6, learn="level",  out={kind="arrow", head="bronze", element="fire",   feather="plain", qty=D.ARROW_BATCH}, cost={ w_shaft2=2, o_head3=2, oil=2, feather=1 } },
    { id="ar_frost",  name="冰霜箭", cat="fletch", req=4, time=6, learn="level",  out={kind="arrow", head="iron",   element="frost",  feather="wind",  qty=D.ARROW_BATCH}, cost={ w_shaft2=2, o_head4=2, h_essence2=3, windfeat=1 } },
    { id="ar_poison", name="剧毒箭", cat="fletch", req=4, time=6, learn="level",  out={kind="arrow", head="iron",   element="poison", feather="wind",  qty=D.ARROW_BATCH}, cost={ w_shaft2=2, o_head4=2, venomsac=2, windfeat=1 } },
    { id="ar_bleed",  name="流血箭", cat="fletch", req=5, time=6, learn="level",  out={kind="arrow", head="steel",  element="bleed",  feather="wind",  qty=D.ARROW_BATCH}, cost={ w_shaft3=2, o_head5=2, bladestone=2, windfeat=1 } },
    { id="ar_pierce", name="穿甲箭", cat="fletch", req=6, time=7, learn="master", out={kind="arrow", head="silver", element="pierce", feather="heavy", qty=D.ARROW_BATCH}, cost={ w_shaft4=3, o_head6=3, heavyfeat=2 } },
    { id="ar_blast",  name="爆裂箭", cat="fletch", req=6, time=7, learn="master", out={kind="arrow", head="silver", element="blast",  feather="plain", qty=D.ARROW_BATCH}, cost={ w_shaft4=2, o_head6=2, oil=2, sulfur=2 } },
    { id="ar_sunder", name="破甲箭", cat="fletch", req=7, time=7, learn="master", out={kind="arrow", head="mithril",element="sunder", feather="heavy", qty=D.ARROW_BATCH}, cost={ w_shaft5=2, o_head6=3, h_essence4=2, heavyfeat=2 } },
    { id="ar_purify", name="净化箭", cat="fletch", req=8, time=8, learn="master", out={kind="arrow", head="adamant",element="purify", feather="plain", qty=D.ARROW_BATCH}, cost={ w_shaft6=2, o_head7=3, h_essence5=3, feather=2 } },
    -- ---- 中间材料 / 药剂 ----
    { id="ironbar",name="精铁锭",  cat="mat", req=3, time=6, learn="level",  out={kind="mat",    id="ironbar",qty=1, color={0.8,0.82,0.88}},  cost={ o_blade2=4, w_char1=2 } },
    { id="hppot",  name="疗伤药剂",cat="mat", req=2, time=5, learn="level",  out={kind="potion", id="hppot",  qty=1, color={0.9,0.35,0.4}},   cost={ h_heal1=4 } },
    { id="leather",name="鞣制皮革",cat="mat", req=5, time=7, learn="master", out={kind="mat",    id="leather",qty=2, color={0.7,0.5,0.32}},   cost={ hide=2, h_heal2=1 } },
    -- ============================================================================
    -- 锻造图谱(§5)：job="forge"，吃 forge 子职业等级/经验。
    --   炼锭(cat=ingot)：兵刃矿(o_blade)+薪炭木(w_char 燃料) → 锭(stackable,进背包)。
    --   造装(cat=armor/bow)：out.kind="gear" → do_craft 调 roll_gear(slot,ilvl_base,按 rarity_roll 抽稀有度)，
    --     产出装备进背包(定向出装第二条线)。wtype 指定弓类型；ilvl_base 由材料档定。
    -- ============================================================================
    -- ---- 炼锭(矿→锭) ----
    { id="fg_copper",   name="铜锭",   cat="ingot", job="forge", req=1, time=5, learn="start", out={kind="mat", id="copper_ingot",  qty=1, color={0.78,0.5,0.32}}, cost={ o_blade2=3, w_char1=1 } },
    { id="fg_iron",     name="铁锭",   cat="ingot", job="forge", req=3, time=6, learn="level", out={kind="mat", id="iron_ingot",    qty=1, color={0.72,0.74,0.8}},  cost={ o_blade3=3, w_char2=1 } },
    { id="fg_silver",   name="银锭",   cat="ingot", job="forge", req=6, time=7, learn="level", out={kind="mat", id="silver_ingot",  qty=1, color={0.85,0.88,0.95}}, cost={ o_blade4=3, w_char4=2 } },
    { id="fg_mithril",  name="秘银锭", cat="ingot", job="forge", req=9, time=8, learn="level", out={kind="mat", id="mithril_ingot", qty=1, color={0.6,0.85,0.9}},   cost={ o_blade5=3, w_char5=2 } },
    { id="fg_adamant",  name="精金锭", cat="ingot", job="forge", req=12,time=9, learn="level", out={kind="mat", id="adamant_ingot", qty=1, color={0.5,0.8,0.6}},    cost={ o_blade6=3, w_char6=2 } },
    { id="fg_starsteel",name="星钢锭", cat="ingot", job="forge", req=15,time=10,learn="level", out={kind="mat", id="starsteel_ingot",qty=1, color={0.7,0.7,0.95}}, cost={ o_blade7=3, w_char7=2 } },
    { id="fg_voidiron", name="虚空铁锭",cat="ingot",job="forge", req=18,time=11,learn="level", out={kind="mat", id="voidiron_ingot",qty=1, color={0.55,0.4,0.7}},  cost={ o_blade8=3, w_char8=3 } },
    -- ---- 造甲(甲胄矿/锭 + 皮革 → gear，roll 稀有度) ----
    { id="fg_copper_chest", name="铜甲胸甲", cat="armor", job="forge", req=2,  time=8,  learn="start", out={kind="gear", slot="chest", ilvl_base=6,  rarity_roll={common=0.55,uncommon=0.35,rare=0.10}}, cost={ copper_ingot=4, leather=2 } },
    { id="fg_iron_chest",   name="精铁胸甲", cat="armor", job="forge", req=4,  time=9,  learn="level", out={kind="gear", slot="chest", ilvl_base=12, rarity_roll={common=0.45,uncommon=0.40,rare=0.15}}, cost={ iron_ingot=4, leather=2 } },
    { id="fg_iron_legs",    name="精铁腿甲", cat="armor", job="forge", req=4,  time=9,  learn="level", out={kind="gear", slot="legs",  ilvl_base=12, rarity_roll={common=0.45,uncommon=0.40,rare=0.15}}, cost={ iron_ingot=4, leather=2 } },
    { id="fg_silver_chest", name="银纹胸甲", cat="armor", job="forge", req=8,  time=11, learn="level", out={kind="gear", slot="chest", ilvl_base=26, rarity_roll={uncommon=0.45,rare=0.45,epic=0.10}}, cost={ silver_ingot=5, leather=3 } },
    { id="fg_silver_head",  name="银纹头盔", cat="armor", job="forge", req=8,  time=10, learn="level", out={kind="gear", slot="head",  ilvl_base=26, rarity_roll={uncommon=0.45,rare=0.45,epic=0.10}}, cost={ silver_ingot=4, leather=2 } },
    { id="fg_adamant_chest",name="精金胸甲", cat="armor", job="forge", req=13, time=13, learn="level", out={kind="gear", slot="chest", ilvl_base=44, rarity_roll={rare=0.50,epic=0.40,legendary=0.10}}, cost={ adamant_ingot=5, leather=4 } },
    { id="fg_void_chest",   name="虚空铸甲", cat="armor", job="forge", req=18, time=15, learn="level", out={kind="gear", slot="chest", ilvl_base=58, rarity_roll={epic=0.55,legendary=0.45}},               cost={ voidiron_ingot=6, leather=5 } },
    -- ---- 造弓(兵刃锭 + 弓臂木 → weapon gear，含 wtype) ----
    { id="fg_copper_short", name="铜锻短弓", cat="bow", job="forge", req=3,  time=9,  learn="start", out={kind="gear", slot="bow", wtype="shortbow", ilvl_base=6,  rarity_roll={common=0.55,uncommon=0.35,rare=0.10}}, cost={ copper_ingot=4, w_bowarm1=3 } },
    { id="fg_iron_long",    name="精铁长弓", cat="bow", job="forge", req=5,  time=10, learn="level", out={kind="gear", slot="bow", wtype="longbow",  ilvl_base=14, rarity_roll={uncommon=0.50,rare=0.40,epic=0.10}}, cost={ iron_ingot=5, w_bowarm2=3 } },
    { id="fg_iron_cross",   name="精铁弩",   cat="bow", job="forge", req=6,  time=10, learn="level", out={kind="gear", slot="bow", wtype="crossbow", ilvl_base=14, rarity_roll={uncommon=0.50,rare=0.40,epic=0.10}}, cost={ iron_ingot=5, w_bowarm3=3 } },
    { id="fg_silver_short", name="银弦短弓", cat="bow", job="forge", req=9,  time=12, learn="level", out={kind="gear", slot="bow", wtype="shortbow", ilvl_base=28, rarity_roll={rare=0.55,epic=0.35,legendary=0.10}}, cost={ silver_ingot=5, w_bowarm4=3 } },
    { id="fg_adamant_long", name="精金长弓", cat="bow", job="forge", req=14, time=14, learn="level", out={kind="gear", slot="bow", wtype="longbow",  ilvl_base=46, rarity_roll={rare=0.45,epic=0.45,legendary=0.10}}, cost={ adamant_ingot=5, w_bowarm6=3 } },
    { id="fg_void_cross",   name="虚空重弩", cat="bow", job="forge", req=19, time=16, learn="level", out={kind="gear", slot="bow", wtype="crossbow", ilvl_base=58, rarity_roll={epic=0.55,legendary=0.45}},               cost={ voidiron_ingot=6, w_bowarm8=4 } },
}
-- 锻造图谱 cat → tab 顺序/名(craft 页 forge 区用)
D.FORGE_TABS = {
    { id="ingot", name="炼锭" },
    { id="armor", name="造甲" },
    { id="bow",   name="造弓" },
}
D.BP = {}; for _,b in ipairs(D.BLUEPRINTS) do D.BP[b.id]=b end
-- 箭头档有序表(低→高)：战斗/recalc 取弹药里最高 phys_mult 用；展示色按 head。
D.ARROWS, D.ARROW = {}, {}
for _,h in ipairs(D.ARROW_HEADS) do
    local a={ id=h.id, name=h.name, mult=h.phys_mult, color=h.color }
    D.ARROWS[#D.ARROWS+1]=a; D.ARROW[a.id]=a
end

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

-- ============================================================================
-- 战斗精通(§0/§1 满级软成长)：满级(60)后溢出 xp 每 xp_need(60) 转 1 精通点。
--   点投入各路线小幅永久加成(每点 +0.5%)，成本递增软上限(花费越多每点越贵)。
--   recalc 读 player.mastery[id]→换算 pct 加成；不破坏平衡(每路线封顶在 §C6 校准记录)。
--   amt=每点比例；apply= recalc 里挂哪个派生量；cap_pts=软上限提示(不强制锁,成本递增自然劝退)。
-- ============================================================================
D.MASTERY_PER_POINT = 0.005   -- 每点 +0.5%
D.MASTERIES = {
    { id="attack",  name="攻击精通", desc="提升攻击力区间(乘算)",       color={0.9,0.45,0.4} },
    { id="crit",    name="暴击精通", desc="提升暴击率(加算)",           color={1.0,0.7,0.25} },
    { id="haste",   name="急速精通", desc="提升攻速(乘算)",             color={0.5,0.9,0.9} },
    { id="gather",  name="采集精通", desc="提升采集产量/速度(乘算)",     color={0.6,0.8,0.5} },
}
D.MASTERY = {}; for _,m in ipairs(D.MASTERIES) do D.MASTERY[m.id]=m end
-- 投入第 (owned+1) 级所需的精通点：owned 越多越贵(软上限)。
--   cost(owned)=1 + floor(owned/8)：前 8 级 1 点/级、9-16 级 2 点/级…温和递增不锁死。
function D.mastery_cost(owned) return 1 + math.floor((owned or 0)/8) end

-- 挂机活动：一次只挂一种。group 体现优先级层级：idle(挂机) > combat(战斗) > sub(副职业)。
D.ACTIVITIES = {
    rest    = { name="挂机", kind="rest",   group="idle",   ord=1 },
    combat  = { name="战斗", kind="combat", group="combat", ord=1 },
    woodcut = { name="砍柴", kind="gather", group="sub", ord=1, mat="wood", base=0.8 },
    mining  = { name="采矿", kind="gather", group="sub", ord=2, mat="ore",  base=0.6 },
    herb    = { name="采药", kind="gather", group="sub", ord=3, mat="herb", base=0.7 },
    fletch  = { name="制造", kind="craft",  group="sub", ord=4 },
    forge   = { name="锻造", kind="craft",  group="sub", ord=5, job="forge" },
}
D.ACT_ORDER = { "rest", "combat", "woodcut", "mining", "herb", "fletch", "forge" }
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
    { id="meadow",  name="晨曦绿野", tier="low", lo=1, hi=4,  ilo=2, ihi=6,  rar={"poor","common","common","uncommon"}, rar_elite={"uncommon","rare"}, enemies={"boar","wolf","bug"},          nodes={ wood={mtier=1,lvloff=0},  ore={mtier=1,lvloff=-1}, herb={mtier=1,lvloff=0} } },
    { id="brook",   name="低语溪谷", tier="low", lo=3, hi=6,  ilo=4, ihi=9,  rar={"poor","common","common","uncommon"}, rar_elite={"uncommon","rare"}, enemies={"boar","wolf","bandit","bug"},  nodes={ wood={mtier=1,lvloff=0},  ore={mtier=1,lvloff=0},  herb={mtier=1,lvloff=0} } },
    { id="downs",   name="风吹荒原", tier="low", lo=5, hi=8,  ilo=6, ihi=11, rar={"common","common","uncommon","uncommon"}, rar_elite={"uncommon","rare"}, enemies={"wolf","bandit","bat"},     nodes={ wood={mtier=2,lvloff=-1}, ore={mtier=2,lvloff=1},  herb={mtier=2,lvloff=0} } },
    { id="darkwood",name="幽暗森林", tier="low", lo=7, hi=10, ilo=8, ihi=14, rar={"common","uncommon","uncommon","rare"}, rar_elite={"rare","epic"}, enemies={"wolf","bandit","ogre","bat"},   nodes={ wood={mtier=2,lvloff=1},  ore={mtier=2,lvloff=0},  herb={mtier=2,lvloff=0} } },
    { id="quarry",  name="碎石矿场", tier="low", lo=9, hi=12, ilo=10,ihi=16, rar={"common","uncommon","uncommon","rare"}, rar_elite={"rare","epic"}, enemies={"bandit","ogre","gargoyle"},          nodes={ wood={mtier=2,lvloff=0},  ore={mtier=3,lvloff=2},  herb={mtier=2,lvloff=-1} } },
    { id="fen",     name="腐沼湿地", tier="low", lo=11,hi=14, ilo=12,ihi=18, rar={"uncommon","uncommon","rare","rare"}, rar_elite={"rare","epic"}, enemies={"wolf","ogre","wraith","bug"},     nodes={ wood={mtier=3,lvloff=0},  ore={mtier=3,lvloff=0},  herb={mtier=3,lvloff=1} } },
    -- ===== 中级 16-35 =====
    { id="ruins",   name="沉没遗迹", tier="mid", lo=15,hi=19, ilo=16,ihi=23, rar={"uncommon","rare","rare","epic"}, rar_elite={"epic","legendary"}, enemies={"bandit","ogre","wraith","lich"}, nodes={ wood={mtier=3,lvloff=0},  ore={mtier=4,lvloff=1},  herb={mtier=3,lvloff=0} } },
    { id="canyon",  name="赤红峡谷", tier="mid", lo=18,hi=22, ilo=20,ihi=27, rar={"uncommon","rare","rare","epic"}, rar_elite={"epic","legendary"}, enemies={"ogre","wraith","golem","lava"},  nodes={ wood={mtier=4,lvloff=-1}, ore={mtier=4,lvloff=2},  herb={mtier=4,lvloff=1} } },
    { id="hollow",  name="回响洞窟", tier="mid", lo=21,hi=25, ilo=23,ihi=31, rar={"rare","rare","epic","epic"}, rar_elite={"epic","legendary"}, enemies={"wraith","golem","gargoyle"},      nodes={ wood={mtier=4,lvloff=0},  ore={mtier=4,lvloff=1},  herb={mtier=4,lvloff=0} } },
    { id="peak",    name="霜寒峰",   tier="mid", lo=24,hi=28, ilo=26,ihi=34, rar={"rare","rare","epic","epic"}, rar_elite={"epic","legendary"}, enemies={"ogre","golem","icewolf"},      nodes={ wood={mtier=5,lvloff=0},  ore={mtier=5,lvloff=1},  herb={mtier=5,lvloff=1} } },
    { id="wastes",  name="灰烬废土", tier="mid", lo=27,hi=31, ilo=29,ihi=37, rar={"rare","epic","epic","legendary"}, rar_elite={"epic","legendary"}, enemies={"wraith","golem","lava"},        nodes={ wood={mtier=5,lvloff=-1}, ore={mtier=5,lvloff=2},  herb={mtier=5,lvloff=0} } },
    { id="catacomb",name="尘封地穴", tier="mid", lo=30,hi=34, ilo=32,ihi=40, rar={"rare","epic","epic","legendary"}, rar_elite={"epic","legendary"}, enemies={"wraith","golem","lich","revenant"}, nodes={ wood={mtier=5,lvloff=0},  ore={mtier=6,lvloff=1},  herb={mtier=5,lvloff=0} } },
    -- ===== 高级 36-60 =====
    { id="spire",   name="苍穹尖塔", tier="high",lo=35,hi=40, ilo=37,ihi=46, rar={"epic","epic","legendary","legendary"}, rar_elite={"legendary","legendary"}, enemies={"golem","frost","gargoyle"},   nodes={ wood={mtier=6,lvloff=0},  ore={mtier=6,lvloff=1},  herb={mtier=6,lvloff=0} } },
    { id="abyss",   name="深渊裂口", tier="high",lo=39,hi=44, ilo=41,ihi=50, rar={"epic","epic","legendary","legendary"}, rar_elite={"legendary","legendary"}, enemies={"wraith","voidcat","lich"},nodes={ wood={mtier=6,lvloff=-1}, ore={mtier=6,lvloff=2},  herb={mtier=6,lvloff=1} } },
    { id="cinder",  name="炽炎熔狱", tier="high",lo=43,hi=48, ilo=45,ihi=54, rar={"epic","legendary","legendary","legendary"}, rar_elite={"legendary","legendary"}, enemies={"drake","golem","lava"}, nodes={ wood={mtier=7,lvloff=0},  ore={mtier=7,lvloff=1},  herb={mtier=7,lvloff=0} } },
    { id="glacier", name="永冻冰川", tier="high",lo=47,hi=52, ilo=49,ihi=58, rar={"epic","legendary","legendary","legendary"}, rar_elite={"legendary","legendary"}, enemies={"frost","golem","icewolf"}, nodes={ wood={mtier=7,lvloff=0},  ore={mtier=7,lvloff=1},  herb={mtier=7,lvloff=-1} } },
    { id="rift",    name="虚空断界", tier="high",lo=51,hi=56, ilo=53,ihi=62, rar={"legendary","legendary","legendary","legendary"}, rar_elite={"legendary","legendary"}, enemies={"voidcat","revenant","lich"}, nodes={ wood={mtier=7,lvloff=-1}, ore={mtier=8,lvloff=2}, herb={mtier=7,lvloff=1} } },
    { id="throne",  name="陨灭王座", tier="high",lo=55,hi=60, ilo=57,ihi=66, rar={"legendary","legendary","legendary","legendary"}, rar_elite={"legendary","legendary"}, enemies={"drake","revenant","golem","voidcat"}, nodes={ wood={mtier=8,lvloff=0}, ore={mtier=8,lvloff=1}, herb={mtier=8,lvloff=0} } },
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
-- ============================================================================
-- 怪物家族(§4.1)：family + 元素抗性，让箭元素有意义。
--   resist[element] = 元素伤害系数(>1 弱点 / <1 抵抗 / 缺省=1 普通)。流血/穿甲走物理不查这表。
--   armor_mul：family 级护甲倍率(construct 高甲 ×1.3，逼穿甲/弩)。
--   drops：family 偏向掉落(本期登记，combat.drop_loot 取部分接上)。
-- ============================================================================
-- 怪物像素精灵映射：arch_id/family → view/sprites 里的精灵名。
-- 精灵全集：slime/bat/boar/wolf/ghost/golem/ogre/dragon/skeleton/beetle
--   + P1 补全：bandit/gargoyle/icewolf/lava/frost/voidcat/drake。
-- 每个敌型尽量有专属精灵；对不上的按 family 兜底（ENEMY_SPRITE_FAMILY）。
D.ENEMY_SPRITE = {
    -- 普通敌型：各自专属
    boar="boar", wolf="wolf", icewolf="icewolf", bandit="bandit", ogre="ogre",
    wraith="ghost", lich="skeleton", revenant="skeleton",
    golem="golem", gargoyle="gargoyle",
    bug="beetle", bat="bat",
    lava="lava", frost="frost", voidcat="voidcat", drake="drake",
    -- 副本 boss：取同家族最贴近的精灵（combat 用 rank/scale 放大区分体型）
    alpha_wolf="wolf", bog_horror="ghost", stone_lord="golem",
    frost_queen="frost", lava_tyrant="lava", void_warden="voidcat", throne_king="dragon",
}
-- 家族兜底（arch_id 未列时按 family 选最贴近的专属精灵）
D.ENEMY_SPRITE_FAMILY = {
    beast="wolf", humanoid="bandit", undead="skeleton", construct="golem",
    elemental="lava", dragon="drake", void="voidcat",
}

D.ENEMY_FAMILY = {
    beast    = { name="野兽",   resist={fire=1.1,  poison=0.9},            armor_mul=1.0, drops={feather=0.30, oil=0.15, hide=0.20} },
    humanoid = { name="人形",   resist={},                                 armor_mul=1.0, drops={hide=0.25, oil=0.10} },
    undead   = { name="不死",   resist={fire=1.25, frost=0.8, poison=0.6}, armor_mul=1.0, drops={oil=0.10} },
    construct= { name="构造",   resist={fire=0.9,  frost=0.9, poison=0.4}, armor_mul=1.3, drops={bladestone=0.2} },  -- 高甲，怕穿甲
    elemental= { name="元素",   resist={fire=0.7,  frost=1.3, poison=0.8}, armor_mul=0.9, drops={venomsac=0.15} },   -- 抵抗火/弱冰(占位)
    dragon   = { name="巨龙",   resist={fire=0.7,  frost=0.7},             armor_mul=1.1, drops={oil=0.40, hide=0.30} },
    void     = { name="虚空",   resist={fire=0.9,  frost=0.9, poison=0.8}, armor_mul=1.0, drops={venomsac=0.10} },  -- 净化克之
}

D.ENEMY_ARCH = {
    boar  ={ name="野猪",   family="beast",    hp=1.0, dmg=1.0, armor=0.3, spd=0.55, color={0.6,0.45,0.35} },
    wolf  ={ name="野狼",   family="beast",    hp=0.8, dmg=1.2, armor=0.2, spd=0.85, color={0.5,0.5,0.55} },
    bandit={ name="强盗",   family="humanoid", hp=1.1, dmg=1.1, armor=0.5, spd=0.6,  color={0.7,0.5,0.3} },
    ogre  ={ name="食人魔", family="humanoid", hp=1.8, dmg=1.5, armor=0.6, spd=0.4,  color={0.45,0.6,0.3} },
    wraith={ name="幽魂",   family="undead",   hp=1.2, dmg=1.6, armor=0.3, spd=0.7,  color={0.55,0.45,0.75} },
    golem ={ name="石巨人", family="construct",hp=2.6, dmg=1.4, armor=1.2, spd=0.35, color={0.6,0.62,0.68} },
    -- 新增铺档敌型：虫(毒囊)/巨蝠/石像鬼/冰狼/熔岩兽/亡灵法师 等，按 family 主题化
    bug   ={ name="毒虫",   family="beast",    hp=0.7, dmg=1.0, armor=0.2, spd=0.9,  color={0.55,0.7,0.35}, drop_mat="venomsac" },
    bat   ={ name="巨蝠",   family="beast",    hp=0.9, dmg=1.3, armor=0.2, spd=0.95, color={0.4,0.35,0.45} },
    gargoyle={name="石像鬼",family="construct",hp=2.0, dmg=1.5, armor=1.0, spd=0.45, color={0.5,0.52,0.58} },
    icewolf={ name="冰狼",   family="beast",    hp=1.3, dmg=1.6, armor=0.4, spd=0.85, color={0.6,0.85,0.95} },
    lava  ={ name="熔岩兽", family="elemental",hp=1.7, dmg=1.9, armor=0.6, spd=0.5,  color={0.85,0.45,0.25} },
    lich  ={ name="亡灵法师",family="undead",  hp=1.4, dmg=2.0, armor=0.4, spd=0.6,  color={0.5,0.55,0.7} },
    -- 高级敌型（36-60 高区用）
    frost   ={ name="霜魔",     family="elemental",hp=1.5, dmg=1.7, armor=0.5, spd=0.6,  color={0.6,0.8,0.95} },
    voidcat ={ name="虚空兽",   family="void",     hp=1.4, dmg=2.0, armor=0.4, spd=0.78, color={0.55,0.4,0.7} },
    drake   ={ name="幼龙",     family="dragon",   hp=2.2, dmg=1.8, armor=0.9, spd=0.5,  color={0.75,0.4,0.32} },
    revenant={ name="亡灵骑士", family="undead",   hp=1.9, dmg=1.6, armor=1.1, spd=0.55, color={0.5,0.55,0.62} },
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

-- ============================================================================
-- 副本系统(§6)：后期主循环。一个副本 = 固定波次小怪 + 1 boss，用当前 build 自动打。
--   进入成本：探险许可 energy(随时间恢复，离线也涨，封顶) + 可选 boss 钥匙(掉落)。
--   结算：经验大包(boss_level*60) + 肥掉落表(保底 rare+、unique 武器、特殊材料、钥匙)。
-- ============================================================================
-- 探险许可(energy)：随时间恢复，离线也算(基于 last_time 时间戳)。
D.ENERGY_MAX = 100          -- 许可封顶
D.ENERGY_REGEN = 100/3600   -- 每秒恢复量(满恢复 ≈1 小时；离线照算)

-- boss 钥匙材料(高档副本要钥匙作第二轨)。掉落于对应档副本，作特殊掉落。
D.DUNGEON_KEYS = {
    iron_key  = { name="铁牢钥匙",   color={0.7,0.74,0.8},  desc="开启中级副本的钥匙。副本 boss 掉落。" },
    ember_key = { name="熔火钥匙",   color={0.95,0.5,0.25}, desc="开启高级熔狱类副本的钥匙。boss 掉落。" },
    void_key  = { name="虚空之钥",   color={0.6,0.4,0.75},  desc="开启顶级副本的钥匙。极稀有 boss 掉落。" },
}
for id,k in pairs(D.DUNGEON_KEYS) do D.MAT_NAME[id]=k.name; D.MAT_COLOR[id]=k.color; D.MAT_DESC[id]=k.desc end

-- boss 敌型(用 family + 机制系数逼不同 build)：
--   hp/dmg/armor/spd 是相对 ENEMY_ARCH 的基底(boss 在 make_boss 里再 ×大倍率)。
--   mech 标记主要机制(展示提示)：high_armor(逼穿甲/弩) / high_freq(逼叠层短弓/AOE) / element(逼对应抗性箭)。
D.BOSSES = {
    alpha_wolf  = { name="头狼·铁牙",   family="beast",    hp=8,  dmg=1.4, armor=0.5, spd=1.0, color={0.55,0.55,0.62}, mech="high_freq", tip="出手频繁，宜叠层短弓/群体箭" },
    bog_horror  = { name="沼骇",         family="undead",   hp=10, dmg=1.6, armor=0.6, spd=0.7, color={0.5,0.6,0.45}, mech="element", tip="不死，火/净化箭克之" },
    stone_lord  = { name="磐石领主",     family="construct",hp=14, dmg=1.5, armor=1.6, spd=0.5, color={0.6,0.62,0.7},  mech="high_armor", tip="重甲，穿甲/破甲/弩破之" },
    frost_queen = { name="冰霜女王",     family="elemental",hp=13, dmg=1.8, armor=0.7, spd=0.8, color={0.6,0.85,0.97}, mech="element", tip="冰抗高，火/物理破之" },
    lava_tyrant = { name="熔岩暴君",     family="elemental",hp=16, dmg=2.0, armor=0.9, spd=0.65,color={0.9,0.45,0.25}, mech="element", tip="火抗高，冰/物理/穿甲破之" },
    void_warden = { name="虚空守望者",   family="void",     hp=18, dmg=2.1, armor=1.0, spd=0.75,color={0.6,0.4,0.75},  mech="element", tip="净化箭重创，全能 build 通吃" },
    throne_king = { name="陨灭之王",     family="dragon",   hp=24, dmg=2.3, armor=1.4, spd=0.7, color={0.8,0.45,0.35}, mech="high_armor", tip="毕业级：高甲高频，毕业 build 试金石" },
}

-- 副本表：按地区进度解锁(unlock=region id)。tier 用于分组展示。
--   min_lvl 推荐等级；waves 小怪波数；boss=D.BOSSES id；mobs=波次小怪取自该表(无则用解锁区 enemies)。
--   cost_energy 进入耗许可；key 需要的钥匙材料 id(nil=只耗许可)。
--   drops：rar_floor 保底稀有度、unique_chance 命名武器概率、mats 特殊材料保底量、key_chance boss 钥匙掉率。
D.DUNGEONS = {
    -- ---- 低级(low) ----
    { id="darkwood_warren", name="幽林兽穴", tier="low",  min_lvl=8,  waves=3, boss="alpha_wolf",  unlock="darkwood", cost_energy=18, key=nil,
      mobs={"wolf","boar","bat"},
      drops={ rar_floor="rare", unique_chance=0.04, mats={feather=4, oil=2, hide=3}, key_chance=0 } },
    { id="sunken_crypt",    name="沉没墓窖", tier="low",  min_lvl=13, waves=3, boss="bog_horror",  unlock="fen",      cost_energy=22, key=nil,
      mobs={"wraith","bug","ogre"},
      drops={ rar_floor="rare", unique_chance=0.06, mats={venomsac=3, oil=3, bladestone=2}, key_chance=0.12, key_id="iron_key" } },
    -- ---- 中级(mid) ----
    { id="quarry_depths",   name="碎石深坑", tier="mid",  min_lvl=20, waves=4, boss="stone_lord",  unlock="hollow",   cost_energy=28, key="iron_key",
      mobs={"golem","gargoyle","wraith"},
      drops={ rar_floor="epic", unique_chance=0.10, mats={bladestone=4, sulfur=3, leather=2}, key_chance=0.10, key_id="iron_key" } },
    { id="frozen_hall",     name="冰封殿堂", tier="mid",  min_lvl=27, waves=4, boss="frost_queen", unlock="peak",     cost_energy=32, key="iron_key",
      mobs={"icewolf","golem","wraith"},
      drops={ rar_floor="epic", unique_chance=0.12, mats={hide=4, oil=3, leather=3}, key_chance=0.12, key_id="ember_key" } },
    -- ---- 高级(high) ----
    { id="cinder_forge",    name="熔狱熔炉", tier="high", min_lvl=45, waves=5, boss="lava_tyrant",  unlock="cinder",   cost_energy=40, key="ember_key",
      mobs={"lava","drake","golem"},
      drops={ rar_floor="epic", unique_chance=0.18, mats={oil=5, sulfur=4, leather=4}, key_chance=0.12, key_id="ember_key" } },
    { id="void_breach",     name="虚空裂隙", tier="high", min_lvl=52, waves=5, boss="void_warden",  unlock="rift",     cost_energy=46, key="ember_key",
      mobs={"voidcat","revenant","lich"},
      drops={ rar_floor="legendary", unique_chance=0.22, mats={venomsac=5, hide=5, leather=5}, key_chance=0.10, key_id="void_key" } },
    { id="throne_sanctum",  name="王座圣所", tier="high", min_lvl=58, waves=6, boss="throne_king",  unlock="throne",   cost_energy=55, key="void_key",
      mobs={"drake","revenant","voidcat","golem"},
      drops={ rar_floor="legendary", unique_chance=0.30, mats={oil=6, leather=6, hide=6}, key_chance=0.06, key_id="void_key" } },
}
D.DUNGEON = {}; for _,dg in ipairs(D.DUNGEONS) do D.DUNGEON[dg.id]=dg end
-- 副本分组展示顺序(沿用 TIER_ORDER：low/mid/high)

-- ── 像素风「暮色猎人」调色（与 _pixel_ref/scene_hero_ref.lua 同一套暮色色域）──
-- 扁平硬边：实色填充 + 1px 硬描边 + 一条简单高光，无圆角/阴影/渐变/抗锯齿。
-- UI 直接走这套色；base/draw 把 panel/button/bar 重绘为像素扁平件。
D.UI = {
    bg={0.09,0.08,0.18},                       -- 暮色夜空底（sky_top）
    panel={0.13,0.12,0.22,0.97},               -- 面板实色（深暮蓝）
    panel_lo={0.10,0.09,0.17,0.97},            -- 面板暗格/凹槽
    line={0.34,0.27,0.42},                      -- 1px 硬描边（暮色地平线紫）
    line_hi={0.50,0.42,0.58},                   -- 高光描边
    text={0.94,0.92,0.86},                      -- 暖白文字（moon 色）
    dim={0.62,0.58,0.70},                       -- 次要文字（冷暮灰紫）
    good={0.40,0.78,0.46},                      -- 生命/正向（grassHi）
    bad={0.86,0.32,0.30},                       -- 伤害/负向（暖红）
    gold={0.96,0.75,0.34},                      -- 强调金（acc 琥珀金）
    xp={0.45,0.50,0.85},                        -- 经验蓝紫
    btn={0.31,0.42,0.58},                       -- 按钮（暮色钢蓝）
}
-- 场景画布像素调色（供 view/sprites + combat_view 画低分场景）。复用 ref 暮色色名。
D.PIX = {
    sky_top={0.09,0.08,0.18}, sky_mid={0.17,0.15,0.31}, sky_hor={0.34,0.27,0.42}, warm={0.55,0.36,0.44},
    moon={0.94,0.91,0.80},
    hill_far={0.21,0.21,0.35}, hill_mid={0.15,0.23,0.31},
    grass={0.25,0.44,0.33}, grass_hi={0.35,0.57,0.40}, grass_dk={0.17,0.33,0.26},
    dirt={0.44,0.33,0.23}, dirt_hi={0.55,0.43,0.30},
    fol={0.23,0.50,0.34}, fol_hi={0.37,0.65,0.45}, fol_dk={0.14,0.33,0.24},
    trunk={0.41,0.28,0.18}, trunk_dk={0.27,0.18,0.11},
    fire1={0.99,0.80,0.38}, fire2={0.97,0.52,0.21},
    acc={0.96,0.75,0.34}, fly={0.87,0.93,0.62},
    outl={0.11,0.09,0.12}, skin={0.93,0.74,0.52}, hood={0.28,0.50,0.36}, hood_hi={0.38,0.64,0.46},
}

return D
