NPC Sitter - Garry's Mod

INSTALL
Windows: tools\install.bat ["<path to garrysmod>"]
PowerShell: .\tools\install.ps1 ["<path to garrysmod>"]
Linux: bash tools/install.sh ["<path to garrysmod>"]

Each script copies addon/npc_sitter to garrysmod/addons/npc_sitter,
replacing the old installation, just like Adamovian Metro.

USAGE
1. LMB an NPC, then LMB a vehicle seat.
2. Select Natural, Upright, Relaxed, Forward, Rollercoaster, or Custom
   animation. Choose an animation frame (-1 = preset), position XYZ
   and rotation Pitch/Yaw/Roll.
3. LMB the seated NPC or its seat to apply pose and transform changes.
4. RMB releases the NPC. The seat remains reserved for NPCs even
   if the NPC is deleted. Players cannot use the seat with E.
5. Reload on an EMPTY reserved seat to allow player seating again.
   Reload elsewhere clears the NPC selection.

Sitting poses depend on sequences supported by each NPC model.
Models without a valid sitting animation are rejected rather than
left in a crouched or T-pose. Other addons' custom "E to sit" HUD
prompts may require integration using the seat's NPCSitter_Reserved
networked boolean.

POSE NOTES (2026-10-26)
- Sit_chair around frame 0.75 can lift the NPC's hands in the air.
  Natural, Upright, Relaxed and Forward now start at the safer 0.48 frame.
- The Hands / arms control defaults to Hands resting on thighs.
  The 2026-10-26 follow-up fixes raised hands using CLIENTSIDE
  BuildBonePositions and 2-bone arm IK, retaining bone/limb lengths.
  Aiming via server GetBoneMatrix was unreliable: the server can
  have stale or invalid bone transforms.
- Alternative modes: Arms hanging down and Original animation.
- Arm posing requires a standard ValveBiped skeleton with usable
  client render bone matrices. Unrecognized skeletons retain their
  original animation. Change Hands to Original animation if another
  addon is also controlling the arms.
- Aim at the seated NPC or chair and LMB after changing a setting.
- Restart Garry's Mod after installing the updated Lua file.

DIAGNOSTICS
- In the CLIENT console, aim at the seated NPC and enter:
    npc_sitter_debug_arms
  Output includes whether the NPC is networked as seated, whether the
  BuildBonePositions callback runs, left/right IK status, and bone names.
  If the arms still raise after installing, copy this output.
