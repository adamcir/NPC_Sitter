TOOL.Category = "NPC"
TOOL.Name = "#tool.npc_sitter.name"
TOOL.Command = nil
TOOL.ConfigName = ""

TOOL.ClientConVar = {
    offset_x = "0", offset_y = "0", offset_z = "0",
    rot_p = "0", rot_y = "0", rot_r = "0",
    pose = "natural", pose_cycle = "-1", sequence = ""
}

-- Only play REAL Source animations compiled into each NPC model. Presets
-- choose among known Valve ActBusy chair/couch animations. They cannot
-- manufacture different poses when the model only contains one idle.
local VALVE_POSES = {
    natural = {"sit_chair_idle", "Sit_Chair02", "Sit_Chair03",
        "sitcouchfeet1", "sitcouchknees1", "sitcouch1",
        "sit_idle", "sitting"},
    upright = {"Sit_Chair02", "Sit_Chair03", "sit_chair_idle",
        "sitcouchfeet1", "sit_idle", "sitting"},
    relaxed = {"sitcouchfeet1", "sitcouchknees1", "sitcouch1",
        "sitccouchtv1", "Sit_Chair03", "sit_chair_idle", "sit_idle"},
    forward = {"sitchairtable1", "sitcouchknees1", "Sit_Chair02",
        "sit_chair_idle", "sit_idle"},
    ride = {"sit_rollercoaster", "sit", "sit_chair_idle"},
    -- Unlike natural, this *explicitly* permits the problematic sit_chair
    -- sequence with gestures/arms forward, for players who prefer it.
    chair = {"sit_chair", "sit_chair_idle", "Sit_Chair02", "sit_idle"}
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

local function FindSitSequence(npc, pose, frame, customName)
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
                "This model does not contain '" .. name .. "'."
        end
        local lowered = string.lower(sequenceName)
        if not (lowered:find("sit", 1, true) or
                lowered:find("chair", 1, true) or
                lowered:find("couch", 1, true)) then
            return nil, nil, nil, nil,
                "Custom animation must be a Source sit/chair/couch sequence."
        end
    else
        for _, candidate in ipairs(VALVE_POSES[pose] or VALVE_POSES.natural) do
            sequence, sequenceName = FindNamedSequence(npc, candidate)
            if sequence ~= nil then break end
        end
        if sequence == nil and pose ~= "chair" and pose ~= "ride" then
            -- Prefer an actual HL2 engine activity over fake bone poses.
            -- Never silently use sit_chair here: on many NPCs it makes
            -- them reach forward instead of sitting with relaxed hands.
            local act = rawget(_G, "ACT_BUSY_SIT_CHAIR")
            if act ~= nil then
                local seq = npc:SelectWeightedSequence(act)
                if seq and seq >= 0 then
                    local name = npc:GetSequenceName(seq)
                    if name and name:lower() ~= "sit_chair"
                        and name:lower() ~= "sit_rollercoaster" then
                        sequence, sequenceName = seq, name
                    end
                end
            end
        end
    end

    if sequence == nil then
        return nil, nil, nil, nil,
            "No natural Valve chair-idle sequence on model " ..
            (npc:GetModel() or "(unknown)") ..
            ". Aim at the NPC and run npc_sitter_list_anims. " ..
            "Legacy sit_chair remains selectable separately."
    end
    local info = npc:GetSequenceInfo(sequence)
    -- Source STUDIO_LOOPING flag = 0x0001.
    local looping = info and info.flags and
        bit.band(info.flags, 1) ~= 0 or false
    local heldFrame = (frame and frame >= 0) and frame or 0.5
    return sequence, sequenceName, heldFrame, looping
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

    local function ApplySitPose(npc, force)
        if not IsValid(npc) then return false end
        local data = npc.NPCSitterData
        if not data or data.sequence == nil then return false end

        -- Prevent the Source NPC AI from overriding the selected idle.
        if ACT_DO_NOT_DISTURB and npc.SetIdealActivity then
            npc:SetIdealActivity(ACT_DO_NOT_DISTURB)
        end
        if force or npc:GetSequence() ~= data.sequence then
            npc:ResetSequence(data.sequence)
            npc:ResetSequenceInfo()
            if data.looping then npc:SetCycle(0) end
        end

        if data.looping then
            npc:SetPlaybackRate(1)  -- native Valve idle animation
        else
            -- For a non-looping Source pose, stop in the middle rather
            -- than playing its exit back to standing or a T-pose.
            npc:SetPlaybackRate(0)
            npc:SetCycle(data.poseCycle)
        end
        return true
    end

    function NPC_SITTER.UpdateTransform(npc, offset, rotation, pose, frame, customSequence)
        if not IsValid(npc) or not npc.NPCSitterData then
            return false, "NPC is not seated."
        end
        local data = npc.NPCSitterData
        if not IsValid(data.seat) then return false, "Seat was removed." end
        local seq, name, cycle, loop, err =
            FindSitSequence(npc, pose, frame, customSequence)
        if seq == nil then return false, err end

        data.offset = Vector(offset.x, offset.y, offset.z)
        data.localAngles = Angle(rotation.p, rotation.y, rotation.r)
        data.pose = pose
        data.sequence = seq
        data.sequenceName = name
        data.poseCycle = cycle
        data.looping = loop

        if npc:GetParent() ~= data.seat then npc:SetParent(data.seat) end
        npc:SetLocalPos(data.offset)
        npc:SetLocalAngles(data.localAngles)
        ApplySitPose(npc, true)
        return true, string.format("Valve sequence %s (%s)",
            name, loop and "loop" or "held original frame")
    end

    local function RestoreNPC(npc, data, nextToSeat)
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
            if data.idealActivity ~= nil and npc.SetIdealActivity then
                npc:SetIdealActivity(data.idealActivity)
            end
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

    function NPC_SITTER.SeatNPC(npc, seat, offset, rotation, pose, frame, customSequence)
        if not IsValid(npc) or not npc:IsNPC() then return false, "Invalid NPC." end
        if not IsSeat(seat) then return false, "Target is not a vehicle seat." end
        if seat.GetDriver and IsValid(seat:GetDriver()) then
            return false, "A player is already in this seat."
        end
        if IsValid(seat.NPCSitterNPC) and seat.NPCSitterNPC ~= npc then
            return false, "Seat already contains an NPC."
        end

        -- Validate animation first: don't parent NPCs that lack a seated pose.
        local sequence, sequenceName, cycle, looping, err =
            FindSitSequence(npc, pose, frame, customSequence)
        if sequence == nil then return false, err end
        if npc.NPCSitterData then NPC_SITTER.UnseatNPC(npc, false) end

        npc.NPCSitterData = {
            seat = seat, moveType = npc:GetMoveType(),
            collisionGroup = npc:GetCollisionGroup(), npcState = npc:GetNPCState(),
            idealActivity = npc:GetIdealActivity(),
            pos = npc:GetPos(), ang = npc:GetAngles(),
            offset = Vector(offset.x, offset.y, offset.z),
            localAngles = Angle(rotation.p, rotation.y, rotation.r),
            pose = pose, sequence = sequence, sequenceName = sequenceName,
            poseCycle = cycle, looping = looping
        }
        ReserveSeat(seat)
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
        return true, string.format("Valve sequence %s (%s)",
            sequenceName, looping and "loop" or "held original frame")
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
    panel:NumSlider("Non-looping frame (-1 = middle)", "npc_sitter_pose_cycle", -1, 1, 2)
    panel:Help("True idle loops play normally. Non-looping Source animations hold a frame to avoid T-pose. Some models have no natural chair animation. Aim at them and run npc_sitter_list_anims in the client console.")
    panel:NumSlider("X offset", "npc_sitter_offset_x", -100, 100, 1)
    panel:NumSlider("Y offset", "npc_sitter_offset_y", -100, 100, 1)
    panel:NumSlider("Z offset", "npc_sitter_offset_z", -100, 100, 1)
    panel:Help("Rotation offset")
    panel:NumSlider("Pitch", "npc_sitter_rot_p", -180, 180, 1)
    panel:NumSlider("Yaw", "npc_sitter_rot_y", -180, 180, 1)
    panel:NumSlider("Roll", "npc_sitter_rot_r", -180, 180, 1)
    panel:Help("RMB releases NPC; Reload on an empty NPC-only seat unlocks it.")
end
