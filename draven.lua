if Player.CharName ~= "Draven" then
    return
end

module("Ovior Draven", package.seeall, log.setup)
clean.module("Ovior Draven", clean.seeall, log.setup)

local _VER = "1.0.0"
CoreEx.AutoUpdate("https://raw.githubusercontent.com/dgagn/ovior/master/draven.lua", _VER)
local _LASTMOD = "16-07-2022"

local Vector = CoreEx.Geometry.Vector
local TargetSelector = _G.Libs.TargetSelector()
local Orbwalker = _G.Libs.Orbwalker

---@class Vec
local Vec = {}

---@param v1 Vector
---@param v2 Vector
function Vec.Sub(v1, v2)
    return Vector(v1.x - v2.x, v1.y - v2.y, v1.z - v2.z)
end

function Vec.Tuple(v1, v2)
    return {
        v1 = v1,
        v2 = v2
    }
end

---Returns if the number is between
---@param num number
---@param inf number
---@param sup number
---@return boolean bool if the number is between
local function between(num, inf, sup)
    return num >= inf and num <= sup
end

---@param r integer between 0 and 255 the reds
---@param g integer between 0 and 255 the greens
---@param b integer between 0 and 255 the blues
---@param a number|nil between 0 and 1 (opacity)
local function rgba(r, g, b, a)
    a = a or 1
    if not (between(r, 0, 255) and between(g, 0, 255) and between(b, 0, 255) and between(a, 0, 1)) then
        return 0
    end
    local nr, ng, nb = string.format("%x", r), string.format("%x", g), string.format("%x", b)
    local na = string.format("%x", a * 255)
    return tonumber(string.format("%s%s%s%s", nr, ng, nb, na))
end

local Menu = _G.Libs.NewMenu
local Renderer = CoreEx.Renderer

---@param T table
local function tablelength(T)
    local count = 0
    for _ in pairs(T) do count = count + 1 end
    return count
end

---@class Draven
local Draven = {}

Draven.Spells = {
    AA = {
        Range = 550
    },
    Q = Libs.Spell.Active({
        Slot = CoreEx.Enums.SpellSlots.Q,
    }),
    W = Libs.Spell.Active({
        Slot = CoreEx.Enums.SpellSlots.W,
    }),
    E = Libs.Spell.Skillshot({
        Slot = CoreEx.Enums.SpellSlots.E,
        Type = "Linear",
        Collisions = { Minions = true, WindWall = true, Heroes = true },
        Range = 1100,
        Speed = 1400,
        Delay = 0.25,
        Radius = 260,
        UseHitbox = true
    }),
    R = Libs.Spell.Skillshot({
        Slot = CoreEx.Enums.SpellSlots.R,
        Range = 2000,
        Speed = 2000,
        Delay = 0.6,
        Radius = 140,
        Type = "Linear",
        Collisions = {
            Heroes = true,
            WindWall = true
        }
    })
}

function OnLoad()
    Draven.LoadMenu()
    Draven.HasEssenceReaver()
    for eventName, eventId in pairs(CoreEx.Enums.Events) do
        if Draven[eventName] then
            CoreEx.EventManager.RegisterCallback(eventId, Draven[eventName])
        end
    end

    return true;
end

local function GameIsAvailable()
    return not (CoreEx.Game.IsChatOpen() or CoreEx.Game.IsMinimized() or Player.IsDead or Player.IsRecalling)
end

local lastTick = 0
function Draven.OnTick()
    if not GameIsAvailable() then return end

    local gameTime = CoreEx.Game.GetTime()
    if gameTime < (lastTick + 0.25) then return end
    lastTick = gameTime

    Draven.Auto()

    Draven.MoveSafeReticles()

    local orbwalkerFunc = Draven[Orbwalker.GetMode()]
    if orbwalkerFunc then
        orbwalkerFunc()
    end
end

function Draven.Auto()
    if Menu.Get("Auto.R.Enabled") then
        Draven.AutoR()
    end

    if Menu.Get("Auto.FarW.Enabled") then
        local manaAvail = Menu.Get("Auto.FarW.Mana")

        if Player.ManaPercent < manaAvail then
            return
        end

        Draven.FarReticleW(Menu.Get("Auto.FarW.Range"))
        return
    end
end

