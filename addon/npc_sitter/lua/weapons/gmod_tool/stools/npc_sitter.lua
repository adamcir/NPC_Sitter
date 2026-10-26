TOOL.Category = "NPC"
TOOL.Name = "#tool.npc_sitter.name"
TOOL.Command = nil
TOOL.ConfigName = ""

TOOL.ClientConVar = {
    offset_x = "0", offset_y = "0", offset_z = "0",
    rot_p = "0", rot_y = "0", rot_r = "0",
    pose = "natural", pose_cycle = "-1", sequence = "", lean = "0",
    hands = "lap"
}

-- Many NPC models only offer ONE seated animation, so a sequence dropdown
-- alone cannot produce different poses. In addition to picking a supported
-- sequence, each preset now modifies the actual ValveBiped skeleton.
-- The angles below are additive to any pre-existing bone manipulation and
-- are fully restored when the NPC leaves the chair.
-- Most ValveBiped spines bend forward on positive local yaw.
local BONE_POSTURES = {
    -- These only adjust torso and head. We position ARMS independently so
    -- straightening the back cannot raise both hands in front of the face.
    natural = {
        Spine = Angle(0, -13, 0), Spine1 = Angle(0, -12, 0),
        Spine2 = Angle(0, -7, 0), Neck1 = Angle(0, 7, 0),
        Head1 = Angle(0, 4, 0)
    },
    upright = {
        Spine = Angle(0, -22, 0), Spine1 = Angle(0, -17, 0),
        Spine2 = Angle(0, -10, 0), Neck1 = Angle(0, 9, 0),
        Head1 = Angle(0, 5, 0)
    },
    relaxed = {
        Spine = Angle(0, -14, 0), Spine1 = Angle(0, -11, 0),
        Spine2 = Angle(0, -7, 0), Neck1 = Angle(0, -5, 0),
        Head1 = Angle(0, -4, 0)
    },
    forward = {
        Spine = Angle(0, 5, 0), Spine1 = Angle(0, 11, 0),
        Spine2 = Angle(0, 7, 0), Neck1 = Angle(0, -7, 0),
        Head1 = Angle(0, -5, 0)
    },
    ride = {
        Spine = Angle(0, -10, 0), Spine1 = Angle(0, -8, 0),
        Spine2 = Angle(0, -6, 0), Neck1 = Angle(0, 6, 0)
    },
    custom = {}
}
local SPINE_PARTS = {Spine = 0.3, Spine1 = 0.4, Spine2 = 0.3}

-- The sequence is still important: it bends the legs into a sitting pose.
-- Skeleton corrections only control the posture above that base animation.
-- A non-sitting animation would leave the NPC standing/T-posed.
local POSES = {
    -- At later frames (e.g. sit_chair at 0.75) HL2 NPCs can raise both hands
    -- to eye height. 0.48 keeps the bent seated legs without that gesture.
    natural = {cycle = 0.48, sequences = {"sit_chair_idle", "sit_chair", "sit_idle", "sitting", "sit"}},
    upright = {cycle = 0.48, sequences = {"sit_chair", "sit_chair_idle", "sit_idle", "sitting", "sit"}},
    relaxed = {cycle = 0.48, sequences = {"sit_chair_idle", "sit_idle", "sit_chair", "sitting", "sit"}},
    forward = {cycle = 0.48, sequences = {"sit_chair", "sit_chair_idle", "sit_idle", "sitting", "sit"}},
    ride = {cycle = 0.50, sequences = {"sit_rollercoaster", "sit_chair", "sit_chair_idle", "sit_idle", "sit"}},
    custom = {cycle = 0.50, sequences = {}}
}

local function IsSeat(ent)
    if not IsValid(ent) then return false end
    if ent:IsVehicle() then return true end
    local class = ent:GetClass() or ""
    return class == "prop_vehicle_prisoner_pod"
        or string.StartWith(class, "prop_vehicle_")
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
    if not POSES[pose] then pose = "natural" end
    local hands = tool:GetClientInfo("hands")
    if hands ~= "lap" and hands ~= "sides" and hands ~= "animation" then hands = "lap" end
    return pose, math.Clamp(tool:GetClientNumber("pose_cycle", -1), -1, 1),
        tool:GetClientInfo("sequence") or "",
        math.Clamp(tool:GetClientNumber("lean", 0), -60, 60), hands
