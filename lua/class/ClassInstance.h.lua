--- @meta

---[[
--- @author asledgehammer, JabDoesThings 2025
---]]

--- @class SuperTable
--- 
--- @field methods table<string, function>
--- @field constructor function

--- @class ClassInstance
---
--- @field __type__ string The `class:<package>.<classname>` identity of the class.
--- @field __super__ SuperTable
--- @field __class__ ClassDefinition
--- @field super table|function? This field is dynamically set for each function invocation.
local ClassInstance = {};
