-- crossplay_sync.lua
if not SERVER then return end

-- Table to store models keyed by SteamID or UserID
local PlayerModels = {}
local PlayerModelsCS = {}   
local PlayerModelsTERROR = {}

-- Networking configuration
local UPDATE_URL = "http://26.158.225.149:2634/update"
local CSTRIKE_UPDATE_URL = "http://26.158.225.149:2635/update_css"
local TERROR_UPDATE_URL = "http://26.158.225.149:2638/update"
local SOCKET_URL = "http://26.158.225.149:2634/update_gmod"
local PROPS_URL = "http://26.158.225.149:2634/update_props"
local CS_PROPS_URL = "http://26.158.225.149:2635/update_props"
local TERROR_PROPS_URL = "http://26.158.225.149:2638/update_props"

-- Constants
local INTERP_SPEED = 50
local MAX_SPEED = 300
local INTERP_DURATION = 0.1

-- Function to get weapon world model
local function GetWeaponWorldModel(ent)
    if IsValid(ent) then
        return ent:GetModel() or ""
    end
    return ""
end

-- Send player update
local function SendPlayerUpdate(ply)
    if not IsValid(ply) then return end

    local pos = ply:GetPos()
    local ang = ply:EyeAngles()
    local name = ply:Nick()
    local model = ply:GetModel() or ""
    local skin = ply:GetSkin() or 0
    local seq = ply:GetSequence() or 0
    local anim = tostring(seq)

    local weaponModel = ""
    local weapon = ply:GetActiveWeapon()
    if IsValid(weapon) then
        weaponModel = GetWeaponWorldModel(weapon)
    end

    local data = {
        event = "update",
        data = {
            name = name,
            x = pos.x, y = pos.y, z = pos.z,
            pitch = 0, yaw = ang.y, roll = ang.r,
            model = model, skin = skin,
            animation = anim,
            weapon_model = weaponModel
        }
    }

    HTTP{
        url = SOCKET_URL,
        method = "POST",
        headers = { ["Content-Type"] = "application/json" },
        body = util.TableToJSON(data)
    }
end

-- Timers
-- Timer: Broadcast all player updates in a single JSON
timer.Remove("BroadcastCSPlayerUpdates")
timer.Remove("BroadcastPlayerUpdates")
timer.Create("BroadcastPlayerUpdates", 0.1, 0, function()
    local payload = { event = "update_all", data = {} }

    for _, ply in ipairs(player.GetAll()) do
        if not IsValid(ply) then continue end 

        local pos = ply:GetPos()
        local ang = ply:EyeAngles()
        local model = ply:GetModel() or ""
        local skin = ply:GetSkin() or 0
        local seq = ply:GetSequence() or 0
        local weaponModel = ""
        local weapon = ply:GetActiveWeapon()
        -- Collect pose parameters
        local ent = ply
        local poseParams = {}
        for i = 0, ent:GetNumPoseParameters() - 1 do
            local name = ent:GetPoseParameterName(i)
            if name and name ~= "" then
                table.insert(poseParams, { name = name, value = ent:GetPoseParameter(i) })
            end
        end

        if IsValid(weapon) then
            weaponModel = weapon:GetModel() or ""
        end

        table.insert(payload.data, {
            name = ply:Nick(),
            x = pos.x, y = pos.y, z = pos.z,
            pitch = 0, yaw = ang.y, roll = ang.r,
            model = model,
            skin = skin,
            animation = tostring(seq),
            weapon_model = weaponModel,         
            sequence = ply:GetSequence()
        })
    end

    -- Send all updates in one POST
    HTTP{
        url = SOCKET_URL,
        method = "POST",
        headers = { ["Content-Type"] = "application/json" },
        body = util.TableToJSON(payload)
    }
end)

-- Timer: Broadcast all prop updates in a single JSON
timer.Remove("BroadcastPropUpdates")
timer.Create("BroadcastPropUpdates", 0.01, 0, function()
end)


-- Extract first "event sequence" from a VCD file
-- Reads a .vcd file and extracts sequence info
-- Returns: eventName, paramName (or nil if not found)
local function GetSequenceFromVCD(path)
    if not file.Exists(path, "GAME") then return nil end

    local contents = file.Read(path, "GAME")
    if not contents then return nil end

    -- Find each "event sequence" block
    for eventName, block in string.gmatch(contents, 'event%s+sequence%s+"([^"]+)"%s*{(.-)}') do
        -- Find the param line inside this block
        local param = string.match(block, 'param%s+"([^"]+)"')
        return param
    end

    
    local seq = string.match(contents, 'event%s+sequence%s+"([^"]+)"')
    return seq
