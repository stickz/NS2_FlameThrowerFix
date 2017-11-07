-- ======= Copyright (c) 2003-2011, Unknown Worlds Entertainment, Inc. All rights reserved. =======
--
-- lua\Weapons\Flamethrower.lua
--
--    Created by:   Charlie Cleveland (charlie@unknownworlds.com)
--
-- ========= For more information, visit us at http://www.unknownworlds.com =====================

Script.Load("lua/Weapons/Weapon.lua")
Script.Load("lua/Weapons/Marine/Flame.lua")
Script.Load("lua/PickupableWeaponMixin.lua")
Script.Load("lua/LiveMixin.lua")
Script.Load("lua/PointGiverMixin.lua")
Script.Load("lua/AchievementGiverMixin.lua")

class 'Flamethrower' (ClipWeapon)

if Client then
    Script.Load("lua/Weapons/Marine/Flamethrower_Client.lua")
end

Flamethrower.kMapName = "flamethrower"

Flamethrower.kModelName = PrecacheAsset("models/marine/flamethrower/flamethrower.model")
local kViewModels = GenerateMarineViewModelPaths("flamethrower")
local kAnimationGraph = PrecacheAsset("models/marine/flamethrower/flamethrower_view.animation_graph")

local kFireLoopingSound = PrecacheAsset("sound/NS2.fev/marine/flamethrower/attack_loop")

local kRange = kFlamethrowerRange
local kUpgradedRange = kFlamethrowerUpgradedRange

Flamethrower.kConeWidth = 0.3
Flamethrower.kDamageRadius = 2.0

local networkVars =
{ 
    createParticleEffects = "boolean",
    animationDoneTime = "float",
    loopingSoundEntId = "entityid",
    range = "integer (0 to 11)"
}

AddMixinNetworkVars(LiveMixin, networkVars)

function Flamethrower:OnCreate()

    ClipWeapon.OnCreate(self)
    
    self.loopingSoundEntId = Entity.invalidId
    
    if Server then
    
        self.createParticleEffects = false
        self.animationDoneTime = 0
        
        self.loopingFireSound = Server.CreateEntity(SoundEffect.kMapName)
        self.loopingFireSound:SetAsset(kFireLoopingSound)
        self.loopingFireSound:SetParent(self)
        self.loopingSoundEntId = self.loopingFireSound:GetId()
        
    elseif Client then    
        self:SetUpdates(true)
        self.lastAttackEffectTime = 0.0        
    end
    
    InitMixin(self, PickupableWeaponMixin)
    InitMixin(self, LiveMixin)
    InitMixin(self, PointGiverMixin)
    InitMixin(self, AchievementGiverMixin)
end

function Flamethrower:OnDestroy()

    ClipWeapon.OnDestroy(self)
    
    -- The loopingFireSound was already destroyed at this point, clear the reference.
    if Server then
        self.loopingFireSound = nil
    elseif Client then
    
        if self.trailCinematic then
            Client.DestroyTrailCinematic(self.trailCinematic)
            self.trailCinematic = nil
        end
        
        if self.pilotCinematic then
            Client.DestroyCinematic(self.pilotCinematic)
            self.pilotCinematic = nil
        end        
    end    
end

function Flamethrower:GetAnimationGraphName()
    return kAnimationGraph
end

-- extracted via model analyzer tool, this is the bounding box origin of the model.
local transformVector = Vector(0.3868434429168701, -0.010511890053749084, -0.060572415590286255)
function Flamethrower:GetPickupOrigin()
    return self:GetCoords():TransformPoint(transformVector)
end

function Flamethrower:GetWeight()
    return kFlamethrowerWeight
end

function Flamethrower:OnHolster(player)
    ClipWeapon.OnHolster(self, player)    
    self.createParticleEffects = false    
end

function Flamethrower:OnDraw(player, previousWeaponMapName)

    ClipWeapon.OnDraw(self, player, previousWeaponMapName)
    
    self.createParticleEffects = false
    self.animationDoneTime = Shared.GetTime()    
end

function Flamethrower:GetClipSize()
    return kFlamethrowerClipSize
end

function Flamethrower:CreatePrimaryAttackEffect(player)
    -- Remember this so we can update gun_loop pose param
    self.timeOfLastPrimaryAttack = Shared.GetTime()
end

function Flamethrower:GetRange()
    return self.range
end

function Flamethrower:GetViewModelName(sex, variant)
    return kViewModels[sex][variant]
end

local function GetUmbrasInRange(checkAtPoint)
	local umbras = GetEntitiesWithinRange("CragUmbra", checkAtPoint, CragUmbra.kRadius)
	table.copy(GetEntitiesWithinRange("StormCloud", checkAtPoint, StormCloud.kRadius), umbras, true)
	table.copy(GetEntitiesWithinRange("MucousMembrane", checkAtPoint, MucousMembrane.kRadius), umbras, true)
	table.copy(GetEntitiesWithinRange("EnzymeCloud", checkAtPoint, EnzymeCloud.kRadius), umbras, true)
	return umbras
end

