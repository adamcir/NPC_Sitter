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
- The original NPC-Sitter_GMod code supplied the seating/parenting
  approach. Native model animations are now deliberately held at a
  seated frame with SetPlaybackRate(0); the original version could
  finish an animation and leave the NPC in a T-pose.
- A lightweight Think guard restores the original Source seated
  sequence if the engine NPC AI changes it.
- The "Natural" preset now prioritizes native Sit_Chair/chair-idle
  before rollercoaster/couch fallback animations. Dr. Kleiner has
  Sit_Chair (id 837 in the user's model). This avoids the hunched
  rollercoaster default. For custom models with only couch sequences,
  choose a better one through Custom Source sequence if available.
- "Sitting pose frame" (-1 = automatic) chooses which original
  animated frame to hold. You can adjust it per model/seat without
  changing the skeleton.
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
