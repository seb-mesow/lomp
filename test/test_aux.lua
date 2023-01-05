---@diagnostic disable: lowercase-global

require("test")

local aux = require("lomp-aux")

function test_host_width()
    local exp_num = 64
    if 0x7FFFFFFF + 1 < 0 then
        exp_num = 32
    end
    local res_num = aux.host_width()
    lu.assert_equals(res_num, exp_num)
end

function test_host_non_neg_width()
    local exp_num = 63
    if 0x7FFFFFFF + 1 < 0 then
        exp_num = 31
    end
    local res_num = aux.host_non_neg_width()
    lu.assert_equals(res_num, exp_num)
end

function test_count_leading_zeros()
    local width = 16
    local host_width = aux.host_width()
    local host_non_neg_width = aux.host_non_neg_width()
    
    ---@param num integer
    ---@param width integer
    ---@param exp_num integer
    local function test_case(num, width, exp_num)
        assert( width >= 1 )
        assert( width <= host_width )
        if num < (1 << width) then
            local res_num = aux.count_leading_zeros(num, width)
            lu.assert_equals(res_num, exp_num)
        end
    end
    
    test_case(   0x0, width, width    )
    test_case(   0x1, width, width - 1)
    test_case(   0x2, width, width - 2)
    test_case(   0x3, width, width - 2)
    test_case(   0x4, width, width - 3)
    test_case(  0x10, width, width - 5)
    test_case(  0x80, width, width - 8)
    test_case(0x8080, width, width -16)
    
    test_case(     0x0, host_non_neg_width, host_non_neg_width    )
    test_case(     0x1, host_non_neg_width, host_non_neg_width - 1)
    test_case(     0x2, host_non_neg_width, host_non_neg_width - 2)
    test_case(     0x3, host_non_neg_width, host_non_neg_width - 2)
    test_case(     0x4, host_non_neg_width, host_non_neg_width - 3)
    test_case(    0x10, host_non_neg_width, host_non_neg_width - 5)
    test_case(    0x80, host_non_neg_width, host_non_neg_width - 8)
    test_case(  0x7080, host_non_neg_width, host_non_neg_width -15)
    test_case(  0x8080, host_non_neg_width, host_non_neg_width -16)
    test_case(0x808080, host_non_neg_width, host_non_neg_width -24)
    
    test_case(-1, host_width, 0)
    test_case(math.mininteger, host_width, 0)
end

function test_is_power_of_two()
    ---@param num integer
    ---@param exp_bool boolean
    local function test_case(num, exp_bool)
        local res_bool = aux.is_power_of_two(num)
        lu.assert_equals(res_bool, exp_bool)
    end
    test_case( 0x0, false)
    test_case( 0x1, true )
    test_case( 0x2, true )
    test_case( 0x3, false)
    test_case( 0x4, true )
    test_case( 0x5, false)
    test_case( 0x8, true )
    test_case(0x10, true )
    test_case(0x20, true )
    test_case(0x40, true )
    test_case(0x80, true )
    test_case(0xFF, false)

    test_case(-  0, false)
    test_case(-  1, false)
    test_case(-  2, false)
    test_case(-  3, false)
    test_case(-  4, false)
    test_case(-  5, false)
    test_case(-  8, false)
    test_case(- 16, false)
    test_case(- 32, false)
    test_case(- 64, false)
    test_case(-128, false)
    test_case(-255, false)
end

os.exit( lu.LuaUnit.run())
-- Never add any arguments to luaunit,
-- if it is expected, that the VS Code Lua Test Extensions,
-- correctly parse the test results.
-- Instead prefix the name of the test with "DISABLED__" .
