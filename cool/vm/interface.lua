---[[
--- @author asledgehammer, JabDoesThings 2025
---]]

local dump = require 'cool/dump';
local DebugUtils = require 'cool/debug';

local PrintPlus = require 'cool/print';
local errorf = PrintPlus.errorf;

local utils = require 'cool/vm/utils';
local readonly = utils.readonly;

--- @type VM
local vm;

local API = {

    __type__ = 'VMModule',

    -- Method(s)
    --- @param _vm VM
    setVM = function(_vm)
        vm = _vm;
        vm.moduleCount = vm.moduleCount + 1;
    end
};

local function applyMetatable(self)
    local mt = getmetatable(self) or {};
    local __properties = {};
    for k, v in pairs(self) do __properties[k] = v end
    -- mt.__metatable = false;
    mt.__tostring = function() return vm.print.printInterface(self) end

    local finalizing = false;

    mt.__index = function(_, field)
        -- Interfaces cannot be instantiated so access to anything requires finalization.
        if not finalizing and not self.__readonly__ then
            finalizing = true;
            self:finalize();
            finalizing = false;
        end

        return __properties[field];
    end

    mt.__newindex = function(tbl, field, value)
        -- TODO: Visibility scope analysis.
        -- TODO: Type-checking.

        if not self.__readonly__ then
            __properties[field] = value;
            return;
        end

        -- Interfaces cannot be instantiated so access to anything requires finalization.
        if not finalizing and not self.__readonly__ then
            finalizing = true;
            self:finalize();
            finalizing = false;
        end

        if field == 'super' or field == '__super__' then
            errorf(2, '%s Cannot set super. (Static context)', self.printHeader);
            return;
        end

        -- Post-finalize assignment.
        if field == 'classObj' and not __properties['classObj'] then
            __properties['classObj'] = value;
            return;
        end

        local fd = self:getField(field);

        -- Inner class invocation.
        if self.children[field] then
            if vm.isOutside() then
                errorf(2, 'Cannot set inner struct explicitly. Use the API.');
            end

            __properties[field] = value;

            return;
        end

        if not fd then
            errorf(2, 'FieldNotFoundException: Cannot set new field or method: %s.%s',
                self.path, field
            );
            return;
        elseif not fd.static then
            errorf(2, 'StaticFieldException: Assigning non-static field in static context: %s.%s',
                self.path, field
            );
            return;
        end

        local level, relPath = vm.scope.getRelativePath();

        vm.stack.pushContext({
            class = self,
            element = fd,
            context = 'field-set',
            line = DebugUtils.getCurrentLine(level),
            path = DebugUtils.getPath(level)
        });

        local callInfo = DebugUtils.getCallInfo(level, nil, true);
        callInfo.path = relPath;
        local scopeAllowed = vm.scope.getScopeForCall(fd.class, callInfo);

        if not vm.scope.canAccessScope(fd.scope, scopeAllowed) then
            local errMsg = string.format(
                'IllegalAccessException: The field %s.%s is set as "%s" access level. (Access Level from call: "%s")\n%s',
                self.name, fd.name,
                fd.scope, scopeAllowed,
                vm.stack.printStackTrace()
            );
            vm.stack.popContext();
            print(errMsg);
            error('', 2);
            return;
        end

        -- (Just in-case)
        if value == vm.constants.UNINITIALIZED_VALUE then
            local errMsg = string.format('%s Cannot set %s as UNINITIALIZED_VALUE. (Internal Error)\n%s',
                self.printHeader, field, vm.stack.printStackTrace()
            );
            vm.stack.popContext();
            error(errMsg, 2);
            return;
        end

        if fd.final then
            local ste = vm.stack.getContext();
            if not ste then
                vm.stack.popContext();
                errorf(2, '%s Attempt to assign final field %s outside of Class scope.', self.printHeader, field);
                return;
            end

            local context = ste:getContext();
            local class = ste:getCallingClass();
            if class ~= self then
                vm.stack.popContext();
                errorf(2, '%s Attempt to assign final field %s outside of Class scope.', self.printHeader, field);
                return;
            elseif context ~= 'constructor' then
                vm.stack.popContext();
                errorf(2, '%s Attempt to assign final field %s outside of constructor scope.', self.printHeader, field);
                return;
            elseif fd.assignedOnce then
                vm.stack.popContext();
                errorf(2, '%s Attempt to assign final field %s. (Already defined)', self.printHeader, field);
                return;
            end
        end

        -- Set the value.
        __properties[field] = value;

        vm.stack.popContext();

        -- Apply forward the value metrics.
        fd.assignedOnce = true;
        fd.value = value;
    end

    setmetatable(self, mt);
