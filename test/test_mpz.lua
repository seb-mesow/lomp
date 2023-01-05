---@diagnostic disable: lowercase-global

require("test")

local mp_aux = require("lomp-aux")
local mpz = require("lomp-mpz")
local mpn = require("lomp-mpn")

local RADIX = mpn.limb_radix()
local WIDTH = mpn.limb_width()
local HOST_WIDTH = mp_aux.host_width()

local function __table_insert_unique(t, v)
    local already_in_table = false 
    for _, _v in pairs(t) do
        if _v == v then
            already_in_table = true
            break
        end
    end
    if not already_in_table then
        table.insert(t, v)
    end
end

---@class test_tuple
---@field num integer Lua integer
---@field int mpz mpz

---@type test_tuple[]
local sorted_tuples = {}
-- sorted by num increasing

---@class test_pair
---@field self  test_tuple 1st operand test tuple
---@field other test_tuple 2nd operand test tuple

---@type test_pair[]
local sorted_pairs = {}
-- 1. sorted by self.num increasing, 2. sorted by other.num increasing

--- takes a table of Lua integers, converts each in an mpz
--- and combines them to a tuple
--- then sorts the tuples by increasing value
--- and stores the tuples as a sequence in the tuples table (1sr. ret. val)
--- also forms the cartesian product of the set of tuples
--- and stores the pairs of tuples in the pairs table (2nd ret. val)
---
---@param nums integer[]
---
---@nodiscard
---@return test_tuple[] sorted_tuples
---@return test_pair[] sorted_pairs
function build_sorted_sequence(nums)
    for _, num in pairs(nums) do
        assert(type(num) == "number")
        assert(math.type(num) == "integer")
        __table_insert_unique(nums,  num)
        __table_insert_unique(nums, -num)
    end
    table.sort(nums)
    
    local sorted_tuples = {}
    for i, num in pairs(nums) do
        -- HERE TEST OF mpz CONSTRUCTOR
        local int = mpz.new(num)
        -- logf("%s --> %s", dec(num), int:dec())
        -- HERE TEST OF CONVERSION TO LUA INTEGER
        assert( rawequal(int:try_to_lua_int(), num) )
        local tuple = { num = num ; int = int }
        sorted_tuples[i] = tuple
    end
    
    local sorted_pairs = {}
    for i, i_tuple in ipairs(sorted_tuples) do
        for j, j_tuple in ipairs(sorted_tuples) do
            local pair = { self = i_tuple ; other = j_tuple }
            --logf("(%s --> %s ; %s --> %s)",
            --     dec(pair.self.num), pair.self.int:dec(),
            --     dec(pair.other.num), pair.other.int:dec())
            table.insert(sorted_pairs, pair)
        end
    end
    return sorted_tuples, sorted_pairs
end

-- also tests the constructor
local function __build_sorted_sequence_and_test_new_and_test_try_to_lua_int()
    local hugeint_a = math.maxinteger // 100
    local hugeint_b = math.floor(math.sqrt(math.maxinteger))
    local maxdigit = RADIX -1
    local tworadix = 1 << (2*WIDTH)
    local twomaxdigit = tworadix -1
    local mediumint = tworadix // 3
    local smallint = RADIX // 3

    --logf("hugeint_a == %d", hugeint_a)
    --logf("hugeint_b == %d", hugeint_b)
    --logf("mediumint == %d", mediumint)
    --logf("smallint == %d", smallint)
    
    local nums = {
        math.mininteger ; -- needs special handling
        math.maxinteger   ;
        math.maxinteger -1;
        hugeint_a +1;
        hugeint_a   ;
        hugeint_a -1;
        hugeint_b +1 ;
        hugeint_b    ;
        hugeint_b -1 ;
        tworadix   +1 ;
        tworadix      ;
        twomaxdigit   ;
        twomaxdigit-1 ;
        mediumint +1;
        mediumint   ;
        mediumint -1;
        RADIX   +1 ;
        RADIX      ;
        maxdigit   ;
        maxdigit+1 ;
        smallint +1 ;
        smallint    ;
        smallint -1 ;
        2 ;
        1 ;
        0 ;
    }
    
    sorted_tuples, sorted_pairs = build_sorted_sequence(nums)
end

