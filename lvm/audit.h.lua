--- @meta

---[[
--- @author asledgehammer, JabDoesThings 2025
---]]

--- @class LVMAuditModule: LVMModule
local API = {};

--- @param paramDef ParameterDefinition
--- @param i integer
--- @param errHeader string
function API.auditParameter(paramDef, i, errHeader) end

--- @param parameters ParameterDefinition[]?
--- @param errHeader string
---
--- @return ParameterDefinition[]
function API.auditParameters(parameters, errHeader) end

--- @param name string
--- @param errHeader string
---
--- @return string
function API.auditMethodParamName(name, errHeader) end

--- @param structScope ClassScope
--- @param propertyScope ClassScope|nil
---
--- @return ClassScope
function API.auditStructPropertyScope(structScope, propertyScope, errHeader) end

--- @param returns any[]|any
--- @param errHeader string
---
--- @return string[]
function API.auditMethodReturnsProperty(returns, errHeader) end

--- @param genDef GenericTypeDefinition
function API.auditGenericType(genDef) end

--- Checks final fields in a class for uninitialization. This is for post-constructor analysis and audits.
---
--- @param classDef ClassStructDefinition
--- @param o ClassInstance
function API.auditFinalFields(classDef, o) end

--- @param consDef ConstructorDefinition
function API.auditConstructor(consDef) end
