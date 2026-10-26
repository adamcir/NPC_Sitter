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
- Looped sitting idles play at normal speed; non-looping sequences
  are held at a native frame to avoid switching to standing/T-pose.
- The legacy sit_chair gesture sequence is intentionally NOT the
  default: on some models it produces exaggerated forward arms.
  It is still available via "Legacy sit_chair".
- Some models have NO natural Valve chair-idle animation. The
  addon cannot conjure an absent animation without a compiled
  model/animation replacement. It will report this instead of
  silently forcing an unsuitable pose.

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
- If the model only lists sit_chair (and it has unnatural arms),
  the proper fix requires a different original sequence or an
  actual model animation, not rotating the arms with Lua.
