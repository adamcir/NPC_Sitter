TOOL.Category = "NPC"
TOOL.Name = "#tool.npc_sitter.name"
TOOL.Command = nil
TOOL.ConfigName = ""

TOOL.ClientConVar = {
    offset_x = "0", offset_y = "0", offset_z = "0",
    rot_p = "0", rot_y = "0", rot_r = "0",
    pose = "natural", pose_cycle = "-1", sequence = "",
    seat_mode = "auto"
}

-- Prefer real seated-in-chair animations over rollercoaster/ground/couch
-- poses, which either crouch or pull the legs up on several custom models.
-- Keep the existing presets and XYZ/rotation/frame controls unchanged.
local CHAIR_IDLE = {
    "Sit_Chair", "sit_chair_idle", "sit_chair",
    "Sit_Chair02", "Sit_Chair03", "sit_idle", "sitting",
    "sitchairtable1"
}
local BACKUP_SIT = {
    "sitcouchknees1", "sitcouch1", "sitcouchfeet1",
    "sitccouchtv1", "sit", "sit_rollercoaster"
}
local VALVE_POSES = {
    natural = CHAIR_IDLE,
    upright = {"Sit_Chair", "Sit_Chair02", "Sit_Chair03",
        "sit_chair_idle", "sit_chair", "sit_idle", "sitting"},
    relaxed = {"sitcouchknees1", "sitcouch1", "Sit_Chair",
        "sit_chair_idle", "sitcouchfeet1", "sit_chair"},
    forward = {"sitchairtable1", "Sit_Chair",
        "Sit_Chair02", "sit_chair", "sit_idle"},
    ride = {"sit_rollercoaster", "sit", "Sit_Chair",
        "sit_chair", "sit_chair_idle"},
    chair = {"Sit_Chair", "sit_chair", "sit_chair_idle",
        "Sit_Chair02", "sit_idle"}
}

local function IsSeat(ent)
    if not IsValid(ent) then return false end
    if ent:IsVehicle() then return true end
    local class = ent:GetClass() or ""
    return class == "prop_vehicle_prisoner_pod"
        or string.StartWith(class, "prop_vehicle_")
end

local function DetectSeatMode(seat)
    if not IsValid(seat) then return "chair" end
    -- Prisoner pods are scripted driveable seats, frequently used as
    -- passenger seats. Never infer the mode from the NPC model.
    local class = seat:GetClass()
    if class == "prop_vehicle_prisoner_pod" then return "prisoner_pod" end
    local model = string.lower(seat:GetModel() or "")
    if string.find(model, "prisoner_pod", 1, true)
        or string.find(model, "prisonerpod", 1, true) then
        return "prisoner_pod"
    end
    return "chair"
end

local function GetSeatMode(tool, seat)
    local selected = tool:GetClientInfo("seat_mode")
    if selected == "chair" or selected == "prisoner_pod" then
        return selected
    end
    return DetectSeatMode(seat)
end

local function IsReservedSeat(ent)
    return IsSeat(ent) and
        (ent.NPCSitterReserved == true or ent:GetNW2Bool("NPCSitter_Reserved", false))
end

local function GetToolOffset(tool)
    return Vector(tool:GetClientNumber("offset_x", 0),
                  tool:GetClientNumber("offset_y", 0),
                  tool:GetClientNumber("offset_z", 0))
end

local function GetToolRotation(tool)
    return Angle(tool:GetClientNumber("rot_p", 0),
                 tool:GetClientNumber("rot_y", 0),
                 tool:GetClientNumber("rot_r", 0))
end

local function GetToolPose(tool)
    local pose = tool:GetClientInfo("pose")
    if not VALVE_POSES[pose] and pose ~= "custom" then pose = "natural" end
    return pose, math.Clamp(tool:GetClientNumber("pose_cycle", -1), -1, 1),
        tool:GetClientInfo("sequence") or ""
end

local function FindNamedSequence(npc, desired)
    -- Sequence IDs start at zero; never check them using Lua truthiness
    -- semantics from other languages. 0 is a valid Lua number.
    for id, name in pairs(npc:GetSequenceList()) do
        if string.lower(name) == string.lower(desired) then
            return id, name
        end
    end
