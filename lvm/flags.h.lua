--- @meta

---[[
--- @author asledgehammer, JabDoesThings 2025
---]]

--- @class LVMFlagsModule: LVMModule
--- @field canSetAudit boolean This private switch flag helps set readonly structs as audited.
--- @field ignorePushPopContext boolean This private switch flag helps mute the stack. (For initializing LVM)
--- @field bypassFieldSet boolean Used to internally assign values.
--- @field allowPackageStructModifications boolean This private switch flag helps shadow assignments and construction of global package struct references.
--- @field internal number If the value is non-zero, the code is considered inside the LVM. Used for bypassing checks.
local API = {};
