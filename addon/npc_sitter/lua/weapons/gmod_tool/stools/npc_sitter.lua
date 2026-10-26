TOOL.Category = "NPC"
TOOL.Name = "#tool.npc_sitter.name"
TOOL.Command = nil
TOOL.ConfigName = ""

TOOL.ClientConVar = {
    offset_x = "0", offset_y = "0", offset_z = "0",
    rot_p = "0", rot_y = "0", rot_r = "0",
    pose = "natural", pose_cycle = "-1", sequence = "", lean = "0"
}

-- Many NPC models only offer ONE seated animation, so a sequence dropdown
-- alone cannot produce different poses. In addition to picking a supported
-- sequence, each preset now modifies the actual ValveBiped skeleton.
-- The angles below are additive to any pre-existing bone manipulation and
-- are fully restored when the NPC leaves the chair.
-- Most ValveBiped spines bend forward on positive local yaw.
local BONE_POSTURES = {
    natural = {
        Spine = Angle(0, -13, 0), Spine1 = Angle(0, -14, 0),
        Spine2 = Angle(0, -9, 0), Neck1 = Angle(0, 7, 0),
        Head1 = Angle(0, 4, 0),
        L_UpperArm = Angle(0, 0, -5), R_UpperArm = Angle(0, 0, 5)
    },
    upright = {
        Spine = Angle(0, -23, 0), Spine1 = Angle(0, -21, 0),
        Spine2 = Angle(0, -12, 0), Neck1 = Angle(0, 9, 0),
        Head1 = Angle(0, 5, 0),
        L_UpperArm = Angle(0, 0, -10), R_UpperArm = Angle(0, 0, 10)
    },
    relaxed = {
        Spine = Angle(0, -22, 0), Spine1 = Angle(0, -18, 0),
        Spine2 = Angle(0, -8, 0), Neck1 = Angle(0, -5, 0),
        Head1 = Angle(0, -8, 0),
        L_UpperArm = Angle(0, 0, -21), R_UpperArm = Angle(0, 0, 21),
        L_Forearm = Angle(0, -9, 0), R_Forearm = Angle(0, 9, 0)
    },
    forward = {
        Spine = Angle(0, 5, 0), Spine1 = Angle(0, 11, 0),
        Spine2 = Angle(0, 7, 0), Neck1 = Angle(0, -7, 0),
        Head1 = Angle(0, -5, 0),
        L_UpperArm = Angle(0, 0, -8), R_UpperArm = Angle(0, 0, 8)
    },
    ride = {
        Spine = Angle(0, -10, 0), Spine1 = Angle(0, -8, 0),
        Spine2 = Angle(0, -6, 0), Neck1 = Angle(0, 6, 0),
        L_UpperArm = Angle(-10, 0, -15),
        R_UpperArm = Angle(-10, 0, 15)
    },
    custom = {}
}
local SPINE_PARTS = {Spine = 0.3, Spine1 = 0.4, Spine2 = 0.3}

-- The sequence is still important: it bends the legs into a sitting pose.
-- Skeleton corrections only control the posture above that base animation.
-- A non-sitting animation would leave the NPC standing/T-posed.
local POSES = {
    natural = {cycle = 0.55, sequences = {"sit_chair_idle", "sit_chair", "sit_idle", "sitting", "sit"}},
    upright = {cycle = 0.30, sequences = {"sit_chair", "sit_chair_idle", "sit_idle", "sitting", "sit"}},
    relaxed = {cycle = 0.75, sequences = {"sit_chair_idle", "sit_idle", "sit_chair", "sitting", "sit"}},
    forward = {cycle = 0.15, sequences = {"sit_chair", "sit_chair_idle", "sit_idle", "sitting", "sit"}},
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
    return pose, math.Clamp(tool:GetClientNumber("pose_cycle", -1), -1, 1),
        tool:GetClientInfo("sequence") or "",
        math.Clamp(tool:GetClientNumber("lean", 0), -60, 60)
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

    function NPC_SITTER.UpdateTransform(npc, offset, rotation, pose, frame, customSequence, lean)
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
        data.sequence = sequence
        data.sequenceName = sequenceName
        data.poseCycle = cycle
        if npc:GetParent() ~= data.seat then npc:SetParent(data.seat) end
        npc:SetLocalPos(data.offset)
        npc:SetLocalAngles(data.localAngles)
        ApplySitPose(npc, true)
        local modified = ApplyPoseBones(npc, data)
        return true, string.format("%s (%s): %d bones adjusted", pose, sequenceName, modified)
    end

    local function RestoreNPC(npc, data, nextToSeat)
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

    function NPC_SITTER.SeatNPC(npc, seat, offset, rotation, pose, frame, customSequence, lean)
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
            pose = pose, lean = lean or 0,
            sequence = sequence, sequenceName = sequenceName,
            poseCycle = cycle
        }
        ReserveSeat(seat)
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
        return true, string.format("%s (%s): %d bones adjusted", pose, sequenceName, modified)
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
    panel:Help("Each pose now changes the NPC skeleton, even if the model only provides one sitting animation.")
    local combo = panel:ComboBox("Sitting pose", "npc_sitter_pose")
    combo:AddChoice("Natural chair (default)", "natural")
    combo:AddChoice("Upright", "upright")
    combo:AddChoice("Relaxed", "relaxed")
    combo:AddChoice("Leaning forward", "forward")
    combo:AddChoice("Rollercoaster / strapped", "ride")
    combo:AddChoice("Custom sequence", "custom")
    panel:NumSlider("Animation frame (-1 = preset)", "npc_sitter_pose_cycle", -1, 1, 2)
    panel:NumSlider("Extra posture / lean (back < 0 < forward)", "npc_sitter_lean", -60, 60, 0)
    panel:TextEntry("Custom model sequence", "npc_sitter_sequence")
    panel:Help("Natural and Upright straighten hunched NPCs. The Extra posture slider compensates for different models. Unsupported sitting animations are rejected.")
    panel:NumSlider("X offset", "npc_sitter_offset_x", -100, 100, 1)
    panel:NumSlider("Y offset", "npc_sitter_offset_y", -100, 100, 1)
    panel:NumSlider("Z offset", "npc_sitter_offset_z", -100, 100, 1)
    panel:Help("Rotation offset")
    panel:NumSlider("Pitch", "npc_sitter_rot_p", -180, 180, 1)
    panel:NumSlider("Yaw", "npc_sitter_rot_y", -180, 180, 1)
    panel:NumSlider("Roll", "npc_sitter_rot_r", -180, 180, 1)
    panel:Help("Used seats stay NPC-only even after NPC removal; aim and Reload to unlock.")
end