end

local function FindSitSequence(npc, pose, frame, customSequence)
    if not IsValid(npc) then return nil, nil, nil, "Invalid NPC." end
    local config = POSES[pose] or POSES.natural
    local cycle = (frame and frame >= 0) and math.Clamp(frame, 0, 1) or config.cycle

    if pose == "custom" then
        local name = string.Trim(customSequence or "")
        if name == "" or not string.match(name, "^[%w_]+$") then
            return nil, nil, nil, "Enter a valid custom sequence name."
        end
        local seq = npc:LookupSequence(name)
        if seq and seq >= 0 then return seq, name, cycle end
        return nil, nil, nil, "Sequence '" .. name .. "' is not available on this model."
    end

    for _, name in ipairs(config.sequences) do
        local seq = npc:LookupSequence(name)
        if seq and seq >= 0 then return seq, name, cycle end
    end

    local activity = rawget(_G, "ACT_BUSY_SIT_CHAIR")
    if activity then
        local seq = npc:SelectWeightedSequence(activity)
        if seq and seq >= 0 then return seq, "ACT_BUSY_SIT_CHAIR", cycle end
    end
    return nil, nil, nil,
        "No supported sitting animation for this NPC model (avoiding T-pose)."
end

if SERVER then
    NPC_SITTER = NPC_SITTER or {}
    NPC_SITTER.SeatedNPCs = NPC_SITTER.SeatedNPCs or {}

    local function ReserveSeat(seat)
        if not IsReservedSeat(seat) then
            seat.NPCSitterReserved = true
            seat:SetNW2Bool("NPCSitter_Reserved", true)
            seat:Fire("Lock", "", 0)
        end
    end

    function NPC_SITTER.ReleaseSeatReservation(seat)
        if not IsReservedSeat(seat) or IsValid(seat.NPCSitterNPC) then return false end
        seat.NPCSitterReserved = nil
        seat:SetNW2Bool("NPCSitter_Reserved", false)
        seat:Fire("Unlock", "", 0)
        return true
    end

    -- Keep previously NPC-used seats inaccessible to players, even if
    -- an NPC is deleted by cleanup/Undo. Reload on an empty seat unlocks it.
    hook.Add("CanPlayerEnterVehicle", "NPCSitter_ReserveVehicle", function(_, vehicle)
        if IsReservedSeat(vehicle) then return false end
    end)

    hook.Add("PlayerUse", "NPCSitter_BlockUse", function(_, ent)
        if IsReservedSeat(ent) then return false end
    end)

    -- Per-model bone indices; cache original bone angles once to avoid
    -- compounding transforms every time the preset changes.
    local function RestorePoseBones(npc, data)
        if not data or not data.originalBones then return end
        for boneId, original in pairs(data.originalBones) do
            if IsValid(npc) then npc:ManipulateBoneAngles(boneId, original) end
        end
        data.originalBones = nil
        data.poseBones = nil
    end

    local function ApplyPoseBones(npc, data)
        if not IsValid(npc) or not data then return 0 end
        data.originalBones = data.originalBones or {}
        local preset = BONE_POSTURES[data.pose] or BONE_POSTURES.natural
        local corrections = {}
        for name, delta in pairs(preset) do corrections[name] = delta end

        -- Extra control lets the player counter a model with an especially
        -- strong baked-in slouch without changing the chosen pose.
        local lean = data.lean or 0
        for name, weight in pairs(SPINE_PARTS) do
            local delta = corrections[name] or angle_zero
            corrections[name] = Angle(delta.p, delta.y + lean * weight, delta.r)
        end

        local changed = 0
        local touched = {}
        for shortName, correction in pairs(corrections) do
            local boneId = npc:LookupBone("ValveBiped.Bip01_" .. shortName)
            if boneId ~= nil then
                if not data.originalBones[boneId] then
                    local base = npc:GetManipulateBoneAngles(boneId)
                    data.originalBones[boneId] = Angle(base.p, base.y, base.r)
                end
                local original = data.originalBones[boneId]
                npc:ManipulateBoneAngles(boneId, Angle(
                    original.p + correction.p,
                    original.y + correction.y,
                    original.r + correction.r
                ))
                touched[boneId] = true
                changed = changed + 1
            end
        end

        -- Reset bones used by the *previous* preset but not by this one.
        for boneId, original in pairs(data.originalBones) do
            if not touched[boneId] then
                npc:ManipulateBoneAngles(boneId, original)
            end
        end
        data.poseBones = touched
        return changed
    end

    local function ApplySitPose(npc, force)
        if not IsValid(npc) then return false end
        local data = npc.NPCSitterData
        if not data or data.sequence == nil then return false end
        -- Never restart AI schedules every Think; keep a seated animation
        -- frozen on the chosen frame, even if the sequence is non-looping.
        if force or npc:GetSequence() ~= data.sequence then
            npc:ResetSequence(data.sequence)
            npc:ResetSequenceInfo()
        end
        npc:SetPlaybackRate(0)
        npc:SetCycle(data.poseCycle)
        return true
    end

    function NPC_SITTER.UpdateTransform(npc, offset, rotation, pose, frame, customSequence, lean, hands)
        if not IsValid(npc) or not npc.NPCSitterData then
            return false, "NPC is not seated."
        end
        local data = npc.NPCSitterData
        if not IsValid(data.seat) then return false, "Seat was removed." end

        local sequence, sequenceName, cycle, err =
            FindSitSequence(npc, pose, frame, customSequence)
        if not sequence then return false, err end

        data.offset = Vector(offset.x, offset.y, offset.z)
        data.localAngles = Angle(rotation.p, rotation.y, rotation.r)
        data.pose = pose
        data.lean = lean or 0
        data.hands = hands or "lap"
        -- The client calculates arm positions with actual up-to-date
        -- render bones (server bone matrices can be stale or invalid).
        npc:SetNW2String("NPCSitter_Hands", data.hands)
        npc:SetNW2Bool("NPCSitter_Seated", true)
        data.sequence = sequence
        data.sequenceName = sequenceName
        data.poseCycle = cycle
        if npc:GetParent() ~= data.seat then npc:SetParent(data.seat) end
        npc:SetLocalPos(data.offset)
        npc:SetLocalAngles(data.localAngles)
        ApplySitPose(npc, true)
        local modified = ApplyPoseBones(npc, data)
        return true, string.format("%s (%s): %d torso bones; arms adjusted clientside",
            pose, sequenceName, modified)
    end

    local function RestoreNPC(npc, data, nextToSeat)
        npc:SetNW2Bool("NPCSitter_Seated", false)
        npc:SetNW2String("NPCSitter_Hands", "animation")
        RestorePoseBones(npc, data)
        local seat = data.seat
        npc:SetParent(NULL)
        npc:SetPlaybackRate(1)
        npc:SetCycle(0)
        npc:SetMoveType(data.moveType or MOVETYPE_STEP)
        if data.collisionGroup ~= nil then
            npc:SetCollisionGroup(data.collisionGroup)
        else
            npc:SetCollisionGroup(COLLISION_GROUP_NPC)
        end
        if npc:IsNPC() then
            if npc.ClearSchedule then npc:ClearSchedule() end
            if data.npcState ~= nil then npc:SetNPCState(data.npcState) end
            if npc.SetForceCrouch then npc:SetForceCrouch(false) end
        end
        if nextToSeat and IsValid(seat) then
            local pos = seat:GetPos() + seat:GetRight() * 55 + Vector(0, 0, 12)
            local tr = util.TraceHull({
                start = pos + Vector(0, 0, 32),
                endpos = pos - Vector(0, 0, 64),
                mins = Vector(-16, -16, 0),
                maxs = Vector(16, 16, 72),
                filter = {npc, seat},
                mask = MASK_NPCSOLID
            })
            npc:SetPos(tr.Hit and tr.HitPos or pos)
            npc:SetAngles(Angle(0, seat:GetAngles().y, 0))
            timer.Simple(0, function()
                if IsValid(npc) then npc:DropToFloor() end
            end)
        elseif data.pos then
            npc:SetPos(data.pos)
            if data.ang then npc:SetAngles(data.ang) end
        end
    end

    function NPC_SITTER.UnseatNPC(npc, nextToSeat)
        if not IsValid(npc) then return false end
        local data = npc.NPCSitterData
        if not data then return false end
        NPC_SITTER.SeatedNPCs[npc] = nil
        if IsValid(data.seat) and data.seat.NPCSitterNPC == npc then
            data.seat.NPCSitterNPC = nil
        end
        npc.NPCSitterData = nil
        RestoreNPC(npc, data, nextToSeat)
        return true
    end

    function NPC_SITTER.SeatNPC(npc, seat, offset, rotation, pose, frame, customSequence, lean, hands)
        if not IsValid(npc) or not npc:IsNPC() then return false, "Invalid NPC." end
        if not IsSeat(seat) then return false, "Target is not a vehicle seat." end
        if seat.GetDriver and IsValid(seat:GetDriver()) then
            return false, "A player is already in this seat."
        end
        if IsValid(seat.NPCSitterNPC) and seat.NPCSitterNPC ~= npc then
            return false, "Seat already contains an NPC."
        end

        -- Validate animation first: don't parent NPCs that lack a seated pose.
        local sequence, sequenceName, cycle, err =
            FindSitSequence(npc, pose, frame, customSequence)
        if not sequence then return false, err end
        if npc.NPCSitterData then NPC_SITTER.UnseatNPC(npc, false) end

        npc.NPCSitterData = {
            seat = seat, moveType = npc:GetMoveType(),
            collisionGroup = npc:GetCollisionGroup(), npcState = npc:GetNPCState(),
            pos = npc:GetPos(), ang = npc:GetAngles(),
            offset = Vector(offset.x, offset.y, offset.z),
            localAngles = Angle(rotation.p, rotation.y, rotation.r),
            pose = pose, lean = lean or 0, hands = hands or "lap",
            sequence = sequence, sequenceName = sequenceName,
            poseCycle = cycle
        }
        ReserveSeat(seat)
        npc:SetNW2String("NPCSitter_Hands", npc.NPCSitterData.hands)
        npc:SetNW2Bool("NPCSitter_Seated", true)
        seat.NPCSitterNPC = npc
        NPC_SITTER.SeatedNPCs[npc] = true
        npc:SetNPCState(NPC_STATE_SCRIPT)
        npc:SetSchedule(SCHED_WAIT_FOR_SCRIPT)
        if npc.SetForceCrouch then npc:SetForceCrouch(false) end
        npc:SetMoveType(MOVETYPE_NONE)
        npc:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)
        npc:SetParent(seat)
        npc:SetLocalPos(npc.NPCSitterData.offset)
        npc:SetLocalAngles(npc.NPCSitterData.localAngles)
        ApplySitPose(npc, true)
        local modified = ApplyPoseBones(npc, npc.NPCSitterData)
        return true, string.format("%s (%s): %d torso bones; arms adjusted clientside",
            pose, sequenceName, modified)
    end

    local nextCheck = 0
    hook.Add("Think", "NPCSitter_HoldSitPose", function()
        if CurTime() < nextCheck then return end
        nextCheck = CurTime() + 0.1
        for npc in pairs(NPC_SITTER.SeatedNPCs) do
            if not IsValid(npc) or not npc.NPCSitterData then
                NPC_SITTER.SeatedNPCs[npc] = nil
            else
                local data = npc.NPCSitterData
                if not IsValid(data.seat) then
                    NPC_SITTER.UnseatNPC(npc, false)
                else
                    if npc:GetParent() ~= data.seat then npc:SetParent(data.seat) end
                    npc:SetLocalPos(data.offset)
                    npc:SetLocalAngles(data.localAngles)
                    ApplySitPose(npc, false)
                end
            end
        end
    end)

    hook.Add("EntityRemoved", "NPCSitter_EntityRemoved", function(ent)
        if ent.NPCSitterData then
            local seat = ent.NPCSitterData.seat
            NPC_SITTER.SeatedNPCs[ent] = nil
            if IsValid(seat) and seat.NPCSitterNPC == ent then
                seat.NPCSitterNPC = nil
            end
            ent.NPCSitterData = nil
        end
        if ent.NPCSitterNPC then
            local npc = ent.NPCSitterNPC
            ent.NPCSitterNPC = nil
            if IsValid(npc) and npc.NPCSitterData then
                NPC_SITTER.SeatedNPCs[npc] = nil
                local data = npc.NPCSitterData
                npc.NPCSitterData = nil
                timer.Simple(0, function()
                    if IsValid(npc) then RestoreNPC(npc, data, false) end
                end)
            end
        end
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
    if IsSeat(ent) and IsValid(ent.NPCSitterNPC) then
        seated = ent.NPCSitterNPC
    elseif ent:IsNPC() and ent.NPCSitterData then
        seated = ent
    end

    if not IsValid(selected) and IsValid(seated) then
        local ok, err = NPC_SITTER.UpdateTransform(
            seated, GetToolOffset(self), GetToolRotation(self), GetToolPose(self)
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
    local ok, err = NPC_SITTER.SeatNPC(
        selected, ent, GetToolOffset(self), GetToolRotation(self), GetToolPose(self)
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
    if ent:IsNPC() and ent.NPCSitterData then
        npc = ent
    elseif IsSeat(ent) and IsValid(ent.NPCSitterNPC) then
        npc = ent.NPCSitterNPC
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
    if IsReservedSeat(trace.Entity) and
        NPC_SITTER.ReleaseSeatReservation(trace.Entity) then
        owner:ChatPrint("[NPC Sitter] Empty seat unlocked for players.")
    else
        owner:ChatPrint("[NPC Sitter] Selection cleared.")
    end
    return true
end

if CLIENT then

    -- Client rendering bone matrices are authoritative for the visible model.
    -- Server GetBoneMatrix may be stale/invalid, which made our previous
    -- hand-to-lap solver stop at the chest. This 2-bone IK works during
    -- BuildBonePositions and does not mutate the server NPC skeleton.
    --
    -- Each upper arm and forearm rotates its entire descendant subtree,
    -- including hands/fingers, so there is no detached wrist or fist.
    local function RotateVectorAxis(v, axis, radians)
        local c, sn = math.cos(radians), math.sin(radians)
        return v * c + axis:Cross(v) * sn +
            axis * (axis:Dot(v) * (1 - c))
    end

    local function IsDescendant(ent, bone, root)
        local current = bone
        local safeguard = 0
        while current ~= nil and current >= 0 and safeguard < 80 do
            if current == root then return true end
            local parent = ent:GetBoneParent(current)
            if parent == nil or parent == current then break end
            current = parent
            safeguard = safeguard + 1
        end
        return false
    end

    local function RotateBoneSubtree(ent, count, root, pivot, axis, degrees)
        -- Cache descendants: repeated full-skeleton walks on every render
        -- would be expensive in populated maps with many seated NPCs.
        local cache = ent.NPCSitterArmChildCache
        if not cache or cache.count ~= count or cache.model ~= ent:GetModel() then
            cache = {count = count, model = ent:GetModel(), children = {}}
            ent.NPCSitterArmChildCache = cache
        end
        local bones = cache.children[root]
        if not bones then
            bones = {}
            for bone = 0, count - 1 do
                if IsDescendant(ent, bone, root) and
                    ent:GetBoneName(bone) ~= "__INVALIDBONE__" then
                    bones[#bones + 1] = bone
                end
            end
            cache.children[root] = bones
        end
        local radians = math.rad(degrees)
        for _, bone in ipairs(bones) do
            local matrix = ent:GetBoneMatrix(bone)
            if matrix then
                local pos = matrix:GetTranslation()
                local angles = matrix:GetAngles()
                angles:RotateAroundAxis(axis, degrees)
                matrix:SetTranslation(pivot + RotateVectorAxis(
                    pos - pivot, axis, radians
                ))
                matrix:SetAngles(angles)
                ent:SetBoneMatrix(bone, matrix)
            end
        end
    end

    local function AimSegment(ent, count, root, child, target)
        local parentM = ent:GetBoneMatrix(root)
        local childM = ent:GetBoneMatrix(child)
        if not parentM or not childM then return false end
        local pivot = parentM:GetTranslation()
        local current = childM:GetTranslation() - pivot
        local desired = target - pivot
        if current:LengthSqr() < 16 or desired:LengthSqr() < 16 then
            return false
        end

        local u = current:GetNormalized()
        local v = desired:GetNormalized()
        local dot = math.Clamp(u:Dot(v), -1, 1)
        if dot > 0.99999 then return true end

        local axis = u:Cross(v)
        if axis:LengthSqr() < 0.000001 then
            -- Antiparallel segments need a stable fallback axis.
            axis = u:Cross(ent:GetUp())
            if axis:LengthSqr() < 0.000001 then
                axis = u:Cross(ent:GetRight())
            end
        end
        axis:Normalize()
        RotateBoneSubtree(ent, count, root, pivot, axis, math.deg(math.acos(dot)))
        return true
    end

    local function GetMatrixPosition(ent, bone)
        if not bone then return nil end
        local m = ent:GetBoneMatrix(bone)
        return m and m:GetTranslation() or nil
    end

    local function SolveSeatedArm(ent, count, side, hands)
        local prefix = "ValveBiped.Bip01_" .. side .. "_"
        local upper = ent:LookupBone(prefix .. "UpperArm")
        local forearm = ent:LookupBone(prefix .. "Forearm")
        local hand = ent:LookupBone(prefix .. "Hand")
        local thigh = ent:LookupBone(prefix .. "Thigh")
        local calf = ent:LookupBone(prefix .. "Calf")
        if not (upper and forearm and hand and thigh and calf) then return end

        local shoulder = GetMatrixPosition(ent, upper)
        local elbow = GetMatrixPosition(ent, forearm)
        local wrist = GetMatrixPosition(ent, hand)
        local hip = GetMatrixPosition(ent, thigh)
        local knee = GetMatrixPosition(ent, calf)
        if not (shoulder and elbow and wrist and hip and knee) then return end

        local a = shoulder:Distance(elbow)
        local b = elbow:Distance(wrist)
        if a < 6 or a > 35 or b < 6 or b > 35 then return end

        local sideSign = side == "R" and 1 or -1
        local target
        if hands == "sides" then
            target = hip - ent:GetUp() * 13 +
                ent:GetRight() * (sideSign * 8)
        else
            -- Upper thigh, near the hip; palms stay below the chest.
            target = hip * 0.70 + knee * 0.30 + ent:GetUp() * 4
        end

        local toHand = target - shoulder
        local distance = toHand:Length()
        if distance < 1 then return end
        local direction = toHand / distance
        local minReach = math.abs(a - b) + 0.5
        local maxReach = a + b - 0.5
        if minReach >= maxReach then return end
        -- Clamp unreachable targets rather than pointing the elbows upward.
        local reach = math.Clamp(distance, minReach, maxReach)
        target = shoulder + direction * reach

        -- Analytical 2-bone IK: choose an elbow on the OUTSIDE of the
        -- torso, then put the hand on the thigh. Both segments retain their
        -- exact original lengths; no world-axis guessing is involved.
        local projected = (a * a - b * b + reach * reach) / (2 * reach)
        local height = math.sqrt(math.max(0, a * a - projected * projected))
        local outside = ent:GetRight() * sideSign - ent:GetForward() * 0.18
        local pole = outside - direction * outside:Dot(direction)
        if pole:LengthSqr() < 0.001 then return end
        pole:Normalize()
        local desiredElbow = shoulder + direction * projected + pole * height

        -- Keep all descendants aligned while rotating the 2 segments.
        if AimSegment(ent, count, upper, forearm, desiredElbow) then
            return AimSegment(ent, count, forearm, hand, target)
        end
        return false
    end

    local function BuildSeatedArmBones(npc, count)
        if not npc:GetNW2Bool("NPCSitter_Seated", false) then return end
        local hands = npc:GetNW2String("NPCSitter_Hands", "lap")
        if hands == "animation" then return end
        local left = SolveSeatedArm(npc, count, "L", hands)
        local right = SolveSeatedArm(npc, count, "R", hands)
        npc.NPCSitterArmLastBuild = SysTime()
        npc.NPCSitterArmStatus =
            (left and "L:OK" or "L:skip") .. ", " ..
            (right and "R:OK" or "R:skip")
    end

    concommand.Add("npc_sitter_debug_arms", function()
        local ply = LocalPlayer()
        if not IsValid(ply) then return end
        local npc = ply:GetEyeTrace().Entity
        if not IsValid(npc) or not npc:IsNPC() then
            print("[NPC Sitter] Aim at an NPC and retry npc_sitter_debug_arms")
            return
        end
        print(string.format(
            "[NPC Sitter] NPC=%s model=%s seated=%s hands=%s",
            npc:GetClass(), npc:GetModel(),
            tostring(npc:GetNW2Bool("NPCSitter_Seated", false)),
            npc:GetNW2String("NPCSitter_Hands", "(not set)")
        ))
        local age = npc.NPCSitterArmLastBuild and
            (SysTime() - npc.NPCSitterArmLastBuild) or -1
        print(string.format(
            "[NPC Sitter] Callback=%s last build age=%.2f s arms=%s",
            tostring(npc.NPCSitterHasArmRig or false), age,
            npc.NPCSitterArmStatus or "(not computed)"
        ))
        for _, name in ipairs({
            "L_UpperArm", "L_Forearm", "L_Hand",
            "R_UpperArm", "R_Forearm", "R_Hand"
        }) do
            print("  " .. name .. "=" .. tostring(
                npc:LookupBone("ValveBiped.Bip01_" .. name)
            ))
        end
    end)

    -- NPC entities are networked later than stool initialization. Register
    -- once per NPC when it becomes seated, including for joining clients.
    local nextArmScan = 0
    hook.Add("Think", "NPCSitter_ClientArmRig", function()
        if CurTime() < nextArmScan then return end
        nextArmScan = CurTime() + 0.7
        for _, npc in ipairs(ents.GetAll()) do
            if npc:IsNPC() and
                npc:GetNW2Bool("NPCSitter_Seated", false) and
                not npc.NPCSitterHasArmRig then
                npc:AddCallback("BuildBonePositions", BuildSeatedArmBones)
                npc.NPCSitterHasArmRig = true
            end
        end
    end)

    language.Add("tool.npc_sitter.name", "NPC Sitter")
    language.Add("tool.npc_sitter.desc", "Seat NPCs with poses and live offsets.")
    language.Add("tool.npc_sitter.0",
        "LMB NPC/seat: seat or update | RMB: release | Reload on empty seat: unlock")
    language.Add("tool.npc_sitter.left", "Select / seat / update seated NPC")
    language.Add("tool.npc_sitter.right", "Release NPC (keep seat reserved)")
    language.Add("tool.npc_sitter.reload", "Clear selection / unlock empty seat")
    TOOL.Information = {{name = "left"}, {name = "right"}, {name = "reload"}}
end

function TOOL.BuildCPanel(panel)
    panel:Help(
        "LMB NPC, then LMB a vehicle seat. Change the controls and LMB the seated NPC/seat to apply. " ..
        "RMB releases NPC; Reload on EMPTY reserved seat allows players to sit again."
    )
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
    panel:Help("Sitting presets also adjust body posture. By default arms are guided down to the lap instead of being raised into the air.")
    local combo = panel:ComboBox("Sitting pose", "npc_sitter_pose")
    combo:AddChoice("Natural chair (default)", "natural")
    combo:AddChoice("Upright", "upright")
    combo:AddChoice("Relaxed", "relaxed")
    combo:AddChoice("Leaning forward", "forward")
    combo:AddChoice("Rollercoaster / strapped", "ride")
    combo:AddChoice("Custom sequence", "custom")
    local hands = panel:ComboBox("Hands / arms", "npc_sitter_hands")
    hands:AddChoice("Hands resting on thighs (default)", "lap")
    hands:AddChoice("Arms hanging down", "sides")
    hands:AddChoice("Original animation (no arm correction)", "animation")
    panel:NumSlider("Animation frame (-1 = preset)", "npc_sitter_pose_cycle", -1, 1, 2)
    panel:NumSlider("Extra posture / lean (back < 0 < forward)", "npc_sitter_lean", -60, 60, 0)
    panel:TextEntry("Custom model sequence", "npc_sitter_sequence")
    panel:Help("Hands resting on thighs uses render-time 2-bone arm posing on ValveBiped NPCs. The Original animation setting disables it. Restart GMod after updating the addon.")
    panel:NumSlider("X offset", "npc_sitter_offset_x", -100, 100, 1)
    panel:NumSlider("Y offset", "npc_sitter_offset_y", -100, 100, 1)
    panel:NumSlider("Z offset", "npc_sitter_offset_z", -100, 100, 1)
    panel:Help("Rotation offset")
    panel:NumSlider("Pitch", "npc_sitter_rot_p", -180, 180, 1)
    panel:NumSlider("Yaw", "npc_sitter_rot_y", -180, 180, 1)
    panel:NumSlider("Roll", "npc_sitter_rot_r", -180, 180, 1)
    panel:Help("Used seats stay NPC-only even after NPC removal; aim and Reload to unlock.")
end