end

-- Internal API
local IAPI = {};

-- MARK: - Method

--- @cast API VMInterfaceModule

--- @param self InterfaceStructDefinition
--- @param methodDefinition InterfaceMethodDefinitionParameter
---
--- @return MethodDefinition
function IAPI.addMethod(self, methodDefinition)
    local errHeader = string.format('InterfaceStructDefinition(%s):addMethod():', self.name);

    local body = methodDefinition.body;
    local bodyInfo = vm.executable.getExecutableInfo(body);

    local name = vm.audit.auditMethodParamName(methodDefinition.name, errHeader);
    local types = vm.audit.auditMethodReturnsProperty(methodDefinition.returnTypes, errHeader);
    local parameters = vm.audit.auditParameters(methodDefinition.parameters, errHeader);

    local md = {

        __type__ = 'MethodDefinition',

        -- Base properties. --
        class = self,
        name = name,
        returnTypes = types,
        parameters = parameters,
        body = body,

        -- Used for scope-visibility analysis. --
        scope = 'public',
        bodyInfo = bodyInfo,

        -- General method flags --
        static = false,
        final = false, -- Cannot define finals in a interface context.

        -- Compiled method flags --
        audited = false,
        override = false,
        super = nil,

        -- Interface definition. --
        interface = self, -- Lets the VM know this belongs to an interface.
        default = body ~= nil,

        -- Always falsify class flags in class method definitions. --
        abstract = false,
    };

    md.signature = vm.executable.createSignature(md);

    --- @cast md MethodDefinition

    local methodCluster = self.declaredMethods[md.name];
    if not methodCluster then
        methodCluster = {};
        self.declaredMethods[md.name] = methodCluster;
    end
    methodCluster[md.signature] = md;

    return md;
end

--- @cast API VMInterfaceModule

--- @param self InterfaceStructDefinition
--- @param definition InterfaceStaticMethodDefinitionParameter
---
--- @return MethodDefinition
function IAPI.addStaticMethod(self, definition)
    local errHeader = string.format('InterfaceStructDefinition(%s):addStaticMethod():', self.name);

    local body = definition.body;

    local scope = vm.audit.auditStructPropertyScope(self.scope, definition.scope, errHeader);
    local name = vm.audit.auditMethodParamName(definition.name, errHeader);
    local types = vm.audit.auditMethodReturnsProperty(definition.returnTypes, errHeader);
    local parameters = vm.audit.auditParameters(definition.parameters, errHeader);
    local bodyInfo = vm.executable.getExecutableInfo(body);

    local md = {

        __type__ = 'MethodDefinition',

        -- Base properties. --
        class = self,
        name = name,
        returnTypes = types,
        parameters = parameters,
        body = body,
        bodyInfo = bodyInfo,

        -- Used for scope-visibility analysis. --
        scope = scope,

        -- General method flags --
        static = true,
        final = false, -- Cannot define finals in a interface context.

        -- Compiled method flags --
        audited = false,
        override = false,
        super = nil,

        -- Interface definition. --
        interface = self, -- Lets the VM know this belongs to an interface.
        default = body ~= nil,

        -- Always falsify class flags in class method definitions. --
        abstract = false,
    };

    md.signature = vm.executable.createSignature(md);

    --- @cast md MethodDefinition

    local methodCluster = self.declaredMethods[md.name];
    if not methodCluster then
        methodCluster = {};
        self.declaredMethods[md.name] = methodCluster;
    end
    methodCluster[md.signature] = md;

    return md;
end

