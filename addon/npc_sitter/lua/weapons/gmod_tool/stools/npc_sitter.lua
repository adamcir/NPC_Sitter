TOOL.Category = "NPC"
TOOL.Name = "#tool.npc_sitter.name"
TOOL.Command = nil
TOOL.ConfigName = ""

TOOL.ClientConVar = {
    offset_x = "0",
    offset_y = "0",
    offset_z = "0",
    rot_p = "0",
    rot_y = "0",
    rot_r = "0"
}

local function IsSeat(ent)
    if not IsValid(ent) then return false end
    if ent:IsVehicle() then return true end

    local class = ent:GetClass() or ""
    return class == "prop_vehicle_prisoner_pod"
        or string.StartWith(class, "prop_vehicle_")
end

local function GetToolOffset(tool)
    return Vector(
        tool:GetClientNumber("offset_x", 0),
        tool:GetClientNumber("offset_y", 0),
        tool:GetClientNumber("offset_z", 0)
    )
end

local function GetToolRotation(tool)
    return Angle(
        tool:GetClientNumber("rot_p", 0),
        tool:GetClientNumber("rot_y", 0),
        tool:GetClientNumber("rot_r", 0)
    )
end

local function FindSitSequence(npc)
    if not IsValid(npc) then return -1, nil end

    local names = {
        "sit_rollercoaster",
        "sit_chair",
        "sit",
        "sit_idle",
        "sitting"
    }

    for _, name in ipairs(names) do
        local seq = npc:LookupSequence(name)
        if seq and seq >= 0 then
            return seq, name
        end
    end

    local act = rawget(_G, "ACT_BUSY_SIT_CHAIR")
    if act then
        local seq = npc:SelectWeightedSequence(act)
        if seq and seq >= 0 then
            return seq, "ACT_BUSY_SIT_CHAIR"
        end
    end

    return -1, nil
end