end

-- --- MAIN LOOP ---
hook.Add("Think", "CrossplayThink", function()
    
    local payload = { event = "prop", data = {} }

    for _, ent in ipairs(ents.GetAll()) do
        if not IsValid(ent) then continue end

        local class = ent:GetClass() 
        if isstring(ent:GetModel()) and (ent:GetMoveType() == MOVETYPE_VPHYSICS and !isnumber(ent:GetModel()) and class ~= "crossplay_prop" and class ~= "func_physbox" || (ent:IsNPC() and class ~= "crossplay_prop" || ent:IsNextBot()  and class ~= "crossplay_prop" || string.find(class,"tf2_") || string.find(class,"npc_sentry") || string.find(ent:GetModel(),"flag") || string.find(ent:GetModel(),"charg")) || ent:GetClass() == "prop_dynamic" || ent:GetClass() == "prop_thumper") then   
            if ((string.find(class,"tf2_") || string.find(class,"npc_")) && ent:GetMaterial() == "Models/effects/vol_light001") then continue end
            local pos = ent:GetPos()
            local ang = ent:GetAngles()
            local model = ent:GetModel() or ""
            if model == "" then continue end

            local scale = ent:GetModelScale() or 1.0
            local skin = ent:GetSkin() or 0
            local name = "siob_"..ent:EntIndex()

            -- Collect pose parameters
            local poseParams = {}
            for i = 0, ent:GetNumPoseParameters() - 1 do
                local name = ent:GetPoseParameterName(i)
                if name and name ~= "" then
                    table.insert(poseParams, { name = name, value = ent:GetPoseParameter(i) })
                end
            end


            table.insert(payload.data, {    
                name = name,    
                id = name,    
                x = pos.x, y = pos.y, z = pos.z,
                pitch = ang.p, yaw = ang.y, roll = ang.r,
                model = model,
                skin = skin,
                scale = scale,
                sequence = ent:GetSequence(),
                cycle = ent:GetCycle(),
            })
        end
    end
--
    -- Send all prop updates in one POST
    HTTP{
        url = PROPS_URL,
        method = "POST",
        headers = { ["Content-Type"] = "application/json" },
        body = util.TableToJSON(payload)
    }
    
    HTTP{
        url = CS_PROPS_URL,
        method = "POST",
        headers = { ["Content-Type"] = "application/json" },
        body = util.TableToJSON(payload)
    }
    
    HTTP{
        url = TERROR_PROPS_URL_PROPS_URL,
        method = "POST",
        headers = { ["Content-Type"] = "application/json" },
        body = util.TableToJSON(payload)
    }
    --[[
    if not SERVER then return end

    http.Fetch(CSTRIKE_UPDATE_URL, function(body)
        local ok, data = pcall(util.JSONToTable, body)
        if not ok or not data or not data.players then return end

        local activePlayers = {}

        for _, playerData in ipairs(data.players) do
            local userid = playerData.userid or playerData.name
            activePlayers[userid] = true

            local targetModel = playerData.model or "models/props_c17/oildrum001.mdl"
            local targetPos = Vector(playerData.x, playerData.y, playerData.z)
            local targetAng = Angle(playerData.pitch, playerData.yaw, playerData.roll)
            local skin = playerData.skin or 0
            local scale = playerData.scale or 1
            local animation = tonumber(playerData.animation) or 0
            local weaponModel = playerData.weapon_model or ""
            local sceneName = playerData.scene or ""

            -- Create entity if missing
            if not PlayerModelsCS[userid] or not IsValid(PlayerModelsCS[userid].ent) then
                local ent = ents.Create("crossplay_prop")
                if not IsValid(ent) then return end

                ent:SetModel(targetModel)
                ent:SetPos(targetPos)
                ent:SetAngles(targetAng)
                ent:Spawn()
                ent:SetSkin(skin)
                ent:AddFlags(FL_OBJECT)

                -- Bonemerge weapon
                if weaponModel ~= "" then
                    local weaponEnt = ents.Create("base_anim")
                    if IsValid(weaponEnt) then
                        weaponEnt:SetModel(weaponModel)
                        weaponEnt:SetParent(ent)
                        weaponEnt:AddEffects(bit.bor(EF_BONEMERGE, EF_BONEMERGE_FASTCULL))
                        weaponEnt:Spawn()
                        ent.weaponEnt = weaponEnt
                    end
                end

                -- Scene + gesture handling
                function ent:SceneThink()
                    if sceneName ~= "" and self.sceneName ~= sceneName then
                        self:PlayScene(sceneName, 0)
                        self.sceneName = sceneName

                        local seqName = GetSequenceFromVCD(sceneName)
                        if seqName then
                            local seqId = self:LookupSequence(seqName)
                            if seqId and seqId > 0 then
                                local layer = self:AddGestureSequence(seqId, true)
                                if layer then
                                    self:SetLayerPlaybackRate(layer, 0.5)
                                    self:SetLayerWeight(layer, 1)
                                    self:SetLayerCycle(layer, 0)
                                    self:SetLayerLooping(layer, false)

                                    self.gestureLayer = layer
                                    self.gestureSeq = seqId
                                    self.gestureEndTime = CurTime() + self:SequenceDuration(seqId)
                                end
                            end
                        end
                    end

                    if self.gestureLayer and self.gestureEndTime and CurTime() >= self.gestureEndTime then
                        if IsValid(self.weaponEnt) then
                            self.weaponEnt:SetNoDraw(false)
                        end
                        if self.gestureSeq then
                            self:RemoveGesture(self.gestureSeq)
                        end
                        self.gestureLayer = nil
                        self.gestureSeq = nil
                        self.gestureEndTime = nil
                    end
                end

                PlayerModelsCS[userid] = {
                    ent = ent,
                    lastPos = targetPos,
                    targetPos = targetPos,
                    targetAng = targetAng,
                    lastUpdate = CurTime(),
                    move_x = 0,
                    move_y = 0
                }
            else
                local dataEntry = PlayerModelsCS[userid]
                local ent = dataEntry.ent

                -- Update weapon model if changed
                if ent.weaponEnt and ent.weaponEnt:GetModel() ~= weaponModel then
                    ent.weaponEnt:SetModel(weaponModel)
                end

                -- Update entity model if changed
                if ent:GetModel() ~= targetModel then
                    ent:SetModel(targetModel)
                end

                -- --- Buffered interpolation setup ---
                if not dataEntry.targetPos or dataEntry.targetPos ~= targetPos then
                    dataEntry.lastPos = dataEntry.targetPos or targetPos
                    dataEntry.targetPos = targetPos
                    dataEntry.targetAng = targetAng
                    dataEntry.lastUpdate = CurTime()
                end

                -- Compute interpolation factor
                local t = (CurTime() - (dataEntry.lastUpdate or CurTime())) / INTERP_DURATION
                local alpha = math.Clamp(t, 0, 1)

                -- Interpolate smoothly toward the last received target
                local newPos = LerpVector(alpha, dataEntry.lastPos, dataEntry.targetPos)
                local newAng = LerpAngle(alpha, ent:GetAngles(), dataEntry.targetAng)

                -- --- Movement & pose parameter computation (TF2-style) ---
                local velocity = (dataEntry.targetPos - dataEntry.lastPos) / math.max(INTERP_DURATION, 0.001)
                local speed = velocity:Length()
                local forward = ent:GetForward()
                local right = ent:GetRight()
                local vel2D = Vector(velocity.x, velocity.y, 0)

                local move_x, move_y = 0, 0
                if vel2D:LengthSqr() > 1 then
                    local dir = vel2D:GetNormalized()
                    move_x = math.Clamp(dir:Dot(forward), -1, 1)
                    move_y = math.Clamp(dir:Dot(right), -1, 1)

                    local walkSpeed = MAX_SPEED * 0.25
                    local runSpeed = MAX_SPEED
                    local t = math.Clamp((speed - walkSpeed) / (runSpeed - walkSpeed), 0, 1)
                    local speedScale = 1 - math.pow(0.5, t * 4.0)
                    move_x = move_x * speedScale
                    move_y = move_y * speedScale
                end

                dataEntry.move_x = Lerp(0.15, dataEntry.move_x or 0, move_x)
                dataEntry.move_y = Lerp(0.15, dataEntry.move_y or 0, move_y)

                ent:SetPos(newPos)
                ent:SetAngles(newAng)
                ent:SetSolid(SOLID_BBOX)
                ent:SetModelScale(scale)
                ent:SetSkin(skin)
                ent:SetPoseParameter("move_x", dataEntry.move_x)
                ent:SetPoseParameter("move_y", dataEntry.move_y)
                ent.move_speed = speed

                -- Animation update
                if ent:GetSequence() ~= animation then
                    ent:SetPlaybackRate(1)
                    ent:ResetSequence(animation)
                end
            end
        end

        -- Cleanup old entities
        for userid, dataEntry in pairs(PlayerModelsCS) do
            if not activePlayers[userid] and IsValid(dataEntry.ent) then
                if IsValid(dataEntry.ent.weaponEnt) then
                    dataEntry.ent.weaponEnt:Remove()
                end
                dataEntry.ent:Remove()
                PlayerModelsCS[userid] = nil
            end
        end
    end)
    
    http.Fetch(TERROR_UPDATE_URL, function(body)
        local ok, data = pcall(util.JSONToTable, body)
        if not ok or not data or not data.players then return end

        local activePlayers = {}

        for _, playerData in ipairs(data.players) do
            local userid = playerData.userid or playerData.name
            activePlayers[userid] = true

            local targetModel = playerData.model or "models/props_c17/oildrum001.mdl"
            local targetPos = Vector(playerData.x, playerData.y, playerData.z)
            local targetAng = Angle(playerData.pitch, playerData.yaw, playerData.roll)
            local skin = playerData.skin or 0
            local scale = playerData.scale or 1
            local animation = tonumber(playerData.animation) or 0
            local weaponModel = playerData.weapon_model or ""
            local sceneName = playerData.scene or ""

            -- Create entity if missing
            if not PlayerModelsTERROR[userid] or not IsValid(PlayerModelsTERROR[userid].ent) then
                local ent = ents.Create("crossplay_prop")
                if not IsValid(ent) then return end

                ent:SetModel(targetModel)
                ent:SetPos(targetPos)
                ent:SetAngles(targetAng)
                ent:Spawn()
                ent:SetSkin(skin)
                ent:AddFlags(FL_OBJECT)

                -- Bonemerge weapon
                if weaponModel ~= "" then
                    local weaponEnt = ents.Create("base_anim")
                    if IsValid(weaponEnt) then
                        weaponEnt:SetModel(weaponModel)
                        weaponEnt:SetParent(ent)
                        weaponEnt:AddEffects(bit.bor(EF_BONEMERGE, EF_BONEMERGE_FASTCULL))
                        weaponEnt:Spawn()
                        ent.weaponEnt = weaponEnt
                    end
                end

                PlayerModelsTERROR[userid] = {
                    ent = ent,
                    lastPos = targetPos,
                    targetPos = targetPos,
                    targetAng = targetAng,
                    lastUpdate = CurTime(),
                    move_x = 0,
                    move_y = 0
                }
            else
                local dataEntry = PlayerModelsTERROR[userid]
                local ent = dataEntry.ent

                -- Update weapon model if changed
                if ent.weaponEnt and ent.weaponEnt:GetModel() ~= weaponModel then
                    ent.weaponEnt:SetModel(weaponModel)
                end

                -- Update entity model if changed
                if ent:GetModel() ~= targetModel then
                    ent:SetModel(targetModel)
                end

                -- --- Buffered interpolation setup ---
                if not dataEntry.targetPos or dataEntry.targetPos ~= targetPos then
                    dataEntry.lastPos = dataEntry.targetPos or targetPos
                    dataEntry.targetPos = targetPos
                    dataEntry.targetAng = targetAng
                    dataEntry.lastUpdate = CurTime()
                end

                -- Compute interpolation factor
                local t = (CurTime() - (dataEntry.lastUpdate or CurTime())) / INTERP_DURATION
                local alpha = math.Clamp(t, 0, 1)

                -- Interpolate smoothly toward the last received target
                local newPos = LerpVector(alpha, dataEntry.lastPos, dataEntry.targetPos)
                local newAng = LerpAngle(alpha, ent:GetAngles(), dataEntry.targetAng)

                -- --- Movement & pose parameter computation (TF2-style) ---
                local velocity = (dataEntry.targetPos - dataEntry.lastPos) / math.max(INTERP_DURATION, 0.001)
                local speed = velocity:Length()
                local forward = ent:GetForward()
                local right = ent:GetRight()
                local vel2D = Vector(velocity.x, velocity.y, 0)

                local move_x, move_y = 0, 0
                if vel2D:LengthSqr() > 1 then
                    local dir = vel2D:GetNormalized()
                    move_x = math.Clamp(dir:Dot(forward), -1, 1)
                    move_y = math.Clamp(dir:Dot(right), -1, 1)

                    local walkSpeed = MAX_SPEED * 0.25
                    local runSpeed = MAX_SPEED
                    local t = math.Clamp((speed - walkSpeed) / (runSpeed - walkSpeed), 0, 1)
                    local speedScale = 1 - math.pow(0.5, t * 4.0)
                    move_x = move_x * speedScale
                    move_y = move_y * speedScale
                end

                dataEntry.move_x = Lerp(0.15, dataEntry.move_x or 0, move_x)
                dataEntry.move_y = Lerp(0.15, dataEntry.move_y or 0, move_y)

                ent:SetPos(newPos)
                ent:SetAngles(newAng)
                ent:SetSolid(SOLID_BBOX)
                ent:SetModelScale(scale)
                ent:SetSkin(skin)
                ent:SetPoseParameter("move_x", dataEntry.move_x)
                ent:SetPoseParameter("move_y", dataEntry.move_y)
                ent.move_speed = speed

                -- Animation update
                if ent:GetSequence() ~= animation then
                    ent:SetPlaybackRate(1)
                    ent:ResetSequence(animation)
                end

                -- Scene + gesture handling
                function ent:SceneThink()
                    if sceneName ~= "" and self.sceneName ~= sceneName then
                        self:PlayScene(sceneName, 0)
                        self.sceneName = sceneName

                        local seqName = GetSequenceFromVCD(sceneName)
                        if seqName then
                            local seqId = self:LookupSequence(seqName)
                            if seqId and seqId > 0 then
                                local layer = self:AddGestureSequence(seqId, true)
                                if layer then
                                    self:SetLayerPlaybackRate(layer, 0.5)
                                    self:SetLayerWeight(layer, 1)
                                    self:SetLayerCycle(layer, 0)
                                    self:SetLayerLooping(layer, false)

                                    self.gestureLayer = layer
                                    self.gestureSeq = seqId
                                    self.gestureEndTime = CurTime() + self:SequenceDuration(seqId)
                                end
                            end
                        end
                    end

                    if self.gestureLayer and self.gestureEndTime and CurTime() >= self.gestureEndTime then
                        if IsValid(self.weaponEnt) then
                            self.weaponEnt:SetNoDraw(false)
                        end
                        if self.gestureSeq then
                            self:RemoveGesture(self.gestureSeq)
                        end
                        self.gestureLayer = nil
                        self.gestureSeq = nil
                        self.gestureEndTime = nil
                    end
                end
            end
        end

        -- Cleanup old entities
        for userid, dataEntry in pairs(PlayerModelsTERROR) do
            if not activePlayers[userid] and IsValid(dataEntry.ent) then
                if IsValid(dataEntry.ent.weaponEnt) then
                    dataEntry.ent.weaponEnt:Remove()
                end
                dataEntry.ent:Remove()
                PlayerModelsTERROR[userid] = nil
            end
        end
    end)
    
    http.Fetch(UPDATE_URL, function(body)
        local ok, data = pcall(util.JSONToTable, body)
        if not ok or not data or not data.players then return end

        local activePlayers = {}

        for _, playerData in ipairs(data.players) do
            local userid = playerData.userid or playerData.name
            activePlayers[userid] = true

            local targetModel = playerData.model or "models/props_c17/oildrum001.mdl"
            local targetPos = Vector(playerData.x, playerData.y, playerData.z)
            local targetAng = Angle(playerData.pitch, playerData.yaw, playerData.roll)
            local skin = playerData.skin or 0
            local scale = playerData.scale or 1
            local animation = tonumber(playerData.animation) or 0
            local weaponModel = playerData.weapon_model or ""
            local sceneName = playerData.scene or ""

            -- Create entity if missing
            if not PlayerModels[userid] or not IsValid(PlayerModels[userid].ent) then
                local ent = ents.Create("crossplay_prop")
                if not IsValid(ent) then return end

                ent:SetModel(targetModel)
                ent:SetPos(targetPos)
                ent:SetAngles(targetAng)
                ent:Spawn()
                ent:SetSkin(skin)
                ent:AddFlags(FL_OBJECT)

                -- Bonemerge weapon
                if weaponModel ~= "" and !IsValid(ent.weaponEnt) then
                    local weaponEnt = ents.Create("base_anim")
                    if IsValid(weaponEnt) then
                        weaponEnt:SetModel(weaponModel)
                        weaponEnt:SetParent(ent)
                        weaponEnt:AddEffects(bit.bor(EF_BONEMERGE, EF_BONEMERGE_FASTCULL))
                        weaponEnt:Spawn()
                        ent.weaponEnt = weaponEnt
                    end
                end

                PlayerModels[userid] = {
                    ent = ent,
                    lastPos = targetPos,
                    targetPos = targetPos,
                    targetAng = targetAng,
                    lastUpdate = CurTime(),
                    move_x = 0,
                    move_y = 0
                }

                -- Scene + gesture handling
                function ent:SceneThink()
                    if sceneName ~= "" and self.sceneName ~= sceneName then
                        self:PlayScene(sceneName, 0)
                        self.sceneName = sceneName

                        local seqName = GetSequenceFromVCD(sceneName)
                        if seqName then
                            local seqId = self:LookupSequence(seqName)
                            if seqId and seqId > 0 then
                                local layer = self:AddGestureSequence(seqId, true)
                                if layer then
                                    self:SetLayerPlaybackRate(layer, 0.5)
                                    self:SetLayerWeight(layer, 1)
                                    self:SetLayerCycle(layer, 0)
                                    self:SetLayerLooping(layer, false)

                                    self.gestureLayer = layer
                                    self.gestureSeq = seqId
                                    self.gestureEndTime = CurTime() + self:SequenceDuration(seqId)
                                end
                            end
                        end
                    end

                    if self.gestureLayer and self.gestureEndTime and CurTime() >= self.gestureEndTime then
                        if IsValid(self.weaponEnt) then
                            self.weaponEnt:SetNoDraw(false)
                        end
                        if self.gestureSeq then
                            self:RemoveGesture(self.gestureSeq)
                        end
                        self.gestureLayer = nil
                        self.gestureSeq = nil
                        self.gestureEndTime = nil
                    end
                end
            else
                local dataEntry = PlayerModels[userid]
                local ent = dataEntry.ent

                -- Update weapon model if changed
                if ent.weaponEnt and ent.weaponEnt:GetModel() ~= weaponModel then
                    ent.weaponEnt:SetModel(weaponModel)
                end

                -- Update entity model if changed
                if ent:GetModel() ~= targetModel then
                    ent:SetModel(targetModel)
                end

                -- --- Buffered interpolation setup ---
                if not dataEntry.targetPos or dataEntry.targetPos ~= targetPos then
                    dataEntry.lastPos = dataEntry.targetPos or targetPos
                    dataEntry.targetPos = targetPos
                    dataEntry.targetAng = targetAng
                    dataEntry.lastUpdate = CurTime()
                end

                -- Compute interpolation factor
                local t = (CurTime() - (dataEntry.lastUpdate or CurTime())) / INTERP_DURATION
                local alpha = math.Clamp(t, 0, 1)

                -- Interpolate smoothly toward the last received target
                local newPos = LerpVector(alpha, dataEntry.lastPos, dataEntry.targetPos)
                local newAng = LerpAngle(alpha, ent:GetAngles(), dataEntry.targetAng)

                -- --- Movement & pose parameter computation (TF2-style) ---
                local velocity = (dataEntry.targetPos - dataEntry.lastPos) / math.max(INTERP_DURATION, 0.001)
                local speed = velocity:Length()
                local forward = ent:GetForward()
                local right = ent:GetRight()
                local vel2D = Vector(velocity.x, velocity.y, 0)

                local move_x, move_y = 0, 0
                if vel2D:LengthSqr() > 1 then
                    local dir = vel2D:GetNormalized()
                    move_x = math.Clamp(dir:Dot(forward), -1, 1)
                    move_y = math.Clamp(dir:Dot(right), -1, 1)

                    local walkSpeed = MAX_SPEED * 0.25
                    local runSpeed = MAX_SPEED
                    local t = math.Clamp((speed - walkSpeed) / (runSpeed - walkSpeed), 0, 1)
                    local speedScale = 1 - math.pow(0.5, t * 4.0)
                    move_x = move_x * speedScale
                    move_y = move_y * speedScale
                end

                dataEntry.move_x = Lerp(0.15, dataEntry.move_x or 0, move_x)
                dataEntry.move_y = Lerp(0.15, dataEntry.move_y or 0, move_y)

                ent:SetPos(newPos)
                ent:SetAngles(newAng)
                ent:SetSkin(skin)
                ent:SetPoseParameter("move_x", dataEntry.move_x)
                ent:SetPoseParameter("move_y", dataEntry.move_y)
                ent.move_speed = speed

                -- Animation update
                if ent:GetSequence() ~= animation then
                    ent:SetPlaybackRate(1)
                    ent:ResetSequence(animation)
                end
            end
        end

        -- Cleanup old entities
        for userid, dataEntry in pairs(PlayerModels) do
            if not activePlayers[userid] and IsValid(dataEntry.ent) then
                if IsValid(dataEntry.ent.weaponEnt) then
                    dataEntry.ent.weaponEnt:Remove()
                end
                dataEntry.ent:Remove()
                PlayerModels[userid] = nil
            end
        end
    end)
    ]]  
end)