end

local function FindSitSequence(npc, pose, frame, customName, seatMode)
    if not IsValid(npc) then return nil, nil, nil, nil, "Invalid NPC." end
    local sequence, sequenceName

    if pose == "custom" then
        local name = string.Trim(customName or "")
        if not name:match("^[%w_]+$") then
            return nil, nil, nil, nil, "Enter a valid custom Source sequence name."
        end
        sequence, sequenceName = FindNamedSequence(npc, name)
        if sequence == nil then
            return nil, nil, nil, nil,
                "This NPC model does not have the sequence '" .. name .. "'."
        end
        local lowered = string.lower(sequenceName)
        if not (lowered:find("sit", 1, true)
            or lowered:find("chair", 1, true)
            or lowered:find("couch", 1, true)) then
            return nil, nil, nil, nil,
                "Custom animation must be a sitting/chair/couch sequence."
        end
    else
        local candidates = VALVE_POSES[pose] or CHAIR_IDLE
        if seatMode == "prisoner_pod" and pose == "natural" then
            -- In a pod, favor a standard chair animation, never the
            -- rollercoaster/couch feet-up animation by default.
            candidates = CHAIR_IDLE
        end
        for _, candidate in ipairs(candidates) do
            sequence, sequenceName = FindNamedSequence(npc, candidate)
            if sequence ~= nil then break end
        end
        if sequence == nil then
            -- Before declaring failure, try the native Source sitting
            -- activity. On Dr. Kleiner it resolves to Sit_Chair (#837).
            local act = rawget(_G, "ACT_BUSY_SIT_CHAIR")
            if act then
                local native = npc:SelectWeightedSequence(act)
                if native and native >= 0 then
                    local nativeName = npc:GetSequenceName(native)
                    if nativeName and nativeName:lower():find("sit", 1, true) then
                        sequence, sequenceName = native, nativeName
                    end
                end
            end
        end
        if sequence == nil then
            -- Last resort for models shipped only with couch/rollercoaster
            -- animations. Unlike the old addon, never pretend standing
            -- or T-pose to be a valid seated animation.
            for _, candidate in ipairs(BACKUP_SIT) do
                sequence, sequenceName = FindNamedSequence(npc, candidate)
                if sequence ~= nil then break end
            end
        end
    end

    if sequence == nil then
        return nil, nil, nil, nil,
            "Model " .. (npc:GetModel() or "(unknown)") ..
            " has no usable sitting sequence; NPC was left standing. " ..
            "Aim at it and run npc_sitter_list_anims."
    end

    -- A genuine Source sitting pose, frozen at a stable interior frame,
    -- prevents BOTH transitions to T-pose and the crouched mid-gesture
    -- appearance in the old sit_rollercoaster default.
    -- Player-controlled 'pose_cycle' always takes precedence.
    local defaultFrame = 0.30
    local nameLower = string.lower(sequenceName)
    if nameLower:find("rollercoaster", 1, true) then
        defaultFrame = 0.50
    elseif nameLower:find("sitcouch", 1, true) then
        defaultFrame = 0.40
    elseif nameLower == "sit_chair" then
        defaultFrame = 0.24
    end
    if seatMode == "prisoner_pod" and nameLower == "sit_chair" then
        defaultFrame = 0.32
    end
    local heldFrame = (frame and frame >= 0)
        and math.Clamp(frame, 0.02, 0.98) or defaultFrame

    local info = npc:GetSequenceInfo(sequence)
    local looping = info and info.flags
        and bit.band(info.flags, 1) ~= 0 or false
    return sequence, sequenceName, heldFrame, looping
end

if SERVER then
    NPC_SITTER = NPC_SITTER or {}

    -- CRITICAL: no Entity references or cyclic tables in Entity:GetTable().
    -- Sandbox SaveMap and duplicator recursively serialize that table.
    -- Storing npc.NPCSitterData = { seat = ent } and
    -- seat.NPCSitterNPC = npc caused "cyclic reference" and broken saves.
    -- Runtime relationships are weak-keyed and exist OUTSIDE both entities.
    local seated = setmetatable({}, {__mode = "k"})
    local occupants = setmetatable({}, {__mode = "k"})
    local reservations = setmetatable({}, {__mode = "k"})
    local pending = {}
    local nextToken = 0
    local MOD = "NPCSitterState"

    local function NewToken()
        nextToken = nextToken + 1
        return string.format("%s-%d-%d", game.GetMap(), math.floor(SysTime() * 1000), nextToken)
    end

    -- Public API for other add-ons. Do not store these tables on entities.
    function NPC_SITTER.GetData(npc) return seated[npc] end
    function NPC_SITTER.GetOccupant(seat) return occupants[seat] end
    function NPC_SITTER.IsReserved(seat)
        return IsValid(seat) and (reservations[seat] == true
            or seat:GetNW2Bool("NPCSitter_Reserved", false))
    end

    local function ClearLegacyFields(npc, seat)
        if IsValid(npc) then npc.NPCSitterData = nil end
        if IsValid(seat) then seat.NPCSitterNPC = nil end
    end

    local function GetStoredNumber(t, key, fallback)
        local n = t and tonumber(t[key]) or nil
        return n or fallback
    end

    local function EncodePose(npc, data)
        return {
            role = "npc",
            token = data.token,
            mode = data.seatMode,
            pose = data.pose,
            cycle = data.poseCycleRequested,
            sequence = data.customSequence,
            offset = {x = data.offset.x, y = data.offset.y, z = data.offset.z},
            angles = {p = data.localAngles.p, y = data.localAngles.y, r = data.localAngles.r}
        }
    end

    local function StoreBoth(npc, data)
        if not IsValid(npc) or not IsValid(data.seat) then return end
        local seat = data.seat
        local pair = EncodePose(npc, data)
        local seatRecord = table.Copy(pair)
        seatRecord.role = "seat"
        seatRecord.reserved = true
        -- Seat-only saves need enough data to recreate a missing NPC.
        -- Only JSON-safe primitives: never an actual Entity reference.
        seatRecord.npcClass = npc:GetClass()
        seatRecord.npcModel = npc:GetModel()
        seatRecord.npcHealth = npc:Health()

        duplicator.ClearEntityModifier(npc, MOD)
        duplicator.StoreEntityModifier(npc, MOD, pair)
        duplicator.ClearEntityModifier(seat, MOD)
        duplicator.StoreEntityModifier(seat, MOD, seatRecord)
    end

    local function StoreEmptyReservation(seat)
        if not IsValid(seat) then return end
        duplicator.ClearEntityModifier(seat, MOD)
        if NPC_SITTER.IsReserved(seat) then
            duplicator.StoreEntityModifier(seat, MOD, {
                role = "seat", reserved = true
            })
        end
    end

    local function SetReserved(seat, value)
        if not IsValid(seat) then return end
        reservations[seat] = value and true or nil
        seat:SetNW2Bool("NPCSitter_Reserved", value and true or false)
        -- Prevent native E use as well as vehicle entry, without replacing
        -- Use() or creating a permanently invisible player driver.
        seat:Fire(value and "Lock" or "Unlock", "", 0)
    end

    function NPC_SITTER.ReleaseSeatReservation(seat)
        if not NPC_SITTER.IsReserved(seat) or IsValid(occupants[seat]) then
            return false
        end
        SetReserved(seat, false)
        StoreEmptyReservation(seat)
        return true
    end

    hook.Add("CanPlayerEnterVehicle", "NPCSitter_ReserveVehicle", function(_, vehicle)
        if NPC_SITTER.IsReserved(vehicle) then return false end
    end)
    hook.Add("PlayerUse", "NPCSitter_BlockUse", function(_, ent)
        if NPC_SITTER.IsReserved(ent) then return false end
    end)

    local function ApplySitPose(npc, force)
        local data = seated[npc]
        if not IsValid(npc) or not data then return false end

        if npc:GetNPCState() ~= NPC_STATE_SCRIPT then
            npc:SetNPCState(NPC_STATE_SCRIPT)
        end
        if rawget(_G, "ACT_DO_NOT_DISTURB") and npc.SetIdealActivity then
            npc:SetIdealActivity(ACT_DO_NOT_DISTURB)
        end
        if force or npc:GetSequence() ~= data.sequence then
            npc:ResetSequence(data.sequence)
            npc:ResetSequenceInfo()
        end
        npc:SetPlaybackRate(0)
        if force or math.abs(npc:GetCycle() - data.poseCycle) > 0.005 then
            npc:SetCycle(data.poseCycle)
        end
        return true
    end

    local function RestoreNPC(npc, data, beside, stay)
        local seat = data.seat
        local worldPos, worldAngles = npc:GetPos(), npc:GetAngles()
        npc:SetParent(NULL)
        npc:SetPlaybackRate(1)
        npc:SetCycle(0)
        npc:SetMoveType(data.moveType or MOVETYPE_STEP)
        npc:SetCollisionGroup(data.collisionGroup or COLLISION_GROUP_NPC)
        if npc:IsNPC() then
            if npc.ClearSchedule then npc:ClearSchedule() end
            if data.npcState ~= nil then npc:SetNPCState(data.npcState) end
            if data.idealActivity and npc.SetIdealActivity then
                npc:SetIdealActivity(data.idealActivity)
            end
        end
        if stay then
            -- Keep the world location on death so ragdolls appear near the
            -- chair rather than back at the NPC's original spawn location.
            npc:SetPos(worldPos)
            npc:SetAngles(worldAngles)
        elseif beside and IsValid(seat) then
            npc:SetPos(seat:GetPos() + seat:GetRight() * 55 + Vector(0, 0, 12))
            npc:SetAngles(Angle(0, seat:GetAngles().y, 0))
            timer.Simple(0, function()
                if IsValid(npc) then npc:DropToFloor() end
            end)
        elseif data.pos then
            npc:SetPos(data.pos)
            if data.ang then npc:SetAngles(data.ang) end
        end
    end

    function NPC_SITTER.UnseatNPC(npc, beside, stay)
        if not IsValid(npc) then return false end
        local data = seated[npc]
        if not data then return false end
        seated[npc] = nil
        local seat = data.seat
        if IsValid(seat) and occupants[seat] == npc then
            occupants[seat] = nil
        end
        duplicator.ClearEntityModifier(npc, MOD)
        ClearLegacyFields(npc, seat)
        RestoreNPC(npc, data, beside, stay)
        if IsValid(seat) then StoreEmptyReservation(seat) end
        return true
    end

    function NPC_SITTER.UpdateTransform(npc, offset, rotation, pose, frame, custom, mode)
        local data = seated[npc]
        if not IsValid(npc) or not data then return false, "NPC not seated." end
        if not IsValid(data.seat) then return false, "Seat no longer exists." end

        local sequence, name, cycle, looping, err =
            FindSitSequence(npc, pose, frame, custom, mode)
        if sequence == nil then return false, err end

        data.offset = Vector(offset.x, offset.y, offset.z)
        data.localAngles = Angle(rotation.p, rotation.y, rotation.r)
        data.pose, data.sequence, data.sequenceName = pose, sequence, name
        data.poseCycle, data.looping = cycle, looping
        data.poseCycleRequested = frame
        data.customSequence = custom
        data.seatMode = mode
        if npc:GetParent() ~= data.seat then npc:SetParent(data.seat) end
        npc:SetLocalPos(data.offset)
        npc:SetLocalAngles(data.localAngles)
        ApplySitPose(npc, true)
        StoreBoth(npc, data)
        return true, string.format("%s: %s (frame %.2f)", mode, name, cycle)
    end

    function NPC_SITTER.SeatNPC(npc, seat, offset, rotation, pose, frame, custom, mode)
        if not IsValid(npc) or not npc:IsNPC() then return false, "Invalid NPC." end
        if not IsSeat(seat) then return false, "Target is not a vehicle seat." end
        if seat.GetDriver and IsValid(seat:GetDriver()) then
            return false, "A player is already in the seat."
        end
        if IsValid(occupants[seat]) and occupants[seat] ~= npc then
            return false, "This seat contains another NPC."
        end
        local sequence, name, cycle, looping, err =
            FindSitSequence(npc, pose, frame, custom, mode)
        if sequence == nil then return false, err end
        if seated[npc] then NPC_SITTER.UnseatNPC(npc, false) end

        local data = {
            token = NewToken(), seat = seat, seatMode = mode,
            pose = pose, sequence = sequence, sequenceName = name,
            looping = looping, poseCycle = cycle,
            poseCycleRequested = frame, customSequence = custom,
            moveType = npc:GetMoveType(), collisionGroup = npc:GetCollisionGroup(),
            npcState = npc:GetNPCState(), idealActivity = npc:GetIdealActivity(),
            pos = npc:GetPos(), ang = npc:GetAngles(),
            offset = Vector(offset.x, offset.y, offset.z),
            localAngles = Angle(rotation.p, rotation.y, rotation.r)
        }
        ClearLegacyFields(npc, seat)
        seated[npc], occupants[seat] = data, npc
        SetReserved(seat, true)

        npc:SetNPCState(NPC_STATE_SCRIPT)
        npc:SetSchedule(SCHED_WAIT_FOR_SCRIPT)
        npc:SetMoveType(MOVETYPE_NONE)
        npc:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)
        npc:SetParent(seat)
        npc:SetLocalPos(data.offset)
        npc:SetLocalAngles(data.localAngles)
        ApplySitPose(npc, true)
        StoreBoth(npc, data)
        return true, string.format("%s: %s (frame %.2f)", mode, name, cycle)
    end

    -- Duplication/Sandbox saves persist the seating *as data*, not as
    -- nested Entity pointers. Both NPC and seat get a serializable modifier.
    -- The pasted pair is relinked once both entities are created.
    local function RestorePair(npc, seat, info)
        if not IsValid(npc) or not IsValid(seat) or not npc:IsNPC()
            or not IsSeat(seat) then return false end
        if IsValid(occupants[seat]) then return false end
        local offsetInfo, angleInfo = info.offset or {}, info.angles or {}
        local mode = info.mode == "prisoner_pod" and "prisoner_pod" or "chair"
        local pose = VALVE_POSES[info.pose] and info.pose or
            (info.pose == "custom" and "custom" or "natural")
        local frame = math.Clamp(GetStoredNumber(info, "cycle", -1), -1, 1)
        local ok = NPC_SITTER.SeatNPC(
            npc, seat,
            Vector(GetStoredNumber(offsetInfo, "x", 0),
                   GetStoredNumber(offsetInfo, "y", 0),
                   GetStoredNumber(offsetInfo, "z", 0)),
            Angle(GetStoredNumber(angleInfo, "p", 0),
                  GetStoredNumber(angleInfo, "y", 0),
                  GetStoredNumber(angleInfo, "r", 0)),
            pose, frame, tostring(info.sequence or ""), mode
        )
        return ok == true
    end

    local function RestoreMissingNPC(seat, info)
        if not IsValid(seat) or not IsSeat(seat)
            or IsValid(occupants[seat]) then return end
        local class = info.npcClass
        if type(class) ~= "string" or not string.StartWith(class, "npc_") then
            return
        end
        local npc = ents.Create(class)
        if not IsValid(npc) then return end
        npc:SetPos(seat:GetPos())
        npc:SetAngles(seat:GetAngles())
        npc:Spawn()
        npc:Activate()
        if type(info.npcModel) == "string" and info.npcModel ~= ""
            and util.IsValidModel(info.npcModel) then
            npc:SetModel(info.npcModel)
        end
        if not RestorePair(npc, seat, info) then
            npc:Remove()
        else
            if type(info.npcHealth) == "number" and info.npcHealth > 0 then
                npc:SetHealth(info.npcHealth)
            end
        end
    end

    local function QueueRestore(ent, info)
        if type(info) ~= "table" then return end
        if info.role == "seat" and IsSeat(ent) then
            SetReserved(ent, info.reserved == true)
        end
        if not info.token or type(info.token) ~= "string" then return end
        local entry = pending[info.token] or {info = info}
        pending[info.token] = entry
        if info.role == "seat" and IsSeat(ent) then
            entry.seat = ent
            entry.info = info -- seat stores model/class fallback
        elseif info.role == "npc" and ent:IsNPC() then
            entry.npc = ent
        else
            return
        end
        if not entry.scheduled then
            entry.scheduled = true
            timer.Simple(1.0, function()
                if pending[info.token] ~= entry then return end
                pending[info.token] = nil
                if IsValid(entry.seat) and IsValid(entry.npc) then
                    RestorePair(entry.npc, entry.seat, entry.info)
                elseif IsValid(entry.seat) then
                    -- Some Sandbox saves duplicate the seat but omit a
                    -- parented NPC. Restore from the seat-side snapshot.
                    RestoreMissingNPC(entry.seat, entry.info)
                end
            end)
        end
    end

    duplicator.RegisterEntityModifier(MOD, function(_, ent, info)
        if IsValid(ent) then QueueRestore(ent, info) end
    end)

    -- Seated NPCs remain killable. Let the engine apply normal NPC damage.
    -- Before lethal damage, detach them so their death/ragdoll doesn't keep
    -- the vehicle parent. Do not modify damage, or override other addons.
    hook.Add("EntityTakeDamage", "NPCSitter_LethalDamage", function(npc, dmg)
        if not seated[npc] or not npc:IsNPC() then return end
        if dmg:GetDamage() > 0 and dmg:GetDamage() >= npc:Health() then
            NPC_SITTER.UnseatNPC(npc, false, true)
        end
    end)
    hook.Add("OnNPCKilled", "NPCSitter_NPCKilled", function(npc)
        if seated[npc] then NPC_SITTER.UnseatNPC(npc, false, true) end
    end)

    local nextCheck = 0
    hook.Add("Think", "NPCSitter_HoldSitPose", function()
        if CurTime() < nextCheck then return end
        nextCheck = CurTime() + 0.1
        for npc, data in pairs(seated) do
            if not IsValid(npc) then
                seated[npc] = nil
            elseif not IsValid(data.seat) then
                NPC_SITTER.UnseatNPC(npc, false, true)
            else
                if npc:GetParent() ~= data.seat then npc:SetParent(data.seat) end
                npc:SetLocalPos(data.offset)
                npc:SetLocalAngles(data.localAngles)
                ApplySitPose(npc, false)
            end
        end
    end)

    hook.Add("EntityRemoved", "NPCSitter_EntityRemoved", function(ent)
        if seated[ent] then
            local data = seated[ent]
            seated[ent] = nil
            if IsValid(data.seat) then
                occupants[data.seat] = nil
                StoreEmptyReservation(data.seat)
            end
        end
        if occupants[ent] then
            local npc = occupants[ent]
            occupants[ent] = nil
            if IsValid(npc) and seated[npc] then
                -- Source vehicle is already going away; remove the link.
                local data = seated[npc]
                seated[npc] = nil
                npc:SetParent(NULL)
                npc:SetMoveType(data.moveType or MOVETYPE_STEP)
                npc:SetCollisionGroup(data.collisionGroup or COLLISION_GROUP_NPC)
                duplicator.ClearEntityModifier(npc, MOD)
            end
        end
        reservations[ent] = nil
    end)
