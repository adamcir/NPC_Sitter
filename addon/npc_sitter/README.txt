NPC Sitter - Garry's Mod
=========================

INSTALL
Windows: tools\install.bat ["<path to garrysmod>"]
PowerShell: .\tools\install.ps1 ["<path to garrysmod>"]
Linux: bash tools/install.sh ["<path to garrysmod>"]

Installer copies addon/npc_sitter into garrysmod/addons/npc_sitter,
replacing the previous version, like the Adamovian Metro installer.
Restart Garry's Mod after installing the update.

NATIVE SOURCE ANIMATIONS (2026-10-26)
- Removed the previous custom spine/arm angles, procedural
  ManipulateBoneAngles modifications, clientside BuildBonePositions
  callbacks and two-bone IK. Those made the NPC look unnatural.
- NPCs now play REAL Source/Valve sitting animations already built
  into their individual model: Sit_Chair02, Sit_Chair03,
  sitchairtable1, sitcouchfeet1, sitcouchknees1, and others.
- Select a Valve animation from the tool menu; a preset resolves to
  an available sequence on that model, rather than modifying its
  bones. Different presets can produce the same result if the
  model has only one usable sitting idle.
- Seat animation behavior now matches the original NPC-Sitter_GMod
  source: choose an existing sequence, ResetSequence, SetCycle(0),
  SetPlaybackRate(1); NPC_STATE_SCRIPT and SCHED_NONE are used.
  There is no timer that continually forces a pose or freezes
  playback at a chosen frame. A custom start frame can be selected.
- The default "Natural" preset uses the original fallback sequence
  order: sit_rollercoaster, sit_chair, sit, sit_ground,
  sit_ground_unarmed. On Dr. Kleiner, sit_chair matches his
  existing Sit_Chair animation.
- The "Upright", "Relaxed", "Table/forward", "Vehicle", "Legacy"
  and "Custom" preset choices, X/Y/Z offsets, rotation settings
  and NPC-only chair reservation behavior are preserved.
- As with the original version, an NPC with no supported sitting
  sequence can still be attached to the chair but may look as if
  it is standing. Use npc_sitter_list_anims to inspect models.

USAGE
1. LMB an NPC and then LMB a vehicle chair.
2. Select "Natural chair idle" or another Valve preset.
3. Adjust X/Y/Z or Pitch/Yaw/Roll if needed.
4. LMB the seated NPC or chair to apply new settings.
5. RMB releases the NPC. Chair stays reserved for NPCs even
   after NPC removal. Players cannot use it with E.
6. Reload on an EMPTY reserved seat to unlock player seating.

DIAGNOSTICS
- Aim at Dr. Kleiner or another NPC and type in CLIENT console:
    npc_sitter_list_anims
  This lists the model's ORIGINAL sit/chair/couch animation names
  and whether each is looped. It also displays the native
  ACT_BUSY_SIT_CHAIR sequence.
- To test one of the returned sequences, pick "Custom Source
  sequence" from the menu and copy that sequence name exactly.
- The natural preset resolves Kleiner's Sit_Chair sequence
  (id 837 in the user-tested model). Neither IK nor manually
  repositioning arms is used.
