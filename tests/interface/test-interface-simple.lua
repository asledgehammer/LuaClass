local SimpleInterface = require 'tests/SimpleInterface';
local SimpleImplementation = require 'tests/SimpleImplementation';

print('Interface: \t' .. tostring(SimpleInterface));
print('Class: \t' .. tostring(SimpleImplementation));

local o = SimpleImplementation:new();
o:bMethod();
o:aMethod();

SimpleInterface.aStaticMethod();