--- Attempts to resolve a MethodDefinition in the ClassStructDefinition. If the method isn't defined in the class,
--- `nil` is returned.
---
--- @param self InterfaceStructDefinition
--- @param name string
---
--- @return MethodDefinition[]? methods
function IAPI.getDeclaredMethods(self, name)
    return self.declaredMethods[name];
end

--- @param self InterfaceStructDefinition
--- @param name string
--- @param args any[]
---
--- @return MethodDefinition|nil methodDefinition
function IAPI.getMethod(self, name, args)
    local method = self:getDeclaredMethod(name, args);
    if not method and self.super then
        method = self.super:getMethod(name, args);
    end
    return method;
end

--- @param self InterfaceStructDefinition
--- @param name string
--- @param args any[]
---
--- @return MethodDefinition|nil methodDefinition
function IAPI.getDeclaredMethod(self, name, args)
    local argsLen = #args;
    local methods = self.declaredMethods[name];

    -- No declared methods with name.
    if not methods then
        return nil;
    end

    for i = 1, #methods do
        local method = methods[i];
        local methodParams = method.parameters;
        local paramsLen = #methodParams;

        if argsLen == paramsLen then
            --- Empty args methods.
            if argsLen == 0 then
                return method;
            else
                for j = 1, #methodParams do
                    local arg = args[j];
                    local parameter = methodParams[j];
                    if not vm.type.isAssignableFromType(arg, parameter.types) then
                        method = nil;
                        break;
                    end
                end
                if method then return method end
            end
        end
    end
    return nil;
end

--- @param self InterfaceStructDefinition
--- @param line integer
---
--- @return MethodDefinition|nil method
function IAPI.getMethodFromLine(self, line)
    --- @type MethodDefinition
    local md;
    for _, mdc in pairs(self.declaredMethods) do
        for i = 1, #mdc do
            md = mdc[i];
            if line >= md.lineRange.start and line <= md.lineRange.stop then
                return md;
            end
        end
    end
    return nil;
end

-- MARK: - Hierarchical

--- (Handles recursively going through sub-interfaces to see if a class is a sub-class)
---
--- @param subClass InterfaceStructDefinition
--- @param classToEval InterfaceStructDefinition
---
--- @return boolean result True if the interface to evaluate is a super-class of the subClass.
function IAPI.__recurseSubInterface(subClass, classToEval)
    local subLen = #subClass.sub;
    for i = 1, subLen do
        local next = subClass.sub[i];
        if IAPI.isAssignableFromType(next, classToEval) or IAPI.__recurseSubInterface(next, classToEval) then
            return true;
        end
    end
    return false;
end

--- @param interface InterfaceStructDefinition The interface to evaulate.
---
--- @return boolean result True if the interface to evaluate is a super-interface of the sub-interface.
function IAPI:isSubInterface(self, interface)
    if IAPI.__recurseSubClass(self, interface) then
        return true;
    end
    return false;
end

--- @param self InterfaceStructDefinition
--- @param struct StructDefinition
---
--- @return boolean
function IAPI.isAssignableFromType(self, struct)
    if struct.__type__ ~= 'InterfaceStructDefinition' then
        return false;
    end

    --- @cast struct InterfaceStructDefinition

    return self == struct or IAPI.isSuperInterface(self, struct);
end

--- @param self InterfaceStructDefinition
--- @param interface InterfaceStructDefinition?
---
--- @return boolean
function IAPI.isSuperInterface(self, interface)
    --- @type InterfaceStructDefinition|nil
    local next = self.super;
    while next do
        if next == interface then return true end
        next = next.super;
    end
    return false;
end

function IAPI.addStaticField(self, fd)
    --- @type FieldDefinition
    local args = {
        __type__ = 'FieldDefinition',
        audited = false,
        class = self,
        types = fd.types,
        type = fd.type,
        name = fd.name,
        scope = 'public',
        static = true,
        final = true,
        value = fd.value,
        get = fd.get,
        set = fd.set,
        assignedOnce = false,
    };

    vm.audit.auditField(self, args);

    -- Ensure that all constants are defined.
    if not args.value then
        errorf(2, '%s Cannot add interface field without a value: %s', self.printHeader, args.name);
    end

    self.declaredFields[args.name] = args;

    return args;
end

-- MARK: Struct

