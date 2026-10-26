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