function Draven.MoveSafeReticles()
    if not Menu.Get("Axe.Enabled") then
        return
    end

    if next(Draven.Reticles) == nil then
        return
    end

    local closest = Draven.GetClosestReticle()
    local reticle = CoreEx.Geometry.Circle(closest.Position, closest.BoundingRadius)
    local paths = reticle:GetPoints()
    local vector = closest.Position
    local shortest = closest.Position:Distance(Player.Position)

    for _, path in pairs(paths) do
        local pos = path:Distance(Player.Position)
        if pos < shortest and CoreEx.EvadeAPI.IsPointSafe(vector) then
            shortest = pos
            vector = path
        end
    end

    if Menu.Get("Axe.IgnoreTurrets.Enabled") then
        for _, turret in pairs(CoreEx.ObjectManager.GetNearby("enemy", "turrets")) do
            turret = turret.AsTurret
            if turret and turret.IsOnScreen and turret.IsAlive then
                local distance = turret.Position:Distance(vector)
                local turretLength = 850
                if distance < turretLength then
                    return
                end
            end
        end
    end

    if not CoreEx.EvadeAPI.IsEvading() then
        Orbwalker.Move(vector)
    end
end

function Draven.Combo()
    if Menu.Get("Combo.W.Enabled") then
        Draven.ComboW()
    end

    if Menu.Get("Combo.E.Enabled") then
        Draven.ComboE()
    end
end

function Draven.AutoR()
    local cannotHitRange = Draven.Spells.AA.Range

    for _, target in ipairs(Draven.Spells.R:GetTargets()) do
        if not Menu.Get("Auto.R.IgnoreRange") then
            local dist = Player:Distance(target.Position)
            if dist < cannotHitRange then
                return
            end
        end
        if not Draven.Spells.R:CanKillTarget(target, nil, Draven.Spells.R:GetDamage(target)) then
            return
        end

        local pathToEnemy = CoreEx.Geometry.Path(Player.Position, target.Position)
        local enemyInBetween = false
        for _, v in pairs(CoreEx.ObjectManager.Get("enemy", "heroes")) do
            local hero = v.AsHero
            if hero and hero.IsTargetable and hero.IsOnScreen and not Draven.Spells.R:CanKillTarget(hero, nil, Draven.Spells.R:GetDamage(target)) and pathToEnemy:Contains(hero.Position) then
                enemyInBetween = true
            end
        end
        if not enemyInBetween then
            Draven.Spells.R:CastOnHitChance(target, Menu.Get("Auto.R.Chance"))
        end
    end
end

function Draven.CountEnemyInAARange()
    local count = 0
    for _, _ in ipairs(TargetSelector:GetTargets(Draven.Spells.AA.Range)) do
        count = count + 1
    end
    return count
end

function Draven.ComboW()
    local manaAvail = Menu.Get("Combo.W.Mana")

    if Player.ManaPercent < manaAvail then
        return
    end

    local enemyInRange = Draven.CountEnemyInAARange()
    if enemyInRange > 0 then
        local hasReticles = Draven.GetReticlesCount() > 0
        if hasReticles and Draven.Spells.W:IsReady() then
            Draven.Spells.W:Cast()
        end
    end
end

function Draven.ComboE()
    local eChance = Menu.Get("Combo.E.Chance")
    local manaAvail = Menu.Get("Combo.E.Mana")

    if Player.ManaPercent < manaAvail then
        return
    end

    for _, wTarget in ipairs(TargetSelector:GetTargets(Draven.Spells.E.Range)) do
        Draven.Spells.E:CastOnHitChance(wTarget, eChance)
    end
end

function Draven.OnPreAttack()
    if not Draven.Spells.Q:IsReady() then return end
    local orbwalkerFunc = Draven[string.format("Pre%sQ", Orbwalker.GetMode())]
    if orbwalkerFunc then
        orbwalkerFunc()
    end
end

function Draven.HasEssenceReaver()
    for _, value in pairs(Player.Items) do
        if value.ItemId == 3508 then
            return true
        end
    end
    return false
end

function Draven.CanSpamW()
    return Draven.HasEssenceReaver() and Player.CritChance > 0.41
end

function Draven.GetFurthestReticle()
    local far = 0
    local reticle = nil
    for _, reticles in pairs(Draven.Reticles) do
        local dist = reticles:Distance(Player.Position)
        if dist > far then
            far = dist
            reticle = reticles
        end
    end
    return reticle
end

function Draven.GetClosestReticle()
    local far = math.huge
    local reticle = nil
    for _, reticles in pairs(Draven.Reticles) do
        local dist = reticles:Distance(Player.Position)
        if dist < far then
            far = dist
            reticle = reticles
        end
    end
    return reticle
end

