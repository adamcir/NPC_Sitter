NPC Sitter - Garry's Mod
=========================

INSTALL
Windows: tools\install.bat ["<path to garrysmod>"]
PowerShell: .\tools\install.ps1 ["<path to garrysmod>"]
Linux: bash tools/install.sh ["<path to garrysmod>"]

Installers copy addon/npc_sitter to garrysmod/addons/npc_sitter.
IMPORTANT: Restart Garry's Mod before testing old saves. An existing
session can still have cyclic Lua data created by an older version.

USAGE
1. LMB an NPC, then LMB the vehicle seat.
2. Seat mode: Automatic / Regular chair / Prisoner pod.
3. Choose a Valve animation preset, custom sequence, and animation
   frame (-1 for auto). X/Y/Z and Pitch/Yaw/Roll offsets remain.
4. LMB seated NPC or seat to update settings; RMB releases the NPC.
5. The seat remains reserved for NPCs even if the NPC dies/is removed.
   Reload on an EMPTY reserved seat to unlock it for players.

COMMUNITY-REQUESTED FIXES (2026-11)
- Sandbox saves, duplications, and loading:
  * Runtime NPC-to-seat references are now stored outside Entity:GetTable()
    in weak-key Lua tables. The previous nested tables could be serialized
    recursively and caused: "attempt to serialize structure with cyclic
    reference" when saving a Sandbox world.
  * duplicator.StoreEntityModifier records only primitive strings/numbers
    and nested numeric offset/rotation tables. Both the NPC and seat
    carry a matching token and position/pose settings.
  * On duplication or loading, the addon attempts to pair pasted NPCs
    and seats again and reapply native sitting animation and offsets.
  * If the save contains a seat without its parented NPC, the add-on
    attempts to recreate a standard npc_* class from the seat snapshot.
    Nonstandard entities or models may not support recreation.
- Killable NPCs:
  * No godmode or damage immunity is applied to seated NPCs.
  * A lethal hit unseats the NPC near the chair before normal
    damage processing so normal death/ragdoll behavior can occur.
  * The death hook cleans up the seat association. Player access stays
    blocked until the chair is explicitly unlocked.
- Prisoner pods:
  * Separate selectable mode with Automatic detection.
  * Uses a Source sitting animation held at a seated frame to
    avoid ending in a T-pose.
- Missing sitting animations:
  * The tool refuses to seat a model without a usable native
    sit/chair/couch animation rather than posing it as a standing NPC.

TEST PLAN (verify in-game before claiming a fix is complete)
1. Spawn 2 NPCs and 2 seats, seat them, save a Sandbox world, load it,
   and check both NPCs remain seated in the corresponding seats.
2. Duplicate seat+NPC together; then duplicate just the seat. Check
   that a seat-only copy restores the NPC where the model allows.
3. Reposition an NPC and save/load again; verify offset/rotation and
   animation settings.
4. Shoot a seated NPC until it dies and verify a normal kill and that
   the seat is no longer occupied by a live NPC.
5. Remove a seated NPC and try seating another in the same chair;
   unlock the chair with Reload when empty.
6. Test regular chair and prisoner pod modes separately.

DIAGNOSTICS
Aim at an NPC and run in the client console:
    npc_sitter_list_anims
It prints actual Source sit/chair/couch animations in that NPC model.
For Dr. Kleiner, the game-reported sitting idle is Sit_Chair.