--- @param self InterfaceStructDefinition
---
--- @return InterfaceStructDefinition interfaceDef
function IAPI.finalize(self)
    print('Interface:finalize()');

    local errHeader = string.format('Interface(%s):finalize():', self.path);

    if self.__readonly__ then
        errorf(2, '%s Cannot finalize. (Interface is already finalized!)', errHeader);
    elseif self.super and (self.super.__type__ == 'ClassStructDefinition' and not self.super.__readonly__) then
        errorf(2, '%s Cannot finalize. (Super-Interface %s is not finalized!)', errHeader, self.path);
    end

    -- If any auto-methods are defined for fields (get, set), create them before compiling class methods.
    vm.field.compileFieldAutoMethods(self);

    -- TODO: Audit everything.

    vm.executable.compileMethods(self);

    -- Change add methods.
    self.addMethod = function() errorf(2, '%s Cannot add methods. (Interface is final!)', errHeader) end

    -- Set default value(s) for static fields.
    for name, fd in pairs(self.declaredFields) do
        if fd.static then
            self[name] = fd.value;
        end
    end

    self.__middleMethods = {};

    -- Insert boilerplate method invoker function.
    for name, methods in pairs(self.methods) do
        for i, md in pairs(methods) do
            if md.override then
                -- RULE: Cannot override method if super-method is final.
                if md.super.final then
                    local sMethod = vm.print.printMethod(md);
                    errorf(2, '%s Method cannot override final method in super-class: %s',
                        errHeader,
                        md.super.class.name,
                        sMethod
                    );
                    return self;
                    -- RULE: Cannot reduce scope of overrided super-method.
                elseif not vm.scope.canAccessScope(md.scope, md.super.scope) then
                    local sMethod = vm.print.printMethod(md);
                    errorf(2, '%s Method cannot reduce scope of super-class: %s (super-scope = %s, scope = %s)',
                        errHeader,
                        sMethod, md.super.scope, md.scope
                    );
                    return self;
                    -- RULE: override Methods must either be consistently static (or not) with their super-method(s).
                elseif md.static ~= md.super.static then
                    local sMethod = vm.print.printMethod(md);
                    errorf(2,
                        '%s All method(s) with identical signatures must either be static or not: %s (super.static = %s, static = %s)',
                        errHeader,
                        sMethod, tostring(md.super.static), tostring(md.static)
                    );
                    return self;
                end
            end
        end
        self.__middleMethods[name] = vm.executable.createMiddleMethod(self, name, methods);
    end

    -- Add static method references.
    for name, mCluster in pairs(self.declaredMethods) do
        self[name] = self.__middleMethods[name];
    end


    for k, v in pairs(self.declaredFields) do
        --- @params T: FieldDefinition
        self.declaredFields[k] = readonly(v);
    end
    for _, v in pairs(self.declaredMethods) do
        for sig, method in pairs(v) do
            --- @params T: MethodDefinition
            v[sig] = readonly(method);
        end
    end

    self.__readonly__ = true;
    vm.DEFINITIONS[self.path] = self;

    -- Set class as child.
    if self.super then
        table.insert(self.super.sub, self);
    end

    -- Add a reference for global package and static code to enclosing struct.
    if self.outer then
        vm.stepIn();
        self.outer[self.name] = self;
        vm.stepOut();
    end

    return self;
end

-- MARK: - Field

--- Attempts to resolve a FieldDefinition in the ClassStructDefinition. If the field isn't declared for the class
--- level, the super-class(es) are checked.
---
--- @param name string
---
--- @return FieldDefinition? fieldDefinition
function IAPI.getField(self, name)
    local fd = self:getDeclaredField(name);
    if not fd and self.super then
        return self.super:getField(name);
    end
    return fd;
end

--- Attempts to resolve a FieldDefinition in the ClassStructDefinition. If the field isn't defined in the class, nil
--- is returned.
---
--- @param name string
---
--- @return FieldDefinition? fieldDefinition
function IAPI.getDeclaredField(self, name)
    return self.declaredFields[name];
end

