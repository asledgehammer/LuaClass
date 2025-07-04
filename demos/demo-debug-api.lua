local obj = {
    type = 'AClass'
};

function obj:inspect()
    print('hi!');

    -- Name of calling function.
    print('name of function: ' .. debug.getinfo(2, "n").name);

    -- Name of context. (type: string)
    local s, obj = debug.getlocal(2, 1);
    print('name of object: ' .. obj.type);
end

function obj:a_func()
    obj:inspect();
end

obj:a_func();