--- unpacks a tuple and calls a function
--- with the number and Integer as arguments
---
---@param func fun(num: integer, int: mpz)
---@param tuples? test_tuple[]
function apply_on_tuples(func, tuples)
    if rawequal(tuples, nil) then
        tuples = sorted_tuples
    end
    ---@cast tuples test_tuple[]
    for _, tuple in ipairs(tuples) do
        -- BEGIN_TEST_DATA()
        -- TEST_DATUM("num", tuple.num)
        -- TEST_DATUM("int", tuple.int)
        func(tuple.num, tuple.int)
        -- END_TEST_DATA()
        -- TEST_OP_NAME(nil)
    end
end

--- unpacks a pair and calls a function
--- with the self tuple and the other tuple as arguments
---
---@param func fun(self: test_tuple, other: test_tuple)
---@param pairs? test_pair[]
function apply_on_pairs(func, pairs)
    if rawequal(pairs, nil) then
        pairs = sorted_pairs
    end
    ---@cast pairs test_pair[]
    for _, pair in ipairs(pairs) do
        --BEGIN_TEST_DATA()
        --TEST_DATUM("self.num", pair.self.num)
        --TEST_DATUM("self.int", pair.self.int)
        --TEST_DATUM("other.num", pair.other.num)
        --TEST_DATUM("other.int", pair.other.int)
        func(pair.self, pair.other)
        --END_TEST_DATA()
        --TEST_OP_NAME(nil)
    end
end



function test_try_to_lua_int()
    -- only special tests of try_to_lua_int()
    ---@param int mpz
    ---@param exp_num integer|nil
    local function test_case(int, exp_num)
        --TEST_MSG_ON()
        -- TEST_OP_NAME("mpz:try_to_lua_int()   (only special values)")
        -- BEGIN_TEST_DATA()
        -- TEST_DATUM("int", int)
        -- TEST_DATUM("exp_num", exp_num)
        -- BEGIN_TEST_CASE()
        -- All nums are of course Lua integers
        -- Thus every corresponding int must be convertable to a Lua integer -
        -- including math.mininteger
        --BEGIN_TEST_OP()
        local res_num = int:try_to_lua_int()
        --END_TEST_OP()
        assert_equals(res_num, exp_num)
        --END_TEST_CASE() ; END_TEST_DATA()
    end
    
    local mpz_from_math_maxinteger = mpz.new(math.maxinteger)
    local mpz_from_math_mininteger = mpz.new(math.mininteger)
    
    test_case(mpz_from_math_mininteger << 1, nil            )
    test_case(mpz_from_math_mininteger - 1 , nil            )
    test_case(mpz_from_math_mininteger     , math.mininteger)
    test_case(mpz_from_math_mininteger >> 1,
              -(1 << (mp_aux.host_non_neg_width()-1)))
    test_case(mpz.new(0)                   , 0              )
    test_case((mpz_from_math_maxinteger >> 1) + 1,
                1 << (mp_aux.host_non_neg_width()-1) )
    test_case(mpz_from_math_maxinteger     , math.maxinteger)
    test_case(mpz_from_math_maxinteger + 1 , nil            )
    test_case(mpz_from_math_maxinteger << 1, nil            )
end

function test_cmp()
    ---@param self test_tuple
    ---@param other test_tuple
    local function test_case(self, other)
        local exp_compare_result
        -- This convention of compare_result behaves
        -- equal to those of GMP's mpz_cmp()
        if self.num < other.num then
            exp_compare_result = -1
        elseif self.num > other.num then
            exp_compare_result = 1
        else
            exp_compare_result = 0
        end
        local res_compare_result = mpz.cmp(self.int, other.int)
        assert_equals(res_compare_result, exp_compare_result)
    end
    
    apply_on_pairs(test_case)
end