function IAPI.getFields(self)
    --- @type FieldDefinition[]
    local array = {};

    local next = self;
    while next do
        for _, fd in pairs(next.declaredFields) do
            table.insert(array, fd);
        end
        next = next.super;
    end

    return array;
end

function API.newInterface(definition, enclosingStruct)
    -- Grab path / package / name context.
    local locInfo = vm.struct.calcPathNamePackage(definition, enclosingStruct);
    local path = locInfo.path;
    local name = locInfo.name;
    local pkg = locInfo.pkg;

    --- @type any
    local id = vm.DEFINITIONS[path] or {};

    -- * Internal Type * --
    id.__type__ = 'InterfaceStructDefinition';

    -- * Struct Properties * --
    id.path = path;
    id.name = name;
    id.pkg = pkg;
    id.type = 'interface:' .. path;

    id.static = definition.static or false;

    -- * Scopable Properties * --
    id.scope = definition.scope or 'package';

    -- * Hierarchical Properties * --
    id.super = definition.extends;
    id.subClasses = {};

    -- * Enclosurable Properties * --
    id.outer = enclosingStruct;
    id.inner = {};
    id.isChild = enclosingStruct ~= nil;
    id.children = {};

    -- * Fieldable Properties * --
    id.declaredFields = {};

    -- * Methodable Properties * --
    id.declaredMethods = {};
    id.methods = {};
    id.methodCache = {};

    -- * Debug Properties * --
    id.printHeader = string.format('interface (%s):', path);

    id.__readonly__ = false;

    --- @cast id InterfaceStructDefinition

    vm.DEFINITIONS[id.path] = id;

    -- Compile the generic parameters for the class.
    id.generics = vm.generic.compileGenericTypesDefinition(id, definition.generics);

    -- Enclosurable: Add the definition to the enclosing struct.
    if enclosingStruct then
        enclosingStruct.inner[id.name] = id;
    end

    --- Set the class to be accessable from a global package reference.
    vm.stepIn();
    vm.package.addToPackageStruct(id);
    vm.stepOut();

    -- MARK: - inner

    function id:addStaticStruct(struct)
        if struct.outer then
            error('TODO: Document', 2);
        end
        struct.static = true;
        struct:setOuterStruct(self);
    end

    function id:setOuterStruct(outer)
        if self.__readonly__ then
            errorf(2, '%s Cannot set enclosing struct. (definition is finalized)');
        end

        if self.outer then
            self.outer.inner[self.name] = nil;
            self.outer = nil;
        end

        local locInfo = vm.struct.calcPathNamePackage(definition, outer);
        self.path = locInfo.path;
        self.name = locInfo.name;
        self.pkg = locInfo.pkg;

        if outer then
            outer.inner[self.name] = self;
            outer[self.name] = self;
        end
    end

    -- * General API * --
    id.finalize = IAPI.finalize;

    -- * Fieldable API * --
    id.addStaticField = IAPI.addStaticField;
    id.getDeclaredField = IAPI.getDeclaredField;
    id.getField = IAPI.getField;

    -- * Methodable API * --
    id.addMethod = IAPI.addMethod;
    id.addStaticMethod = IAPI.addStaticMethod;

    function id:getDeclaredMethods(name)
        return self.declaredMethods[name];
    end

    function id:getMethod(name, args)
        return vm.executable.resolveMethod(self, name, self.methods[name], args);
    end

    function id:getDeclaredMethod(name, args)
        return vm.executable.resolveMethod(self, name, self.declaredMethods[name], args);
    end

    -- * Hierarchical API * --
    id.isSuperInterface = IAPI.isSuperInterface;
    id.isSubInterface = IAPI.isSubInterface;
    id.isAssignableFromType = IAPI.isAssignableFromType;

    function id:isAssignableFromType(superStruct)
        -- All other super-structs fail on assignable check.
        if not superStruct or
            superStruct.__type__ == 'ClassStructDefinition' or
            superStruct.__type__ == 'InterfaceStructDefinition' then
            return false;
        end

        --- @cast superStruct InterfaceStructDefinition
        return self == superStruct or self:isSuperInterface(superStruct);
    end

    function id:isFinalized()
        return self.__readonly__;
    end

    applyMetatable(id);

    return id;
end

return API;