local function GetBileInRange(checkAtPoint)
	local bombs = GetEntitiesWithinRange("Bomb", checkAtPoint, 1.6)
	table.copy(GetEntitiesWithinRange("WhipBomb", checkAtPoint, 1.6), bombs, true)
	return bombs
end

function Flamethrower:BurnSporesAndUmbra(startPoint, endPoint)

    local toTarget = endPoint - startPoint
    local distanceToTarget = toTarget:GetLength()
    toTarget:Normalize()

	local checkAtPoint = startPoint + toTarget * distanceToTarget
        
	-- for the index and bomb entity in range
	for index, bomb in ipairs(GetBileInRange(checkAtPoint)) do
		bomb:TriggerEffects("burn_bomb", { effecthostcoords = Coords.GetTranslation(bomb:GetOrigin()) } )
		DestroyEntity(bomb)
	end
		
	-- for the index and spore entity in range
	for index, spore in ipairs(GetEntitiesWithinRange("SporeCloud", checkAtPoint, kSporesDustCloudRadius)) do
		self:TriggerEffects("burn_spore", { effecthostcoords = Coords.GetTranslation(spore:GetOrigin()) } )
		DestroyEntity(spore)
	end

    -- for the index and umbra entity in range
	for index, umbra in ipairs(GetUmbrasInRange(checkAtPoint)) do
		self:TriggerEffects("burn_umbra", { effecthostcoords = Coords.GetTranslation(umbra:GetOrigin()) } )
		DestroyEntity(umbra)
	end
end

function Flamethrower:CreateFlame(player, position, normal, direction)

    -- create flame entity, but prevent spamming:
    if table.icount(GetEntitiesForTeamWithinRange("Flame", self:GetTeamNumber(), position, 1.7)) == 0 then
    
        local flame = CreateEntity(Flame.kMapName, position, player:GetTeamNumber())
        flame:SetOwner(player)
        
        local coords = Coords.GetTranslation(position)
        coords.yAxis = normal
        coords.zAxis = direction
        
        coords.xAxis = coords.yAxis:CrossProduct(coords.zAxis)
        coords.xAxis:Normalize()
        
        coords.zAxis = coords.xAxis:CrossProduct(coords.yAxis)
        coords.zAxis:Normalize()
        
        flame:SetCoords(coords)      
    end
end

local groundTraceVector = Vector(0, -2.6, 0)
function Flamethrower:ApplyConeDamage(player)
    
    local eyePos  = player:GetEyePos()    
    local ents = {}

    local fireDirection = player:GetViewCoords().zAxis
    
    local startPoint = Vector(eyePos)
    local filterEnts = {self, player}
    local trace = TraceMeleeBox(self, startPoint, fireDirection, Vector(self.kConeWidth, self.kConeWidth, self.kConeWidth), self:GetRange(), PhysicsMask.Flame, EntityFilterList(filterEnts))
    
        -- Check for spores in the way.
    if Server then
        self:BurnSporesAndUmbra(startPoint, trace.endPoint)
    end
        
    if trace.fraction ~= 1 then

        local traceEnt = trace.entity
        
        if traceEnt then
            
            if HasMixin(traceEnt, "Live") and traceEnt:GetCanTakeDamage() then
                table.insert(ents, traceEnt)
            end

            -- for the index and radius of the hit entities ?
            for index, entRadius in ipairs(GetEntitiesWithMixinWithinRange("Live", trace.endPoint, Flamethrower.kDamageRadius)) do
                if entRadius ~= traceEnt and entRadius:GetCanTakeDamage() then
                    table.insert(ents, entRadius)
                end
            end
            
            --Create flame below target
            if Server then
                local groundTrace = Shared.TraceRay(trace.endPoint, trace.endPoint + groundTraceVector, CollisionRep.Default, PhysicsMask.CystBuild, EntityFilterAllButIsa("TechPoint"))
                if groundTrace.fraction ~= 1 then
                    fireDirection = fireDirection * 0.55 + trace.normal
                    fireDirection:Normalize()
                    
                    self:CreateFlame(player, groundTrace.endPoint, groundTrace.normal, fireDirection)
                end
            end
			
                
        else
                
            if Server then
                fireDirection = fireDirection * 0.55 + trace.normal
                fireDirection:Normalize()

                self:CreateFlame(player, trace.endPoint, trace.normal, fireDirection)
            end        
        end
    end
    
    
    for _, ent in ipairs(ents) do

        if ent ~= player then
        
            local enemyOrigin = ent:GetModelOrigin()            
            
            local prevHealth = ent:GetHealth()
            
			-- GetNormalizedVector = distance to enemy
			self:DoDamage( kFlamethrowerDamage, ent, enemyOrigin, GetNormalizedVector( enemyOrigin - eyePos) )

            -- Only light on fire if we successfully damaged them
            if ent:GetHealth() ~= prevHealth and HasMixin(ent, "Fire") then
                ent:SetOnFire(player, self)
            end
            
            if ent.GetEnergy and ent.SetEnergy then
                ent:SetEnergy(ent:GetEnergy() - kFlameThrowerEnergyDamage)
            end
        end    
    end    
end