function test_comparision_operators()
    ---@param self mpz|integer
    ---@param relation_str string
    ---@param other mpz|integer
    ---@param exp_bool boolean
    local function ____test_case(self, relation_str, other, exp_bool)
        local func
        if relation_str == "<" then
            func = mpz.less
        elseif relation_str == "<=" then
            func = mpz.less_equal
        elseif relation_str == ">" then
            func = mpz.greater
        elseif relation_str == ">=" then
            func = mpz.greater_equal
        else
            func = mpz.equal
        end
        local res_bool = func(self, other)
        assert_equals(res_bool, exp_bool)
    end
    
    ---@param self mpz|integer
    ---@param exp_cmp_res integer
    ---@param other mpz|integer
    local function __test_case(self, exp_cmp_res, other)
        if exp_cmp_res == 0 then -- self == other
            ____test_case(self, "<" , other, false)
            ____test_case(self, "<=", other, true )
            ____test_case(self, "==", other, true )
            ____test_case(self, ">=", other, true )
            ____test_case(self, ">" , other, false)
        elseif exp_cmp_res == 1 then -- self > other
            ____test_case(self, "<" , other, false)
            ____test_case(self, "<=", other, false)
            ____test_case(self, "==", other, false)
            ____test_case(self, ">=", other, true )
            ____test_case(self, ">" , other, true )
        else -- self < other
            ____test_case(self, "<" , other, true )
            ____test_case(self, "<=", other, true )
            ____test_case(self, "==", other, false)
            ____test_case(self, ">=", other, false)
            ____test_case(self, ">" , other, false)
        end
    end
    
    ---@param self  test_tuple
    ---@param other test_tuple
    local function test_case(self, other)
        local exp_cmp_res
        -- This convention of compare_result behaves
        -- equal to those of GMP's mpz_cmp()
        if self.num < other.num then
            exp_cmp_res = -1
        elseif self.num > other.num then
            exp_cmp_res = 1
        else
            exp_cmp_res = 0
        end
        __test_case(self.num, exp_cmp_res, other.num)
        __test_case(self.int, exp_cmp_res, other.num)
        __test_case(self.num, exp_cmp_res, other.int)
        __test_case(self.int, exp_cmp_res, other.int)
    end
    
    -- It is enough to test much fewer pairs,
    -- because we test mpz.cmp() seperately,
    -- which avoids calling mpz.cmp() five times per pair 
    local two_digits_num = RADIX + 1
    local nums = { -two_digits_num ; -1 ; 0 ; 1 ; two_digits_num }
    local _, pairs = build_sorted_sequence(nums)
    
    apply_on_pairs(test_case, pairs)
end

function test_copy()
    ---@param num integer
    ---@param int mpz
    local function test_case(num, int)
        --TEST_MSG_ON()
        -- TEST_OP_NAME("mpz:copy()")
        -- BEGIN_TEST_CASE()
        -- BEGIN_TEST_OP()
        local res_int = int:copy()
        -- END_TEST_OP()
        local res_num = res_int:try_to_lua_int()
        -- assert_true( mpz.equal(res_int, int))
        assert_equals(res_num, num)
        -- END_TEST_CASE()
    end
    
    apply_on_tuples(test_case)
end

function test_abs()
    ---@param num integer
    ---@param int mpz
    local function test_case(num, int)
        --TEST_MSG_ON()
        -- TEST_OP_NAME("mpz:abs()")
        -- BEGIN_TEST_CASE()
        local exp_num = math.abs(num)
        if exp_num < 0 then
            assert( num == math.mininteger )
            local int_a = mpz.new(math.mininteger)
            -- BEGIN_TEST_OP()
            local int_b = mpz.abs(int_a)
            -- END_TEST_OP()
            assert_true( mpz.equal(int_b, -int_a) )
        else
            -- BEGIN_TEST_OP()
            local res_int = mpz.abs(int)
            -- END_TEST_OP()
            local res_num = res_int:to_lua_int()
            assert_equals(res_num, exp_num)
        end
        -- END_TEST_CASE()
    end
    
    apply_on_tuples(test_case)
end

function test_neg()
    ---@param num integer
    ---@param int mpz
    local function test_case(num, int)
        --TEST_MSG_ON()
        -- TEST_OP_NAME("unary negation operator")
        -- BEGIN_TEST_CASE()
        local exp_num = -num
        if ((exp_num < 0) == (num < 0)) and (num ~= 0) then
            assert( num == math.mininteger )
            local int_a = mpz.new(math.maxinteger) + 1
            -- BEGIN_TEST_OP()
            local int_b = - (mpz.new(math.mininteger))
            -- END_TEST_OP()
            assert_true( mpz.equal(int_b, int_a) )
        else
            -- BEGIN_TEST_OP()
            local res_int = -int
            -- END_TEST_OP()
            local res_num = res_int:to_lua_int()
            assert_equals(res_num, exp_num)
        end
        -- END_TEST_CASE()
    end
    
    apply_on_tuples(test_case)
