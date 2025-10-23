AddCSLuaFile()

ENT.Base = "base_anim" 
ENT.Type = "ai"
ENT.PrintName = "Crossplay Prop"
ENT.Spawnable = false

ENT.AutomaticFrameAdvance = true -- important for gesture speed and animation control

-- Use this to slow down gesture animation playback
ENT.GesturePlaybackRate = 0.8 -- 1.0 = normal, <1 = slower

AccessorFunc( ENT, "m_iClass", "NPCClass" )

function ENT:Initialize()
    if SERVER then  
        self:SetCollisionGroup(COLLISION_GROUP_NPC)
        self:SetMoveType(MOVETYPE_STEP)
        self:PhysicsInit(SOLID_BBOX)
        self:SetNPCClass(CLASS_PLAYER_ALLY)
        self:SetHealth(999999999)
        self:SetBloodColor(BLOOD_COLOR_RED)
        self:SetHullType( HULL_HUMAN )
        self:SetHullSizeNormal()
        self:PhysicsInitBox(Vector(-24, -24, 0), Vector(24, 24, 72))
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then
            phys:EnableMotion(false) -- so it doesn't move
            phys:Wake()
        end
    end
end

-- Handle animation events (weapon hiding, footsteps)
function ENT:HandleAnimEvent(event, eventTime, cycle, type, options)
    local name = util.GetAnimEventNameByID(event)

    -- Weapon hide/unhide
    if name == "AE_WPN_HIDE" then
        if IsValid(self.weaponEnt) then
            self.weaponEnt:SetNoDraw(true)
        end
    elseif name == "AE_WPN_UNHIDE" then
        if IsValid(self.weaponEnt) then
            self.weaponEnt:SetNoDraw(false)
        end
    end
end

-- Handle animation events (weapon hiding, footsteps)
function ENT:FireAnimationEvent(pos, ang, event, name)
    -- Footstep events (7001 / 7002)
    if event == 7001 or event == 7002 then
        local tr = util.TraceLine({
            start = self:GetPos() + Vector(0, 0, 72),
            endpos = self:GetPos() - Vector(0, 0, 4) * 8,
            mask = MASK_PLAYERSOLID_BRUSHONLY,
            collisiongroup = COLLISION_GROUP_PLAYER_MOVEMENT
        })

        -- Special case for Headless Horseman model
        if self:GetModel() == "models/bots/headless_hatman.mdl" then
            self:EmitSound("Halloween.HeadlessBossFootfalls")
            return
        end

        -- Determine footstep sound by material
        local step = table.Random({ "Left", "Right" })
        local soundPrefix

        if tr.SurfaceProps == util.GetSurfaceIndex("gravel") then
            soundPrefix = "Gravel"
        else
            local mat = tr.MatType
            if mat == MAT_CONCRETE then soundPrefix = "Concrete"
            elseif mat == MAT_DEFAULT then soundPrefix = "Default"
            elseif mat == MAT_GRASS then soundPrefix = "Grass"
            elseif mat == MAT_DIRT then soundPrefix = "Dirt"
            elseif mat == MAT_METAL then soundPrefix = "SolidMetal"
            elseif mat == MAT_SNOW then soundPrefix = "Snow"
            elseif mat == MAT_PLASTIC then soundPrefix = "Plastic"
            elseif mat == MAT_FLESH or mat == MAT_BLOODYFLESH then soundPrefix = "Flesh"
            elseif mat == MAT_SAND then soundPrefix = "Sand"
            elseif mat == MAT_SLOSH then soundPrefix = "Mud"
            elseif mat == MAT_TILE then soundPrefix = "Tile"
            elseif mat == MAT_COMPUTER or mat == MAT_VENT then soundPrefix = "MetalVself"
            elseif mat == MAT_FOLIAGE then soundPrefix = "Grass"
            elseif mat == MAT_WOOD then soundPrefix = "Wood"
            elseif mat == MAT_GRATE then soundPrefix = "MetalGrate"
            else
                soundPrefix = "Default"
            end
        end

        self:EmitSound(soundPrefix .. ".Step" .. step)
    end
end

-- Make sure animation frames advance properly
function ENT:Think()
    self:NextThink(CurTime())
    if (self.SceneThink) then
        self:SceneThink()
    end
    return true
end

function ENT:UpdateAnimationRate(rate)
    self.GesturePlaybackRate = rate or 1.0
    self:SetPlaybackRate(self.GesturePlaybackRate)
end
