local Math = require 'tests/Math';

local test = true;
if test then
    local math = Math.new();
    print('(class method) PI = ' .. tostring(math.getPI()));
    print('(class instance) PI = ' .. tostring(math.PI));
    print('(static call) PI = ' .. tostring(Math.PI));
end