if SERVER then
    NPC_SITTER = NPC_SITTER or {}
    NPC_SITTER.SeatedNPCs = NPC_SITTER.SeatedNPCs or {}

    local function ApplySitPose(npc, force)
        if not IsValid(npc) then return false end

        local data = npc.NPCSitterData
        if not data then return false end

        if not data.sequence or data.sequence < 0 then
            local seq, seqName = FindSitSequence(npc)
            data.sequence = seq
            data.sequenceName = seqName
        end

        if not data.sequence or data.sequence < 0 then
            return false
        end

        npc:SetNPCState(NPC_STATE_SCRIPT)
        npc:SetSchedule(SCHED_WAIT_FOR_SCRIPT)

        if force or npc:GetSequence() ~= data.sequence then
            npc:ResetSequence(data.sequence)
            npc:ResetSequenceInfo()
        end

        -- Freeze on a stable seated frame so a non-looping sit sequence
        -- cannot finish and return the NPC to standing/T-pose.
        npc:SetPlaybackRate(0)
        npc:SetCycle(data.poseCycle or 0.5)

        return true
    end

    function NPC_SITTER.UpdateTransform(npc, offset, rotation)
        if not IsValid(npc) or not npc.NPCSitterData then
            return false
        end

        local data = npc.NPCSitterData
        if not IsValid(data.seat) then
            return false
        end

        data.offset = Vector(offset.x, offset.y, offset.z)
        data.localAngles = Angle(rotation.p, rotation.y, rotation.r)

        if npc:GetParent() ~= data.seat then
            npc:SetParent(data.seat)
        end

        npc:SetLocalPos(data.offset)
        npc:SetLocalAngles(data.localAngles or angle_zero)
        ApplySitPose(npc, true)

        return true
    end

    function NPC_SITTER.UnseatNPC(npc, placeNextToSeat)
        if not IsValid(npc) then return false end

        local data = npc.NPCSitterData
        if not data then return false end

        local seat = data.seat

        NPC_SITTER.SeatedNPCs[npc] = nil

        if IsValid(seat) and seat.NPCSitterNPC == npc then
            seat.NPCSitterNPC = nil
        end

        npc:SetParent(NULL)
        npc:SetPlaybackRate(1)

        npc:SetMoveType(data.moveType or MOVETYPE_STEP)

        if data.collisionGroup ~= nil then
            npc:SetCollisionGroup(data.collisionGroup)
        else
            npc:SetCollisionGroup(COLLISION_GROUP_NPC)
        end

        if npc:IsNPC() and data.npcState ~= nil then
            npc:SetNPCState(data.npcState)
        end

        if placeNextToSeat and IsValid(seat) then
            local targetPos = seat:GetPos() + seat:GetRight() * 55 + Vector(0, 0, 12)

            local tr = util.TraceHull({
                start = targetPos + Vector(0, 0, 32),
                endpos = targetPos - Vector(0, 0, 64),
                mins = Vector(-16, -16, 0),
                maxs = Vector(16, 16, 72),
                filter = {npc, seat},
                mask = MASK_NPCSOLID
            })

            npc:SetPos(tr.Hit and tr.HitPos or targetPos)
            npc:SetAngles(Angle(0, seat:GetAngles().y, 0))

            timer.Simple(0, function()
                if IsValid(npc) then
                    npc:DropToFloor()
                end
            end)
        elseif data.pos then
            npc:SetPos(data.pos)
            if data.ang then
                npc:SetAngles(data.ang)
            end
        end

        npc.NPCSitterData = nil
        return true
    end

    function NPC_SITTER.SeatNPC(npc, seat, offset, rotation)
        if not IsValid(npc) or not npc:IsNPC() then
            return false, "Invalid NPC."
        end

        if not IsSeat(seat) then
            return false, "Target is not a vehicle seat."
        end

        if IsValid(seat.NPCSitterNPC) and seat.NPCSitterNPC ~= npc then
            return false, "This seat is already occupied by another NPC."
        end

        if npc.NPCSitterData then
            NPC_SITTER.UnseatNPC(npc, false)
        end

        local seq, seqName = FindSitSequence(npc)

        npc.NPCSitterData = {
            seat = seat,
            moveType = npc:GetMoveType(),
            collisionGroup = npc:GetCollisionGroup(),
            npcState = npc:GetNPCState(),
            pos = npc:GetPos(),
            ang = npc:GetAngles(),
            offset = Vector(offset.x, offset.y, offset.z),
            localAngles = Angle(rotation.p, rotation.y, rotation.r),
            sequence = seq,
            sequenceName = seqName,
            poseCycle = 0.5
        }

        seat.NPCSitterNPC = npc
        NPC_SITTER.SeatedNPCs[npc] = true

        npc:SetNPCState(NPC_STATE_SCRIPT)
        npc:SetSchedule(SCHED_WAIT_FOR_SCRIPT)
        npc:SetMoveType(MOVETYPE_NONE)
        npc:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)

        npc:SetParent(seat)
        npc:SetLocalPos(npc.NPCSitterData.offset)
        npc:SetLocalAngles(npc.NPCSitterData.localAngles)

        ApplySitPose(npc, true)
        return true
    end

    local nextPoseCheck = 0
    hook.Add("Think", "NPCSitter_HoldSitPose", function()
        if CurTime() < nextPoseCheck then return end
        nextPoseCheck = CurTime() + 0.10

        for npc in pairs(NPC_SITTER.SeatedNPCs) do
            if not IsValid(npc) or not npc.NPCSitterData then
                NPC_SITTER.SeatedNPCs[npc] = nil
            else
                local data = npc.NPCSitterData
                local seat = data.seat

                if not IsValid(seat) then
                    NPC_SITTER.UnseatNPC(npc, false)
                else
                    if npc:GetParent() ~= seat then
                        npc:SetParent(seat)
                    end

                    npc:SetLocalPos(data.offset or vector_origin)
                    npc:SetLocalAngles(data.localAngles or angle_zero)
                    ApplySitPose(npc, false)
                end
            end
        end
    end)

    hook.Add("EntityRemoved", "NPCSitter_EntityRemoved", function(ent)
        if ent.NPCSitterNPC then
            local npc = ent.NPCSitterNPC

            if IsValid(npc) and npc.NPCSitterData then
                NPC_SITTER.SeatedNPCs[npc] = nil

                timer.Simple(0, function()
                    if not IsValid(npc) or not npc.NPCSitterData then return end

                    local data = npc.NPCSitterData
                    npc:SetParent(NULL)
                    npc:SetPlaybackRate(1)
                    npc:SetMoveType(data.moveType or MOVETYPE_STEP)

                    if data.collisionGroup ~= nil then
                        npc:SetCollisionGroup(data.collisionGroup)
                    end

                    if npc:IsNPC() and data.npcState ~= nil then
                        npc:SetNPCState(data.npcState)
                    end

                    npc.NPCSitterData = nil
                end)
            end
        end

        if ent.NPCSitterData then
            NPC_SITTER.SeatedNPCs[ent] = nil

            local data = ent.NPCSitterData
            if IsValid(data.seat) and data.seat.NPCSitterNPC == ent then
                data.seat.NPCSitterNPC = nil
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

    -- If the seat already contains an NPC and there is no pending selection,
    -- LMB applies the current offset sliders immediately.
    if not IsValid(selected) and IsSeat(ent) and IsValid(ent.NPCSitterNPC) then
        local npc = ent.NPCSitterNPC
        local offset = GetToolOffset(self)
        local rotation = GetToolRotation(self)

        if NPC_SITTER.UpdateTransform(npc, offset, rotation) then
            owner:ChatPrint(string.format(
                "[NPC Sitter] Transform updated: XYZ %.1f %.1f %.1f | PYR %.1f %.1f %.1f",
                offset.x, offset.y, offset.z, rotation.p, rotation.y, rotation.r
            ))
            return true
        end

        owner:ChatPrint("[NPC Sitter] Could not update this NPC.")
        return false
    end

    if not IsValid(selected) then
        if not ent:IsNPC() then
            owner:ChatPrint("[NPC Sitter] First click must be on an NPC, or click an occupied seat to update its offset.")
            return false
        end

        self.SelectedNPC = ent
        owner:SetNW2Entity("NPCSitter_SelectedNPC", ent)
        owner:ChatPrint("[NPC Sitter] NPC selected. Now click a vehicle seat.")
        return true
    end

    if ent:IsNPC() then
        self.SelectedNPC = ent
        owner:SetNW2Entity("NPCSitter_SelectedNPC", ent)
        owner:ChatPrint("[NPC Sitter] Selected NPC changed. Now click a vehicle seat.")
        return true
    end

    if not IsSeat(ent) then
        owner:ChatPrint("[NPC Sitter] Click a vehicle seat, or Reload (R) to cancel.")
        return false
    end

    local offset = GetToolOffset(self)
    local rotation = GetToolRotation(self)

    local ok, err = NPC_SITTER.SeatNPC(selected, ent, offset, rotation)
    if not ok then
        owner:ChatPrint("[NPC Sitter] " .. (err or "Could not seat NPC."))
        return false
    end

    self.SelectedNPC = nil
    owner:SetNW2Entity("NPCSitter_SelectedNPC", NULL)
    owner:ChatPrint("[NPC Sitter] NPC seated. Change position/rotation offsets and LMB the occupied seat to apply them.")
    return true
end

function TOOL:RightClick(trace)
    if CLIENT then return true end

    local owner = self:GetOwner()
    local ent = trace.Entity
    if not IsValid(ent) then return false end

    local npc = nil

    if ent:IsNPC() and ent.NPCSitterData then
        npc = ent
    elseif IsSeat(ent) and IsValid(ent.NPCSitterNPC) then
        npc = ent.NPCSitterNPC
    end

    if not IsValid(npc) then
        if IsValid(owner) then
            owner:ChatPrint("[NPC Sitter] Aim at a seated NPC or its seat.")
        end
        return false
    end

    if NPC_SITTER.UnseatNPC(npc, true) then
        if IsValid(owner) then
            owner:ChatPrint("[NPC Sitter] NPC released.")
        end
        return true
    end

    return false
end

function TOOL:Reload(trace)
    if CLIENT then return true end

    local owner = self:GetOwner()
    self.SelectedNPC = nil

    if IsValid(owner) then
        owner:SetNW2Entity("NPCSitter_SelectedNPC", NULL)
        owner:ChatPrint("[NPC Sitter] Selection cleared.")
    end

    return true
end

if CLIENT then
    language.Add("tool.npc_sitter.name", "NPC Sitter")
    language.Add("tool.npc_sitter.desc", "Seat NPCs on vehicle seats with an adjustable live offset.")
    language.Add("tool.npc_sitter.0", "LMB NPC: select | LMB seat: seat/update offset | RMB: release | Reload: clear")

    language.Add("tool.npc_sitter.left", "Select NPC / seat it / apply current offset")
    language.Add("tool.npc_sitter.right", "Release a seated NPC")
    language.Add("tool.npc_sitter.reload", "Clear selected NPC")

    TOOL.Information = {
        { name = "left" },
        { name = "right" },
        { name = "reload" }
    }
end

function TOOL.BuildCPanel(panel)
    panel:Help(
        "1) LMB an NPC.\n" ..
        "2) LMB a vehicle seat.\n" ..
        "3) Change X/Y/Z and Pitch/Yaw/Roll below.\n" ..
        "4) LMB the occupied seat to apply the new position and rotation immediately."
    )

    panel:AddControl("ComboBox", {
        MenuButton = 1,
        Folder = "npc_sitter",
        Options = {
            ["Default"] = {
                npc_sitter_offset_x = "0",
                npc_sitter_offset_y = "0",
                npc_sitter_offset_z = "0",
                npc_sitter_rot_p = "0",
                npc_sitter_rot_y = "0",
                npc_sitter_rot_r = "0"
            },
            ["Slightly higher"] = {
                npc_sitter_offset_x = "0",
                npc_sitter_offset_y = "0",
                npc_sitter_offset_z = "8",
                npc_sitter_rot_p = "0",
                npc_sitter_rot_y = "0",
                npc_sitter_rot_r = "0"
            }
        },
        CVars = {
            "npc_sitter_offset_x",
            "npc_sitter_offset_y",
            "npc_sitter_offset_z",
            "npc_sitter_rot_p",
            "npc_sitter_rot_y",
            "npc_sitter_rot_r"
        }
    })

    panel:NumSlider("X offset (forward/back)", "npc_sitter_offset_x", -100, 100, 1)
    panel:NumSlider("Y offset (left/right)", "npc_sitter_offset_y", -100, 100, 1)
    panel:NumSlider("Z offset (up/down)", "npc_sitter_offset_z", -100, 100, 1)

    panel:Help("Rotation offset")
    panel:NumSlider("Pitch", "npc_sitter_rot_p", -180, 180, 1)
    panel:NumSlider("Yaw", "npc_sitter_rot_y", -180, 180, 1)
    panel:NumSlider("Roll", "npc_sitter_rot_r", -180, 180, 1)

    panel:Help("After changing any slider, LMB the occupied seat to apply position and rotation immediately.")
end