function Draven.IsFacingReticle()
    local far = false
    for _, reticle in pairs(Draven.Reticles) do
        local facing = Player:IsFacing(reticle, 90)
        if facing then
            return true
        end
    end
    return false
end

---@param target AIBaseClient
function Draven.OnPostAttack(target)
    if Menu.Get("Auto.SpamW.Enabled") then
        if not Draven.Spells.W:IsReady() then return end
        Draven.SpamW()
    end

    if not (target and target.AsHero and target.AsHero.IsEnemy) then
        return
    end
end

function Draven.SpamW()
    if Draven.CanSpamW() and Player.ManaPercent >= Menu.Get("Auto.SpamW.Mana") then
        Draven.Spells.W:Cast()
    end
end

---@param range integer|nil
function Draven.FarReticleW(range)
    local reticle = Draven.GetFurthestReticle()
    if reticle then
        local reticleDist = Player:Distance(reticle.Position)
        range = range or 250

        if (reticleDist > range or (Menu.Get("Auto.SlowedW.Enabled") and Player.IsSlowed)) and
            Player:IsFacing(reticle, 90) and Draven.Spells.W:IsReady() then
            Draven.Spells.W:Cast()
        end
    end
end

function Draven.HasAxes(numAxes)
    return Draven.GetAxesCount() < numAxes
end

function Draven.PreComboQ()
    if not Menu.Get("Combo.Q.Enabled") then
        return
    end
    local manaAvail = Menu.Get("Combo.Q.Mana")

    if Player.ManaPercent < manaAvail then
        return
    end

    if Draven.HasAxes(Menu.Get("Combo.Q.MinQ")) then
        Draven.Spells.Q:Cast()
    end
end

function Draven.PreWaveclearQ()
    if not Menu.Get("Waveclear.Q.Enabled") then
        return
    end

    local manaAvail = Menu.Get("Waveclear.Q.Mana")

    if Player.ManaPercent < manaAvail then
        return
    end
    
    if Draven.HasAxes(Menu.Get("Waveclear.Q.MinQ")) then
        Draven.Spells.Q:Cast()
    end
end

function Draven.PreLasthitQ()
    if not Menu.Get("Lasthit.Q.Enabled") then
        return
    end

    local manaAvail = Menu.Get("Lasthit.Q.Mana")

    if Player.ManaPercent < manaAvail then
        return
    end

    if Draven.HasAxes(Menu.Get("Lasthit.Q.MinQ")) then
        Draven.Spells.Q:Cast()
    end
end

function Draven.PreHarassQ()
    if not Menu.Get("Harass.Q.Enabled") then
        return
    end

    local manaAvail = Menu.Get("Harass.Q.Mana")

    if Player.ManaPercent < manaAvail then
        return
    end

    if Draven.HasAxes(Menu.Get("Harass.Q.MinQ")) then
        Draven.Spells.Q:Cast()
    end
end

function Draven.OnDraw()
    if not GameIsAvailable() then return end

    if Menu.Get("Drawing.Reticles.Enabled") then
        Draven.DrawReticles()
    end
    if Menu.Get("Drawing.E.Enabled") then
        Draven.DrawE()
    end
    if Menu.Get("Drawing.QDamage.Enabled") then
        Draven.DrawQHp()
    end

    if Menu.Get("Drawing.Gold.Enabled") then
        Draven.DrawGoldText()
    end
end

function Draven.DrawGoldText()
    local gold = string.format("%d G", Draven.GetAdorationStacksGold())
    Renderer.DrawTextOnPlayer(gold, Menu.Get("Drawing.Gold.Color"))
end

function Draven.DrawE()
    Renderer.DrawCircle3D(Player.Position, Draven.Spells.E.Range, 30, 2, Menu.Get("Drawing.E.Color"))
end

-- Draw HP

function Draven.DrawQHp()
    for _, v in pairs(CoreEx.ObjectManager.Get("enemy", "heroes")) do
        local hero = v.AsHero
        if hero and hero.IsTargetable and hero.IsOnScreen then
            local hp = Draven.CalculateHpVectorTuple(hero.HealthBarScreenPos, Draven.CalculateHpAxeDamage(hero))
            Renderer.DrawFilledRect(hp.v1, hp.v2, 30, Menu.Get("Drawing.QDamage.Color"))
        end
    end
end

---@param calcWidth number
function Draven.CalculateHpVectorTuple(v1, calcWidth)
    local size = Vector(calcWidth, 13)

    local fullWidth = 105
    local diff = fullWidth - calcWidth
    local subForCenterHP = Vector(46 - diff, 25)
    local sub = Vec.Sub(v1, subForCenterHP)


    return Vec.Tuple(sub, size)