end

function TOOL:LeftClick(trace)
    if CLIENT then return true end
    local owner = self:GetOwner()
    if not IsValid(owner) then return false end
    local ent = trace.Entity
    if not IsValid(ent) then return false end

    local selected = self.SelectedNPC
    local seated
    if IsSeat(ent) and IsValid(NPC_SITTER.GetOccupant(ent)) then
        seated = NPC_SITTER.GetOccupant(ent)
    elseif ent:IsNPC() and NPC_SITTER.GetData(ent) then
        seated = ent
    end

    if not IsValid(selected) and IsValid(seated) then
        local pose, frame, customSequence = GetToolPose(self)
        local ok, err = NPC_SITTER.UpdateTransform(
            seated, GetToolOffset(self), GetToolRotation(self),
            pose, frame, customSequence,
            GetSeatMode(self, NPC_SITTER.GetData(seated).seat)
        )
        owner:ChatPrint(ok and ("[NPC Sitter] Pose updated: " .. (err or ""))
            or "[NPC Sitter] " .. (err or "Update failed."))
        return ok
    end

    if not IsValid(selected) then
        if not ent:IsNPC() then
            owner:ChatPrint("[NPC Sitter] First LMB an NPC, or LMB an occupied seat to update it.")
            return false
        end
        self.SelectedNPC = ent
        owner:SetNW2Entity("NPCSitter_SelectedNPC", ent)
        owner:ChatPrint("[NPC Sitter] NPC selected. Now LMB a vehicle seat.")
        return true
    end

    if ent:IsNPC() then
        self.SelectedNPC = ent
        owner:SetNW2Entity("NPCSitter_SelectedNPC", ent)
        owner:ChatPrint("[NPC Sitter] Selected NPC changed.")
        return true
    end
    if not IsSeat(ent) then
        owner:ChatPrint("[NPC Sitter] LMB a vehicle seat or Reload to cancel.")
        return false
    end
    local pose, frame, customSequence = GetToolPose(self)
    local ok, err = NPC_SITTER.SeatNPC(
        selected, ent, GetToolOffset(self), GetToolRotation(self),
        pose, frame, customSequence, GetSeatMode(self, ent)
    )
    if not ok then
        owner:ChatPrint("[NPC Sitter] " .. (err or "Could not seat NPC."))
        return false
    end
    self.SelectedNPC = nil
    owner:SetNW2Entity("NPCSitter_SelectedNPC", NULL)
    owner:ChatPrint("[NPC Sitter] NPC seated: " .. (err or "") .. ". LMB seat to update.")
    return true