end

function test_shift()
    ---@param num_arg integer
    ---@param int mpz
    ---@param left_shift_amount integer
    local function test_case__lshift(num_arg, int, left_shift_amount)
        --TEST_MSG_ON()
        -- TEST_OP_NAME("<< operator")
        -- BEGIN_TEST_DATA()
        -- TEST_DATUM("s", s)
        -- BEGIN_TEST_CASE()
        local exp_num
        if num_arg < 0 then
            num = -num_arg
        else
            num = num_arg
        end
        -- We assume an infinite word width (to the left)
        if num < 0 then
            -- END_TEST_CASE()
            -- END_TEST_DATA()
            return
        end
        -- if abs(num_arg) has bits, that would be shifted out left
        if (left_shift_amount > 0) and (num & (-1 << (HOST_WIDTH-left_shift_amount))) ~= 0 then
            exp_num = nil
        else
            exp_num = num << left_shift_amount
            if exp_num < 0 then
                -- END_TEST_CASE()
                -- END_TEST_DATA()
                return
            end
            if num_arg < 0 then
                exp_num = -exp_num
            end
        end
        -- BEGIN_TEST_OP()
        local res_int = int << left_shift_amount
        -- END_TEST_OP()
        local res_num = res_int:try_to_lua_int()
        assert_equals(res_num, exp_num)
        -- END_TEST_CASE()
        -- END_TEST_DATA()
    end
    
    ---@param num_arg integer
    ---@param int mpz
    ---@param right_shift_amount integer
    local function test_case__rshift(num_arg, int, right_shift_amount)
        --TEST_MSG_ON()
        -- TEST_OP_NAME(">> operator")
        -- BEGIN_TEST_DATA()
        -- TEST_DATUM("s", right_shift_amount)
        -- BEGIN_TEST_CASE()
        local exp_num
        if num_arg < 0 then
            num = -num_arg
        else
            num = num_arg
        end
        -- We assume an infinite word width (to the left)
        if num < 0 then
            -- END_TEST_CASE() ; END_TEST_DATA()
            return
        end
        -- if abs(num_arg) has bits, that would be shifted out left
        if (right_shift_amount < 0) and (num & (-1 << (HOST_WIDTH+right_shift_amount))) ~= 0 then
            exp_num = nil
        else
            exp_num = num >> right_shift_amount
            if exp_num < 0 then
                -- END_TEST_CASE() ; END_TEST_DATA()
                return
            end
            if num_arg < 0 then
                exp_num = -exp_num
            end
        end
        -- BEGIN_TEST_OP()
        local res_int = int >> right_shift_amount
        -- END_TEST_OP()
        local res_num = res_int:try_to_lua_int()
        assert_equals(res_num, exp_num)
        -- END_TEST_CASE() ; END_TEST_DATA()
    end
    
    local shift_step = (WIDTH >> 1) -1
    if shift_step < 1 then
        shift_step = 1
    end
    
    ---@param num integer
    ---@param int mpz
    local function test_cases(num, int)
        local shift_amount = 0
        repeat
            test_case__lshift(num, int,  shift_amount)
            test_case__lshift(num, int, -shift_amount)
            test_case__rshift(num, int,  shift_amount)
            test_case__rshift(num, int, -shift_amount)
            shift_amount = shift_amount + shift_step
        until shift_amount > HOST_WIDTH
    end
    
    apply_on_tuples(test_cases)
end

function test_add_sub()
    ---@param self  test_tuple
    ---@param other test_tuple
    local function test_case(self, other)
        --TEST_MSG_ON()
        -- TEST_OP_NAME("+ operator")
        -- BEGIN_TEST_CASE()
        ---@type integer|nil
        local exp_num = self.num + other.num
        if ((self.num < 0) == (other.num < 0)) -- detect wrapping around
        and ((exp_num < 0) ~= (self.num < 0)) then
            exp_num = nil
        end
        local res_int = self.int + other.int
        local res_num = res_int:try_to_lua_int()
        assert_equals(res_num, exp_num)
        -- END_TEST_CASE()
    end
    
    apply_on_pairs(test_case)
end