end

---@param target AIHeroClient
function Draven.CalculateHpAxeDamage(target)
    local damage = Libs.DamageLib.GetAutoAttackDamage(Player, target, true)
    local percent = 1 - ((target.Health - damage) / target.MaxHealth)
    return percent * 105
end

--------------------------------------------------------

---@param source AIBaseClient
---@param dash DashInstance
function Draven.OnGapclose(source, dash)
    if not source.IsEnemy then return end

    if not (Draven.Spells.E:IsInRange(source.Position) and Menu.Get("Auto.GapE")) then
        return
    end

    if not source:IsFacing(Player.Position) then
        return
    end

    local paths = dash:GetPaths()
    local endPos = paths[#paths].EndPos
    local distToEnd = Player.Position:Distance(endPos)
    local distToStart = Player.Position:Distance(dash.StartPos)

    if distToEnd > distToStart then
        return
    end

    Draven.Spells.E:Cast(source)
end

---@param source AIBaseClient
---@param spell SpellCast
function Draven.OnInterruptibleSpell(source, spell, danger, endT, canMove)
    if not (source.IsEnemy and Draven.Spells.E:IsReady() and danger > 3 and Menu.Get("Auto.IntE")) then
        return
    end
    if not (Draven.Spells.E:IsInRange(source.Position)) then
        return
    end

    Draven.Spells.E:CastOnHitChance(source, CoreEx.Enums.HitChance.VeryHigh)
end

-- Reticles
---@type table<integer, GameObject>
Draven.Reticles = {}

function Draven.GetReticlesCount()
    return tablelength(Draven.Reticles)
end

function Draven.GetAxesCount()
    return Draven.GetReticlesCount() + Player:GetBuffCount("dravenspinningattack")
end

function Draven.DrawReticles()
    if next(Draven.Reticles) == nil then
        return
    end

    for _, reticles in pairs(Draven.Reticles) do
        CoreEx.Renderer.DrawCircle3D(reticles.Position, reticles.BoundingRadius, 30, 2,
            Menu.Get("Drawing.Reticles.Color"))
    end
end

---@param obj GameObject
function Draven.OnCreateObject(obj)
    if obj.Name == "Draven_Base_Q_reticle_self" then
        Draven.Reticles[obj.Handle] = obj
    end
end

---@param obj GameObject
function Draven.OnDeleteObject(obj)
    if obj.Name == "Draven_Base_Q_reticle_self" then
        Draven.Reticles[obj.Handle] = nil
    end
end

-- Gold
---@param stacks number
function Draven.CalculateAdorationStacksGold(stacks)
    return 40 + (2.5 * stacks)
end

function Draven.GetAdorationStacksGold()
    local currentPlayerStacks = Player:GetBuffCount("dravenpassivestacks")
    return Draven.CalculateAdorationStacksGold(currentPlayerStacks)
end

-- Menu

---@class MenuExtended
local MenuExtended = {}

---@param id string
---@param name string
---@param default boolean
function MenuExtended.DrawOption(id, name, default, color)
    color = color or rgba(255, 255, 255, 1)

    Menu.Checkbox(string.format("%s.Enabled", id), name, default)
    Menu.ColorPicker(string.format("%s.Color", id), "Color", color)
end

---@class DravenMenu
local DravenMenu = {}

function Draven.LoadMenu()
    Menu.RegisterMenu("OviorDraven", "Ovior Draven", DravenMenu.RegisterMenu, { Author = "Ovior", Version = _VER, LastModified=_LASTMOD })
end

function DravenMenu.RegisterMenu()
    Menu.NewTree("Axe", "Axe Catching Settings", DravenMenu.AxeSettings)
    Menu.Separator()
    Menu.NewTree("Combo", "Combo Settings", DravenMenu.ComboSettings)
    Menu.NewTree("Waveclear", "Waveclear Settings", DravenMenu.WaveclearSettings)
    Menu.NewTree("Lasthit", "Lasthit Settings", DravenMenu.LasthitSettings)
    Menu.NewTree("Harass", "Harass Settings", DravenMenu.HarassSettings)
    Menu.NewTree("Auto", "Auto Settings", DravenMenu.AutoSettings)

    Menu.Separator()

    Menu.NewTree("Drawing", "Drawing Settings", DravenMenu.DrawingSettings)
end

function DravenMenu.AxeSettings()
    Menu.Checkbox("Axe.Enabled", "Auto catch axes", true)
    Menu.Checkbox("Axe.IgnoreTurrets.Enabled", "Ignore axes in turret range", true)
end

function DravenMenu.ComboSettings()
    Menu.Checkbox("Combo.Q.Enabled", "Use [Q]", true)
    Menu.Slider("Combo.Q.MinQ", "Have at least [Q] Axes", 3, 0, 4, 1)
    Menu.Slider("Combo.Q.Mana", "Use if above Mana percent [W]", 0.20, 0, 1, 0.05)
    Menu.Separator()

    Menu.Checkbox("Combo.W.Enabled", "Use [W]", true)
    Menu.Slider("Combo.W.Mana", "Use if above Mana percent [W]", 0.30, 0, 1, 0.05)

    Menu.Separator()
    Menu.Checkbox("Combo.E.Enabled", "Use [E]", true)
    Menu.Slider("Combo.E.Chance", "HitChance [E]", 0.85, 0, 1, 0.05)
    Menu.Slider("Combo.E.Mana", "Use if above Mana percent [E]", 0.30, 0, 1, 0.05)

end

function DravenMenu.WaveclearSettings()
    Menu.Checkbox("Waveclear.Q.Enabled", "Use [Q]", true)
    Menu.Slider("Waveclear.Q.MinQ", "Have at least [Q] Axes", 2, 0, 4, 1)
    Menu.Slider("Waveclear.Q.Mana", "Use if above Mana percent [W]", 0.20, 0, 1, 0.05)
end

function DravenMenu.LasthitSettings()
    Menu.Checkbox("Lasthit.Q.Enabled", "Use [Q]", true)
    Menu.Slider("Lasthit.Q.MinQ", "Have at least [Q] Axes", 1, 0, 4, 1)
    Menu.Slider("Lasthit.Q.Mana", "Use if above Mana percent [W]", 0.20, 0, 1, 0.05)

end

function DravenMenu.HarassSettings()
    Menu.Checkbox("Harass.Q.Enabled", "Use [Q]", true)
    Menu.Slider("Harass.Q.MinQ", "Have at least [Q] Axes", 2, 0, 4, 1)
    Menu.Slider("Harass.Q.Mana", "Use if above Mana percent [W]", 0.20, 0, 1, 0.05)
end

function DravenMenu.AutoSettings()
    Menu.Checkbox("Auto.KeepQ.Enabled", "Auto [Q] when buff is over", true)
    Menu.Slider("Auto.KeepQ.Mana", "Above mana percent", 0.20, 0, 1, 0.05)

    Menu.Checkbox("Auto.IgnoreTurret.Enabled", "Ignore Axes in turrets", true)


    Menu.Separator()

    Menu.Checkbox("Auto.SpamW.Enabled", "Auto [W] if can sustain", true)
    Menu.Slider("Auto.SpamW.Mana", "Above mana percent", 0.10, 0, 1, 0.05)
    Menu.Checkbox("Auto.SlowedW.Enabled", "Auto [W] if slowed while catching", true)
    Menu.Checkbox("Auto.FarW.Enabled", "Auto [W] if reticles far", true)
    Menu.Slider("Auto.FarW.Range", "Reticles range", 250, 50, 400, 50)
    Menu.Slider("Auto.FarW.Mana", "Above mana percent", 0.30, 0, 1, 0.05)

    Menu.Separator()

    Menu.Checkbox("Auto.GapE", "Auto [E] on Gap Close", true)
    Menu.Checkbox("Auto.IntE", "Auto [E] on Interruptable Spells", true)

    Menu.Separator()

    Menu.Checkbox("Auto.R.Enabled", "Use [R] for kills", true)
    Menu.Slider("Auto.R.Chance", "HitChance [R]", 0.5, 0, 1, 0.05)
    Menu.Checkbox("Auto.R.IgnoreRange", "Ignore range for [R]", true)
end

function DravenMenu.DrawingSettings()
    MenuExtended.DrawOption("Drawing.Reticles", "Draw the axe reticle", true)
    MenuExtended.DrawOption("Drawing.QDamage", "Draw [Q] Damage on HP", false, rgba(0, 0, 0, 0.75))
    MenuExtended.DrawOption("Drawing.E", "Draw [E] Range", true, rgba(255, 255, 255, 0.2))
    MenuExtended.DrawOption("Drawing.Gold", "Draw Gold Adorations", true, 0xBCEE08FF)
end
