---[[
--- @author asledgehammer, JabDoesThings 2025
---]]

local DebugUtils = require 'asledgehammer/util/DebugUtils';

local LVMUtils = require 'LVMUtils';
local arrayContains = LVMUtils.arrayContains;
local errorf = LVMUtils.errorf;

--- @type LVM
local LVM;

--- @type LVMMethodModule
local API = {

    __type__ = 'LVMModule',

    setLVM = function(lvm) LVM = lvm end
};

function API.createMiddleMethod(cd, name, methods)
    return function(o, ...)
        local args = { ... };
        local argsLen = #args;

        --- @type MethodDefinition?
        local md = nil;
        for i = 1, #methods do
            if md then break end
            md = methods[i];
            local parameters = md.parameters or {};
            local paramLen = #parameters;
            if argsLen == paramLen then
                for p = 1, paramLen do
                    local arg = args[p];
                    local parameter = parameters[p];
                    if not LVM.type.isAssignableFromType(arg, parameter.types) then
                        md = nil;
                        break;
                    end
                end
            else
                md = nil;
            end
        end

        local errHeader = string.format('Class(%s):%s():', cd.name, name);

        if not md then
            errorf(2, '%s No method signature exists: %s', errHeader, LVM.print.argsToString(args));
            return;
        end

        LVM.stack.pushContext({
            class = cd,
            element = md,
            context = 'method',
            line = DebugUtils.getCurrentLine(3),
            path = DebugUtils.getPath(3)
        });

        local level, relPath = LVM.scope.getRelativePath();

        local callInfo = DebugUtils.getCallInfo(level, true);
        callInfo.path = relPath;
        local scopeAllowed = LVM.scope.getScopeForCall(md.class, callInfo);

        if not LVM.scope.canAccessScope(md.scope, scopeAllowed) then
            local sMethod = LVM.print.printMethod(md);
            local errMsg = string.format(
                'IllegalAccessException: The method %s is set as "%s" access level. (Access Level from call: "%s")\n%s',
                sMethod,
                md.scope, scopeAllowed,
                LVM.stack.printStackTrace()
            );
            LVM.stack.popContext();
            print(errMsg);
            error('', 2);
            return;
        end

        local lastSuper;
        if o then
            --- Apply super.
            LVM.flags.canGetSuper = true;
            LVM.flags.canSetSuper = true;
            lastSuper = o.super;
            o.super = o.__super__;
            LVM.flags.canGetSuper = false;
            LVM.flags.canSetSuper = false;
        end

        local retVal = nil;
        local result, errMsg = xpcall(function()
            if md.static then
                retVal = md.func(unpack(args));
            else
                retVal = md.func(o, unpack(args));
            end
            -- TODO: Check type-cast of returned value.
        end, debug.traceback);

        if o then
            --- Revert super.
            LVM.flags.canSetSuper = true;
            o.super = lastSuper;
            LVM.flags.canSetSuper = false;
        end

        -- Audit void type methods.
        if retVal ~= nil and md.returns == 'void' then
            local errMsg = string.format('Invoked Method is void and returned value: {type = %s, value = %s}',
                type(retVal),
                tostring(retVal)
            );
            print(errMsg);
            LVM.stack.popContext();
            error('', 2);
            return;
        end

        LVM.stack.popContext();

        -- Throw the error after applying context.
        if not result then error(tostring(errMsg) or '') end

        return retVal;
    end;
end

--- @param classDef LVMClassDefinition
---
--- @return string[] methodNames
function API.getDeclaredMethodNames(classDef, array)
    --- @type string[]
    array = array or {};

    local decMethods = classDef.declaredMethods;
    for name, _ in pairs(decMethods) do
        if not arrayContains(array, name) then
            table.insert(array, name);
        end
    end

    return array;
end

--- @param classDef LVMClassDefinition
--- @param methodNames string[]?
---
--- @return string[] methodNames
function API.getMethodNames(classDef, methodNames)
    methodNames = methodNames or {};
    if classDef.superClass then
        API.getMethodNames(classDef.superClass, methodNames);
    end
    API.getDeclaredMethodNames(classDef, methodNames);
    return methodNames;
end

return API;
