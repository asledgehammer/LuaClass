---[[
--- @author asledgehammer, JabDoesThings 2025
---]]

local LuaClass = require 'LuaClass';
local newClass = LuaClass.newClass;

local Dimension = newClass({
    scope = 'public',
});

Dimension:addField({
    scope = 'private',
    type = 'number',
    name = 'width',
    value = 0
});

Dimension:addField({
    scope = 'private',
    type = 'number',
    name = 'height',
    value = 0
});

Dimension:addConstructor({
    scope = 'public',

    parameters = {
        { type = 'number', name = 'width' },
        { type = 'number', name = 'height' },
    },

    --- @param self Dimension
    super = function(self)
        print('Dimension(width, height) super');
        self:super();
    end,

    --- @param self Dimension
    --- @param width number
    --- @param height number
    body = function(self, width, height)
        print('Dimension(width, height) body');
        self.width = width;
        self.height = height;
    end
});

Dimension:addMethod({
    scope = 'public',
    name = 'getWidth',
    returns = 'number',

    --- @param self Dimension
    ---
    --- @return number width
    body = function(self)
        return self.width;
    end
});

Dimension:addMethod({
    scope = 'public',
    name = 'getHeight',
    returns = 'number',

    --- @param self Dimension
    ---
    --- @return number height
    body = function(self)
        return self.height;
    end
});

Dimension:addMethod({
    scope = 'public',
    name = 'toString',
    returns = 'string',

    --- @param self Dimension
    body = function(self)
        return tostring(self:getWidth()) .. ', ' .. tostring(self:getHeight());
    end
});

Dimension:addMethod({
    scope = 'public',
    name = 'equals',
    parameters = {
        { name = 'other', type = 'any' }
    },
    returns = 'boolean',

    --- @param self Dimension
    --- @param other any
    body = function(self, other)
        if not other.__type__ or self.__type__ ~= other.__type__ then
            return false;
        end
        --- @cast other Dimension
        return self:getWidth() == other:getWidth() and self:getHeight() == other:getHeight();
    end
});

Dimension:finalize();

--- @cast Dimension DimensionDefinition
return Dimension;