end

function TOOL:RightClick(trace)
    if CLIENT then return true end
    local owner = self:GetOwner()
    local ent = trace.Entity
    if not IsValid(ent) then return false end
    local npc
    if ent:IsNPC() and NPC_SITTER.GetData(ent) then
        npc = ent
    elseif IsSeat(ent) and IsValid(NPC_SITTER.GetOccupant(ent)) then
        npc = NPC_SITTER.GetOccupant(ent)
    end
    if not IsValid(npc) then
        if IsValid(owner) then owner:ChatPrint("[NPC Sitter] Aim at seated NPC/seat.") end
        return false
    end
    if NPC_SITTER.UnseatNPC(npc, true) then
        if IsValid(owner) then
            owner:ChatPrint("[NPC Sitter] NPC released. Seat remains NPC-only.")
        end
        return true
    end
    return false
end

function TOOL:Reload(trace)
    if CLIENT then return true end
    local owner = self:GetOwner()
    self.SelectedNPC = nil
    if not IsValid(owner) then return false end
    owner:SetNW2Entity("NPCSitter_SelectedNPC", NULL)
    if NPC_SITTER.IsReserved(trace.Entity) and
        NPC_SITTER.ReleaseSeatReservation(trace.Entity) then
        owner:ChatPrint("[NPC Sitter] Empty seat unlocked for players.")
    else
        owner:ChatPrint("[NPC Sitter] Selection cleared.")
    end
    return true