local pi2 = math.pi/2
local zeroAngle = Angles(0,0,0)
function Flamethrower:ShootFlame(player)

    local viewCoords = player:GetViewAngles():GetCoords()
    
    local barrelPoint = self:GetBarrelPoint(player)
	viewCoords.origin = barrelPoint + viewCoords.zAxis * (-0.4) + viewCoords.xAxis * (-0.2)
    local endPoint = barrelPoint + viewCoords.xAxis * (-0.2) + viewCoords.yAxis * (-0.3) + viewCoords.zAxis * self:GetRange()
    
    local trace = Shared.TraceRay(viewCoords.origin, endPoint, CollisionRep.Damage, PhysicsMask.Flame, EntityFilterAll())
    
    local range = (trace.endPoint - viewCoords.origin):GetLength()
    if range < 0 then
        range = range * (-1)
    end
    
    if trace.endPoint ~= endPoint and trace.entity == nil then
    
        local angles = zeroAngle
        angles.yaw = GetYawFromVector(trace.normal)
        angles.pitch = GetPitchFromVector(trace.normal) + pi2
        
        local normalCoords = angles:GetCoords()
        normalCoords.origin = trace.endPoint
        range = range - 3        
    end
    
    self:ApplyConeDamage(player)
end

function Flamethrower:FirePrimary(player, bullets, range, penetration)
    self:ShootFlame(player)
end

function Flamethrower:GetDeathIconIndex()
    return kDeathMessageIcon.Flamethrower
end

function Flamethrower:GetHUDSlot()
    return kPrimaryWeaponSlot
end

function Flamethrower:GetIsAffectedByWeaponUpgrades()
    return false
end

local clip = nil
local fTime = nil
function Flamethrower:OnPrimaryAttack(player)

    if not self:GetIsReloading() then
    
        ClipWeapon.OnPrimaryAttack(self, player)
        
        clip = self:GetClip()
		if self:GetIsDeployed() and clip > 0 and self:GetPrimaryAttacking() then
        
            if not self.createParticleEffects then
                self:TriggerEffects("flamethrower_attack_start")
            end
        
            self.createParticleEffects = true
            
            if Server and not self.loopingFireSound:GetIsPlaying() then
                self.loopingFireSound:Start()
            end            
        end
        
        if self.createParticleEffects and clip == 0 then
        
            self.createParticleEffects = false
            
            if Server then
                self.loopingFireSound:Stop()
            end    
        end
    
        -- Fire the cool flame effect periodically
        -- Don't crank the period too low - too many effects slows down the game a lot.
		if Client and self.createParticleEffects then 
			fTime = Shared.GetTime()
			if self.lastAttackEffectTime + 0.5 < fTime then            
				self:TriggerEffects("flamethrower_attack")
				self.lastAttackEffectTime = fTime
			end
        end        
    end    
end

function Flamethrower:OnPrimaryAttackEnd(player)

    ClipWeapon.OnPrimaryAttackEnd(self, player)

    self.createParticleEffects = false
        
    if Server then    
        self.loopingFireSound:Stop()        
    end    
end

function Flamethrower:OnReload(player)

    if self:CanReload() then
    
        if Server then        
            self.createParticleEffects = false
            self.loopingFireSound:Stop()        
        end
        
        self:TriggerEffects("reload")
        self.reloading = true        
    end    
end

function Flamethrower:GetUpgradeTechId()
    return kTechId.FlamethrowerRangeTech
end

function Flamethrower:GetHasSecondary(player)
    return false
end

function Flamethrower:GetSwingSensitivity()
    return 0.8
end

function Flamethrower:Dropped(prevOwner)

    ClipWeapon.Dropped(self, prevOwner)
    
    if Server then    
        self.createParticleEffects = false
        self.loopingFireSound:Stop()        
    end    
end

function Flamethrower:GetAmmoPackMapName()
    return FlamethrowerAmmo.kMapName
end

function Flamethrower:GetNotifiyTarget()
    return false
end

local idleAnimations = {"idle", "idle_fingers", "idle_clean"}
function Flamethrower:GetIdleAnimations(index)
    return idleAnimations[index]
end

function Flamethrower:ModifyDamageTaken(damageTable, attacker, doer, damageType)
    if damageType ~= kDamageType.Corrode then
        damageTable.damage = 0
    end
end

function Flamethrower:GetCanTakeDamageOverride()
    return self:GetParent() == nil
end

if Server then
    function Flamethrower:OnKill()
        DestroyEntity(self)
    end
    
    function Flamethrower:GetSendDeathMessageOverride()
        return false
    end 
    
    function Flamethrower:OnProcessMove(input)
        
        ClipWeapon.OnProcessMove(self, input)
        
        local hasRangeTech = false
        local parent = self:GetParent()
        if parent then
            hasRangeTech = GetHasTech(parent, kTechId.FlamethrowerRangeTech)
        end
        
        self.range = hasRangeTech and kUpgradedRange or kRange
    end    
end

if Client then
    function Flamethrower:GetUIDisplaySettings()
        return { xSize = 128, ySize = 256, script = "lua/GUIFlamethrowerDisplay.lua" }
    end
end

Shared.LinkClassToMap("Flamethrower", Flamethrower.kMapName, networkVars)