function DISABLED_test_mul()
    ---@param self  test_tuple
    ---@param other test_tuple
    local function test_case(self, other)
        local self_num_abs = math.abs(self.num)
        local other_num_abs = math.abs(other.num)
        if  self_num_abs  <= (math.maxinteger / other_num_abs)
        and other_num_abs <= (math.maxinteger / self_num_abs) then
            local exp_num = self.num * other.num
            -- ignore wrapping around
            if ( (self.num < 0) == (other.num < 0) ) == (exp_num >= 0) then
                local res_int = self.int * other.int
                local res_num = res_int:to_lua_int()
                assert_equals(res_num, exp_num)
            end
        end
    end
    
    apply_on_pairs(test_case)
    
    local maxinteger_int = mpz.new(math.maxinteger)
    local dummy =  maxinteger_int *  maxinteger_int
          dummy =  maxinteger_int * -maxinteger_int
          dummy = -maxinteger_int *  maxinteger_int
          dummy = -maxinteger_int * -maxinteger_int
end

function DISABLED_test_div()
    ---@param self  test_tuple
    ---@param other test_tuple
    local function test_case(self, other)
        if other.num == 0 then
            lu.assert_error_msg_contains(
                "Tried to divide by zero",
                mpz.div, self.int, other.int)
        else
            local exp_num = self.num // other.num
            local remainder_num = self.num - exp_num*other.num
            -- round a negative quotient up towards zero
            if exp_num < 0 and remainder_num ~= 0 then
                exp_num = exp_num +1
            end
            local res_int = self.int // other.int
            local res_num = res_int:to_lua_int()
            lu.assert_equals(res_num, exp_num)
        end
    end
    
    apply_on_pairs(test_case)
    
    local maxinteger_int = mpz.new(math.maxinteger)
    local dummy =  maxinteger_int *  maxinteger_int
          dummy =  maxinteger_int * -maxinteger_int
          dummy = -maxinteger_int *  maxinteger_int
          dummy = -maxinteger_int * -maxinteger_int
end

function DISABLED_test_sqrt()
    ---@param num integer
    ---@param int mpz
    local function test_case(num, int)
        logf("----- test_sqrt(%s) ----------------------------------------", dec(num))
        if num < 0 then
            lu.assert_error_msg_contains(
                "Tried to take the square root of a negative number",
                mpz.sqrt, int)
        else
            local exp_num = math.floor(math.sqrt(num))
            local res_int = mpz.sqrt(int)
            --local res_num = res_int:to_lua_integer()
            --lu.assert_equals(res_num, exp_num)       
        end
    end
    
    apply_on_tuples(test_case)
end

function DISABLED_test_dec()
    ---@param num integer
    ---@param int mpz
    local function test_case(num, int)
        local exp_str = string.format("%d", num)
        local res_str = int:dec()
        lu.assert_equals(res_str, exp_str)
    end
    
    apply_on_tuples(test_case)
end

function DISABLED_test_hex()
    ---@param num integer
    ---@param int mpz
    local function test_case(num, int)
        local exp_str = ""
        if num < 0 then
            num = -num
            exp_str = "-"
        end
        exp_str = exp_str..string.format("%X", num)
        local res_str = int:hex()
        lu.assert_equals(res_str, exp_str)
    end
    
    apply_on_tuples(test_case)
end

function DISABLED_test_hex_lowercase()
    ---@param num integer
    ---@param int mpz
    local function test_case(num, int)
        local exp_str = ""
        if num < 0 then
            num = -num
            exp_str = "-"
        end
        exp_str = exp_str..string.format("%x", num)
        local res_str = int:hex_lowercase()
        lu.assert_equals(res_str, exp_str)
    end
    
    apply_on_tuples(test_case)
end

function DISABLED_test_oct()
    ---@param num integer
    ---@param int mpz
    local function test_case(num, int)
        local exp_str = ""
        if num < 0 then
            num = -num
            exp_str = "-"
        end
        exp_str = exp_str..string.format("%o", num)
        local res_str = int:oct()
        lu.assert_equals(res_str, exp_str)
    end
    
    apply_on_tuples(test_case)
end


__build_sorted_sequence_and_test_new_and_test_try_to_lua_int()

os.exit( lu.LuaUnit.run())
-- Never add any arguments to luaunit,
-- if it is expected, that the VS Code Lua Test Extensions,
-- correctly parse the test results.
-- Instead prefix the name of the test with "DISABLED__" .