end

if CLIENT then
    concommand.Add("npc_sitter_list_anims", function()
        local ply = LocalPlayer()
        if not IsValid(ply) then return end
        local npc = ply:GetEyeTrace().Entity
        if not IsValid(npc) or not npc:IsNPC() then
            print("[NPC Sitter] Aim at an NPC and retry npc_sitter_list_anims.")
            return
        end
        print("[NPC Sitter] Original Source animations: " .. npc:GetModel())
        local count = 0
        for id, name in pairs(npc:GetSequenceList()) do
            local key = string.lower(name)
            if key:find("sit", 1, true) or key:find("chair", 1, true)
                or key:find("couch", 1, true) then
                local info = npc:GetSequenceInfo(id)
                local looping = info and info.flags and
                    bit.band(info.flags, 1) ~= 0 or false
                print(string.format("  [%d] %s looping=%s",
                    id, name, tostring(looping)))
                count = count + 1
            end
        end
        local act = rawget(_G, "ACT_BUSY_SIT_CHAIR")
        if act then
            local seq = npc:SelectWeightedSequence(act)
            print("  ACT_BUSY_SIT_CHAIR = " ..
                (seq and seq >= 0 and npc:GetSequenceName(seq) or "(missing)"))
        end
        if count == 0 then print("  No sit/chair/couch sequences.") end
        print("  Use a matching name in the Custom sequence field.")
    end)

    language.Add("tool.npc_sitter.name", "NPC Sitter")
    language.Add("tool.npc_sitter.desc", "Seat NPCs using original Valve Source animations.")
    language.Add("tool.npc_sitter.0",
        "LMB NPC/seat: seat or update | RMB: release | Reload on empty seat: unlock")
    language.Add("tool.npc_sitter.left", "Select NPC / seat / choose Valve animation")
    language.Add("tool.npc_sitter.right", "Release NPC (keep seat reserved)")
    language.Add("tool.npc_sitter.reload", "Clear selection / unlock empty seat")
    TOOL.Information = {{name = "left"}, {name = "right"}, {name = "reload"}}