timer.Stop("CrossPlayLoop")

-- === SOUND HOOK ===
hook.Add("EntityEmitSound", "CrossplaySoundCapture", function(data)
    local ent = data.Entity
    -- You can filter here: only send player, NPC, or crossplay_prop sounds
    local class = ent:GetClass()
    if (ent and string.find(class, "crossplay_prop")) then return end       
    if (string.find(data.SoundName,"loop")) then return end
    if (string.find(data.SoundName,"growl_high")) then return end
    if (string.find(data.SoundName,"growl_idle")) then return end
    if (string.find(data.SoundName,"confused1")) then return end
    if (string.find(data.SoundName,"rocket1")) then return end  
    if (string.find(data.SoundName,"pulsemachine")) then return end
    if (string.find(data.SoundName,"v8/")) then return end
    if (string.find(data.SoundName,"junker/")) then return end
    if (string.find(data.SoundName,"turret_floor/alarm")) then return end
    if (string.find(data.SoundName,"turret_floor/alert")) then return end
    if (string.find(data.SoundName,"antlion/fly")) then return end
    if (string.find(data.SoundName,"cpoint_klaxon")) then return end
    -- Prepare payload
    local soundData = {
        event = "sound",
        sound = {
            sound = data.SoundName or "",
            volume = 1.0,
            pitch = data.Pitch or 100,
            level = 95,  
            pos = ent:GetPos() or data.Pos,
            name = "worldspawn"
        }
    }

    -- Send to Node.js
    HTTP{
        url = "http://26.158.225.149:6000/sound",
        method = "POST",
        headers = { ["Content-Type"] = "application/json" },
        body = util.TableToJSON(soundData)
    }

    HTTP{
        url = "http://26.158.225.149:2463/sound",
        method = "POST",
        headers = { ["Content-Type"] = "application/json" },
        body = util.TableToJSON(soundData)
    }

    HTTP{
        url = "http://26.158.225.149:6001/sound",
        method = "POST",
        headers = { ["Content-Type"] = "application/json" },
        body = util.TableToJSON(soundData)
    }

    HTTP{
        url = "http://26.158.225.149:6002/sound",
        method = "POST",
        headers = { ["Content-Type"] = "application/json" },
        body = util.TableToJSON(soundData)
    }

    HTTP{
        url = "http://26.158.225.149:6003/sound",
        method = "POST",
        headers = { ["Content-Type"] = "application/json" },
        body = util.TableToJSON(soundData)
    }
    
    return nil
end)
if SERVER then
    local TRACE_URL = "http://26.158.225.149:7001/traceattacks"
    local TRACE_URL2 = "http://26.158.225.149:7000/traceattacks"    
    local TRACE_RADIUS = 100
    local lastFetched = 0
    local traceBuffer = {} 

    -- ---- GET loop: fetch traces from remote server and apply damage locally ----
    timer.Create("TraceAttackGETTimer", 0.2, 0, function()
        http.Fetch(TRACE_URL2,
            function(body, len, headers, code)
                if not body or body == "" then return end

                local ok, traces = pcall(util.JSONToTable, body)
                if not ok or type(traces) ~= "table" then
                    print("[TraceAttack GET] Failed to parse JSON from server.")
                    return
                end

                for _, trace in ipairs(traces) do
                    if trace and trace.hitpos then
                        -- parse hitpos as space-separated string: "x y z"
                        local parts = string.Explode(" ", trace.hitpos)
                        if #parts ~= 3 then continue end
                        local hitpos = Vector(tonumber(parts[1]) or 0,
                                            tonumber(parts[2]) or 0,
                                            tonumber(parts[3]) or 0)

                        local damage = tonumber(trace.damage) or 30

                        -- find nearby players/entities
                        local nearby = ents.FindInSphere(hitpos, TRACE_RADIUS)
                        for _, ent in ipairs(nearby) do
                            if IsValid(ent) then
                                -- keep c, c, c style for SP parity: use the entity itself
                                    local dmg = DamageInfo()
                                    dmg:SetDamage(damage)
                                    dmg:SetDamageType(DMG_BULLET)
                                    dmg:SetDamagePosition(hitpos)
                                    ent:TakeDamageInfo(dmg)
                            end
                        end
                    end
                end
            end,
            function(err)
                print("[TraceAttack GET] HTTP error:", err)
            end
        )
    end)

    -- ---- Hook: collect traces on EntityTakeDamage ----
    -- We'll collect: hitpos as table, damage, attacker entindex and attacker steam64, inflictor class
    hook.Add("EntityTakeDamage", "TraceAttack_CollectHook", function(target, dmginfo)
        if not dmginfo then return end
        local attacker = dmginfo:GetAttacker()

        if IsValid(attacker) and dmginfo:GetDamage() > 0 then
            local pos = dmginfo:GetDamagePosition()
            -- if DamagePosition is zero vector, fall back to target:GetPos()
            if not pos or (pos.x == 0 and pos.y == 0 and pos.z == 0) then
                pos = target:GetPos() or vector_origin
            end

            local hitpos_str = string.format("%.6f %.6f %.6f", pos.x, pos.y, pos.z)
            -- Prepare trace table with structured fields
            if (attacker:GetClass() == "npc_headcrab_black" or attacker:GetClass() == "npc_headcrab_poison") then
                dmginfo:SetDamage(500)
            end
            local trace = { 
                hitpos = hitpos_str,
                damage = dmginfo:GetDamage()
            }

            table.insert(traceBuffer, trace)
            -- We return false to allow other damage hooks to run and normal damage behavior.
            -- If you want to block original damage from happening locally, return true here.
            return false
        end
    end)

    -- ---- POST loop: flush traceBuffer to remote server periodically ----
    timer.Create("TraceAttackPOSTTimer", 0.2, 0, function()
        if #traceBuffer == 0 then return end

        -- make a shallow copy and clear buffer immediately to avoid losing traces added during the POST
        local toSend = table.Copy(traceBuffer)
        traceBuffer = {}

        -- Create the JSON payload
        local payload = util.TableToJSON(toSend, false) -- false = compact

        HTTP({
            url = TRACE_URL,
            method = "POST",
            timeout = POST_TIMEOUT,
            headers = {
                ["Content-Type"] = "application/json"
            },
            body = payload,
            success = function(code, body, headers)
                if code < 200 or code >= 300 then
                    print(string.format("[TraceAttack POST] Non-2xx HTTP code: %s", tostring(code)))
                    -- optionally re-buffer on failure
                    for _, t in ipairs(toSend) do table.insert(traceBuffer, t) end
                    print(body)
                end 
            end,
            failed = function(err)
                print("[TraceAttack POST] HTTP failed:", tostring(err))
                -- re-buffer so we don't lose data on temporary network failure
                for _, t in ipairs(toSend) do table.insert(traceBuffer, t) end
            end
        })
    end)
