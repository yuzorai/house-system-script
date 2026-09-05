# Project-wide Dependencies

The house system owns house-specific behavior. It calls these existing project-wide services through server-side interfaces:

- `InventoryService`: validates and consumes or returns furniture inventory records.
- `WarehouseService`: returns furniture when a house selection changes or a physical deed transfers.
- `PhysicalDeedService`: maintains globally unique physical-house deed ownership and transfers.
- `ItemRegistry`: resolves registered item templates and display information.
- `NotificationServer`: sends player notifications after validated actions.

These services are not copied here because they are broader inventory and notification systems used outside houses. `PhysicalDeedService` is included because physical-property ownership is a central house feature.

Roblox instance contracts such as `ServerStorage.HouseTemplates`, `Workspace.PhysicalHouses`, `ReplicatedStorage.HouseRemotes`, and `ReplicatedStorage.Items.Furnitures` are described in the linked feature document.
