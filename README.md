# Roblox House System

[Gameplay demo video](https://drive.google.com/file/d/1rtq7iNGRbxSwT_SRzrH1MSszA3vLdPfK/view?usp=sharing)

[House System Features and Scripting Structure](docs/House_System_Features_and_Scripting_Structure.docx)

This repository contains the current source for a Roblox house system. It is separated by the same responsibilities used in Roblox Studio: server coordination, client presentation, shared logic, furniture functions, and isolated regression tests.

## System features

- Virtual and physical houses
- House styles, sequential upgrades, taxes, and private/public access
- Owner and visitor sessions with server-side permission checks
- Furniture placement, movement, storage, whole-model bounds validation, and persistence
- Item Displays, Music Players, Editable Signs, and native Seat furniture
- Crafted furniture records and persistent wood finishes
- Unique physical-property deeds and physical-house entry
- Search, grid snapping, precision nudges, and server-validated move/rotation undo-redo

## Repository layout

```text
src/
  server/       Server-authoritative requests, saves, sessions, placement, taxes, deeds, and furniture functions
  client/       House UI, build previews, local presentation, and received session updates
  shared/       Placement geometry and snapshot delta helpers used by both sides
tests/          Edit-mode isolated regression tests using fake stores and temporary instances
docs/           Feature and architecture reference document
```

## Architecture

`HouseController` requests an action through `HouseRemotes`. `HouseSystem` validates the player, active session, ownership or visitor role, cooldown, inventory record, and allowed placement volume. The server applies the change, saves through `HouseDataService`, and sends a session-state update back to relevant clients.

Furniture behavior is data-driven through the `HouseFunction` String attribute. For example, templates can use `ItemDisplay`, `MusicPlayer`, `EditableSign`, or `Seat`; their reusable server behavior is in `src/server/FurnitureFunctions`.

## Important dependencies

This is the complete house-system source, but it integrates with existing project-wide services rather than duplicating unrelated systems. Those integrations are documented in [Dependencies](docs/DEPENDENCIES.md).

## Verification scope

The included `HouseRegression.luau` is an edit-mode suite for save serialization, writer ownership, placement geometry, session behavior, snapshots, move history, template validation, and client startup. It does not replace a real Roblox multiplayer or cross-server playtest.