end

if SERVER then
    local CHAT_GET_URL = "http://26.158.225.149:7000/chat"

    -- Periodic fetch every 2 seconds
    timer.Create("FetchChatMessages", 1.8, 0, function()
        http.Fetch(CHAT_GET_URL,
            function(body, len, headers, code)
                -- Parse JSON
                local ok, messages = pcall(util.JSONToTable, body)
                if not ok or type(messages) ~= "table" then return end

                -- Loop through each message
                for _, msg in ipairs(messages) do
                    local name = msg.name or "Unknown"
                    local text = msg.text or ""

                    -- Example: send chat message to all players
                    for _, ply in ipairs(player.GetAll()) do
                        ply:ChatPrint("[Chat] " .. name .. ": " .. text)
                    end
                    print("[Chat] " .. name .. ": " .. text)
                end
            end,
            function(err)
                print("[Chat] HTTP GET failed: " .. err)
            end
        )
    end)
    hook.Add( "PlayerSay", "CrossplayChat", function( ply, text )

        HTTP{
            url = CHAT_GET_URL,
            method = "POST",    
            headers = { ["Content-Type"] = "application/json" },
            body = "{\"name\":\"[GMOD] "..ply:Nick().."\",\"text\":\""..text.."\"}"
        }
    end)
end
