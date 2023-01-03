---@diagnostic disable: lowercase-global

-- Because the Lua Test Adapter for VS Code runs the test from
-- the workspace folder / respository root,
-- this file should be kept in this directory.
-- (Maybe one can pass arguments to the lua interpreter used by the Test Adapter.)

package.path = "./test/?.lua;./src/?.lua;"..package.path

local mp_aux = require("lua-only-mp-aux")
local msg = require("lua-only-mp-msg")
local mpn = require("lua-only-mpn")

lu = require("luaunit-patched")

-- set WIDTH == 15 for (simulating) 32-bit systems
-- set WIDTH == 31 for              64-bit systems
-- I recommend WIDTH == 8 to test simulate multiple limb integers.
mpn.__set_limb_width(8, "testing")

local function logf(fmt, ...)
    return print("test Log: "..string.format(fmt, ...))
end

local function num_tostring(num)
    if type(num) == "number" then
        if math.type(num) == "float" then
            return string.format("%f", num)
        else
            return string.format("%d", num)
        end
    else
        return tostring(num)
    end
end

local GROUP_WIDTH_HEX = mpn.get_count_of_hex_digits_per_limb()
function hex(num)
    return mp_aux.grouped_hex_from_int(num, GROUP_WIDTH_HEX)
end

function dec(num)
    return mp_aux.grouped_dec_from_int(num)
end



-- ########## deep coping ##########

local __dp = {} -- table needed because of pairwise recurisve call :-(

-- returns a deep_copy of a value
-- 
-- If the value is a simple type (including nil and strings),
-- then it simply returns the value (therefore making a copy)
-- 
-- If the value is a complex type
-- (currently tables are the only supported complex type)
-- and it has a metamethod __deep_copy,
-- the it calls this as __deep_copy(self_table)
-- 
-- Note: Functions can only be "copied" as reference.
-- 
-- If the value is a complex type
-- and does not have a metamethod __deep_copy,
-- then it uses pairs() to make copies of all keys and values
-- This default __deep_copy function passes the metatable as reference
-- to the deep copy
-- For almost all data structures
-- this default __deep_copy function is not sufficent.
function __dp.deep_copy(v)
    local mt = getmetatable(v)
    if not rawequal(mt, nil) then
        local deep_copy_func = mt.__deep_copy
        if type(deep_copy_func) == "function" then
            return deep_copy_func(v)
        end
    end
    ---@diagnostic disable-next-line: undefined-global
    return __dp.deep_copy_default(v)
end

-- deep copied a table
function __dp.deep_copy_default(obj)
    local type_str = type(obj)
    if rawequal(type_str, "table") then
        local dct = setmetatable({}, __dp.deep_copy(getmetatable(obj)))
        for k, v in pairs(obj) do
            dct[__dp.deep_copy(k)] = __dp.deep_copy(v)
        end
        return dct
    elseif rawequal(type_str, "thread") or rawequal(type_str,"userdata") then
        msg.errorf("__dp.deep_copy_default(value) does not support values"
                 .." of the (complex) type %s", type_str)
        return
    end
    return obj
end




local __TEST_MSG_INFOS = {}

__TEST_MSG_INFOS.backup_test_datum_objs = {}
__TEST_MSG_INFOS.test_datum_objs = {}

function TEST_OP_NAME(op_name)
    assert( type(op_name) == "string" or rawequal(op_name, nil))
    __TEST_MSG_INFOS.op_name = op_name
end

function BEGIN_TEST_DATA()
    local cur_test_datum_objs = __TEST_MSG_INFOS.test_datum_objs
    assert( type(cur_test_datum_objs) == "table" )
    cur_test_datum_objs = __dp.deep_copy(cur_test_datum_objs)
    assert( type(cur_test_datum_objs) == "table" )
    table.insert(__TEST_MSG_INFOS.backup_test_datum_objs, 
                 cur_test_datum_objs)
end

function TEST_DATUM(k, v)
    assert( type(k) == "string" )
    local test_datum_obj = { k = k ; v = v }
    table.insert(__TEST_MSG_INFOS.test_datum_objs, test_datum_obj)
end

function END_TEST_DATA()
    local backups = __TEST_MSG_INFOS.backup_test_datum_objs
    local backup_size = #backups
    assert( backup_size >= 1 )
    __TEST_MSG_INFOS.test_datum_objs = backups[backup_size]
    table.remove(backups)
    assert( #backups == backup_size - 1 )
end

local function __sprint_test_data()
    local str
    for _, test_datum_obj in ipairs(__TEST_MSG_INFOS.test_datum_objs) do
        if rawequal(str, nil) then
            str = ""
        else
            str = str.."\n"
        end
        str = str..string.format("%s == %s", test_datum_obj.k, 
                                        tostring(test_datum_obj.v))
    end
    return str
end

__TEST_MSG_INFOS.on = false
 
function TEST_MSG_ON()
    __TEST_MSG_INFOS.on = true
end

function BEGIN_TEST_CASE()
    if __TEST_MSG_INFOS.on then
        local suffix = ""
        local op_name = __TEST_MSG_INFOS.op_name
        if not rawequal(op_name, nil) then
            suffix = "on operation "..op_name
        end
        if not rawequal(suffix, "") then
            suffix = suffix.." "
        end
        print(string.rep("=", 10).." test case "..suffix..string.rep("=", 30))
        print("test data:")
        print(__sprint_test_data())
        print(string.rep("-", 25).." begin test routine "..string.rep("-", 55))
    end
end

function BEGIN_TEST_OP()
    if __TEST_MSG_INFOS.on then
        print(string.rep("-", 35)
            .." begin operation to test "
            ..string.rep("-", 40))
    end
end
function END_TEST_OP()
    if __TEST_MSG_INFOS.on then
        print(string.rep("-", 35)
            .." end operation to test "
            ..string.rep("-", 40))
    end
end

function END_TEST_CASE()
    if __TEST_MSG_INFOS.on then
        print(string.rep("-", 25)
            .." end test routine "
            ..string.rep("-", 55))
        __TEST_MSG_INFOS.on = false
    end
end

local function __get_msg()
    return __sprint_test_data()
end

-- THE FOLLOWING ASSERTATION FUNCTIONS REQUIRE luaunit-patched.lua !!
    
-- like lu.assert_equals() but prints an auto-generated informative message 
-- about the test data, of the test case when the test case failed. 
function assert_equals(res, exp)
    lu.assert_equals(res, exp, __get_msg)
end

function assert_true(bool)
    lu.assert_true(bool, __get_msg)
end
