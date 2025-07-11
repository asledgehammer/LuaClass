---[[
--- @author asledgehammer, JabDoesThings 2025
---]]

local vm = require 'cool/vm';
local builder = require 'cool/builder';

local cool = {
    newClass = vm.class.newClass,
    newInterface = vm.interface.newInterface,
    builder = builder,
    import = vm.import,
    packages = vm.package.packages
};

vm.stepIn();

-- Language-level
require 'lua/lang/Object';
require 'lua/lang/Package';
require 'lua/lang/Class';

-- Language-util-level
local StackTraceElement = require 'lua/lang/StackTraceElement';
vm.forName(StackTraceElement.path);

vm.stepOut();

return cool;