end

function TOOL.BuildCPanel(panel)
    panel:Help("Original Valve Source animations only. No bone manipulation or IK. LMB an NPC, then the chair; LMB again to update pose and offsets.")
    panel:AddControl("ComboBox", {
        MenuButton = 1,
        Folder = "npc_sitter",
        Options = {
            ["Default"] = {
                npc_sitter_offset_x = "0", npc_sitter_offset_y = "0",
                npc_sitter_offset_z = "0", npc_sitter_rot_p = "0",
                npc_sitter_rot_y = "0", npc_sitter_rot_r = "0"
            },
            ["Slightly higher"] = {
                npc_sitter_offset_x = "0", npc_sitter_offset_y = "0",
                npc_sitter_offset_z = "8", npc_sitter_rot_p = "0",
                npc_sitter_rot_y = "0", npc_sitter_rot_r = "0"
            }
        },
        CVars = {
            "npc_sitter_offset_x", "npc_sitter_offset_y", "npc_sitter_offset_z",
            "npc_sitter_rot_p", "npc_sitter_rot_y", "npc_sitter_rot_r"
        }
    })
    panel:Help("Seat type (the animation is held to prevent T-pose).")
    local seatMode = panel:ComboBox("Seat mode", "npc_sitter_seat_mode")
    seatMode:AddChoice("Automatic (detect prisoner pod)", "auto")
    seatMode:AddChoice("Regular chair", "chair")
    seatMode:AddChoice("Prisoner pod", "prisoner_pod")
    panel:Help("Prisoner pods use a seated Source animation rather than a standing/rollercoaster pose. Availability depends on the NPC model.")
    panel:Help("Presets select original Source sequences actually available in each NPC model.")
    local combo = panel:ComboBox("Valve sitting animation", "npc_sitter_pose")
    combo:AddChoice("Natural chair idle (recommended)", "natural")
    combo:AddChoice("Upright chair", "upright")
    combo:AddChoice("Relaxed couch", "relaxed")
    combo:AddChoice("Table / forward", "forward")
    combo:AddChoice("Vehicle sitting", "ride")
    combo:AddChoice("Legacy sit_chair (may gesture)", "chair")
    combo:AddChoice("Custom Source sequence", "custom")
    panel:TextEntry("Custom Source sequence name", "npc_sitter_sequence")
    panel:NumSlider("Sitting pose frame (-1 = automatic)", "npc_sitter_pose_cycle", -1, 1, 2)
    panel:Help("The original Source animation is held at a stable sitting frame to prevent T-pose, without rotating model bones. Avoids the crouched rollercoaster pose by preferring chair-idle. For uncommon models, adjust the pose frame. Use npc_sitter_list_anims to inspect available animations.")
    panel:NumSlider("X offset", "npc_sitter_offset_x", -100, 100, 1)
    panel:NumSlider("Y offset", "npc_sitter_offset_y", -100, 100, 1)
    panel:NumSlider("Z offset", "npc_sitter_offset_z", -100, 100, 1)
    panel:Help("Rotation offset")
    panel:NumSlider("Pitch", "npc_sitter_rot_p", -180, 180, 1)
    panel:NumSlider("Yaw", "npc_sitter_rot_y", -180, 180, 1)
    panel:NumSlider("Roll", "npc_sitter_rot_r", -180, 180, 1)
    panel:Help("RMB releases NPC; Reload on an empty NPC-only seat unlocks it.")
end
