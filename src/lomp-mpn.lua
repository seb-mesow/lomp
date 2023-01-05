local msg = require("lua-only-mp-msg")
local mp_aux = require("lua-only-mp-aux")

-- mpn is the INTERNAL module for the implementation of the actual
-- arbitrary-precision arithmetic algorithms.
-- As the name suggests it only works with non-negative integers
-- ("natural integers").
-- Thus a using module of the mpn module
-- is responsible to maintain a sign for a number.

-- A natural integer is represented by a triple:
--     1. a table, which contains "limbs" at indices which are integers
--        - The table must contain limbs at the indices
--          from including the starting index upto excluding the end index
--        - The mpn module guarantees, that no other indices
--          are read or written in this table.
--        - The mpn module guarantees, that the metatable of the table
--          is not read or written.
--     2. a start index within the table, which points
--        to the least significant limb of the natural integer
--        - Mostly the startindex is 0.
--     3. an end index, which is the index of the most significant limb plus one
--        - In most cases the end index must be greater than the start index.
--        - If the natural integer is zero,
--          then the end index must equal the start index
--        - The end index must never be less than the start index
--        - Mostly the end index equals the count of limbs.
-- All these three values must be provided seperately.
-- But a using module can store the start and end indices
-- at string indices of the table.
-- (Note the guarantee on the table.)
-- 
-- By convention we may also refer to the least significant end of a range as 
-- the "right" end, and to the most significant end as the "left" end.
-- 
-- A natural integer is zero, if and only if the start and end index is equal.
-- A natural integer provied AS INPUT to a mpn function can not be zero.
-- But an mpn function can RETURN a natural integer which is zero.
--
-- The mpn module does not establish any further requirements
-- on the values of the limbs. Especially the most significant limb at the 
-- index length -1 and the lowest significant limb at the starting index
-- can be zero.
-- 
-- A natural integer as an input argument must always be
-- specified by a triple as above.
--
-- A natural integer as an output argument, which consists of the limbs
-- before the radix point (integer part), must always be specified by a pair
-- of the table to write in and a start index for the least significant limb to write.
-- (For an integer part the least significant limb is the limb directly before the radix point.)
-- The function then returns the corresponding end index,
-- which points directly before the most significant limb.
--
-- A natural "integer" as an output argument, which consists of the limbs
-- after the radix point (fractional part), must be specified either by a 
-- triple as above or by a pair. In both cases the table to write in and 
-- the end index, which points directly before the most significant limb
-- to write must be specified.
-- (For a fractional part the most significant limb is the limb directly after the radix point.)
-- In the case of a triple the difference between the end index and the start 
-- index specifies the count of fractionals limbs to compute.
-- In the case of a pair the function then returns the corresponding start 
-- index for the least significant, written limb

-- BEGIN DEBUG
local f = string.format

local function bin(int)
    return "(bin) "..mp_aux.binary_from_int(int)
end
-- END DEBUG

local mpn = {}

-- declaration of module-wide global vars

local HOST_WIDTH = mp_aux.host_width()
local HOST_NON_NEG_WIDTH = mp_aux.host_non_neg_width()

-- because 2^3 = 8 < 10 <= 2^4 = 16
-- This useful for efficient radix conversion to decimal and hexadecimal. 
local MIN_WIDTH = 4

-- The MAX_WIDTH is selected such, that multiplication is safe.
-- Multiplication is considered as that operation, which should be the fastest.
-- Thus the width is selected such,
-- that no overflow occurs during the multiplication algorithm,
-- and such, that at the multiplication algorithm
-- no spliting or dividing is necessary.
-- The maximum of this intermediate value is RADIX^2 - 1 .
-- The maximum value of a limb is RADIX - 1 .
-- The exact formula is MAX_WIDTH <! 1/2 * log_B(B^w +1) , where
-- B ... host digit radix (B := 2 for binary computers)
-- w ... number of digits USABLE FOR A NON-NEGATIVE INTEGERS
-- log_B .. the logarithm to base B
-- For binary computers this simplifies to WIDTH <!= w/2

local MAX_WIDTH = HOST_NON_NEG_WIDTH >> 1

-- BEGIN DEBUG
local function hex(num)
    return mp_aux.grouped_hex_from_int(
                num, DEBUG_STRING_LIMB_FORMAT_HEX_DIGITS_PER_LIMB)
end
-- END DEBUG

local DEFAULT_PURPOSE_STR = "__DEFAULT_PURPOSE__"

local WIDTH, RADIX, MOD_MASK, SUB_MASK, TWO_WIDTH_MASK,
      DEBUG_STRING_LIMB_FORMAT_BIN,
      DEBUG_STRING_LIMB_FORMAT_OCT, 
      DEBUG_STRING_LIMB_FORMAT_OCT_DIGITS_PER_LIMB,
      DEBUG_STRING_LIMB_FORMAT_DEC, 
      DEBUG_STRING_LIMB_FORMAT_DEC_DIGITS_PER_LIMB,
      DEBUG_STRING_LIMB_FORMAT_HEX, 
      DEBUG_STRING_LIMB_FORMAT_HEX_DIGITS_PER_LIMB,
      DIGITS_PER_LIMB_DEC, BIG_BASE_DEC

--- @package
--- @param width integer bits per limb
--- @param purpose_str string description, why to set the value
function mpn.__set_global_vars(width, purpose_str)
    -- BEGIN DEBUG
    if purpose_str ~= DEFAULT_PURPOSE_STR then
        msg.logf("Set the following values for global variables"
               .." for the purpose: \"%s\"", purpose_str)
    end
    -- END DEBUG
    
    WIDTH = width
    RADIX = 1 << WIDTH
    MOD_MASK = RADIX -1 -- sets all bits higher than the WIDTH-1. bit to zero
    
    -- When reading a two's complement representation
    -- as an unsigned resp. non-negative integer,
    -- then a NEGATIVE number x would be read
    -- as the unsigned resp. non-negative integer x plus W
    -- (with x < 0, thus x + W < W).
    -- (w ... FULL bit width of a signed or unsigned integer,
    --  W ... signed word radix, W := 2^(w-1) )
    -- Of course reading the two's complement representation of non-negative 
    -- integers as an unsigned integer yields the exact same integer.
    -- Thus reading the two's complement representation as an unsigned integer
    -- executes for us the following step:
    --     If the number is negative, then add W to it.
    --     Else leave the number as it is.
    -- Thus the read number is always non-negative.
    -- Fortunately this step is the crucial step
    -- in the schoolbook subtraction algorithm.
    
    SUB_MASK = (1 << (WIDTH + 1)) -1
    -- In the two's complement representation sets all bits higher
    -- than the WIDTH-th bit to zero.
    -- Reads the two's complement representation
    -- as an unsigned resp. non-negative integer
    -- Thus the carry/borrow bit is also kept.
    -- (The carry/borrow is either exactly 0 or exactly 1.)
    
    TWO_WIDTH_MASK = (1 << (WIDTH<<1)) -1
    -- Converts an integer x, with -2^(2w) <= x <= 2^(2w)-1,
    -- in two's complement representation of arbitrary width
    -- in its two's complement (= a non-negative integer) of width 2w
    
    -- to decimal radix conversion
    DIGITS_PER_LIMB_DEC = 0
    BIG_BASE_DEC = 10
    local big_base = BIG_BASE_DEC
    while big_base <= RADIX do
        BIG_BASE_DEC = big_base
        big_base = big_base *10
        -- DIGITS_PER_LIMB_DEC lags behind big_base by 1
        DIGITS_PER_LIMB_DEC = DIGITS_PER_LIMB_DEC +1
    end
    
    
    DEBUG_STRING_LIMB_FORMAT_OCT_DIGITS_PER_LIMB = math.ceil(WIDTH / 3)
    DEBUG_STRING_LIMB_FORMAT_OCT = 
        string.format("%%0%do", DEBUG_STRING_LIMB_FORMAT_OCT_DIGITS_PER_LIMB)
    
    DEBUG_STRING_LIMB_FORMAT_DEC_DIGITS_PER_LIMB =
        math.ceil(math.log(RADIX, 10))
    DEBUG_STRING_LIMB_FORMAT_DEC =
        string.format("%%0%dd", DEBUG_STRING_LIMB_FORMAT_DEC_DIGITS_PER_LIMB)
    
    DEBUG_STRING_LIMB_FORMAT_HEX_DIGITS_PER_LIMB = math.ceil(WIDTH / 4)
    DEBUG_STRING_LIMB_FORMAT_HEX =
        string.format("%%0%dX", DEBUG_STRING_LIMB_FORMAT_HEX_DIGITS_PER_LIMB)
    
    
    -- BEGIN DEBUG
    if purpose_str ~= DEFAULT_PURPOSE_STR then
        msg.logf("WIDTH == %d ; RADIX == 2^%d == %s == %d",
                 WIDTH, WIDTH, hex(RADIX), RADIX)
        msg.logf("MIN_WIDTH == %d ; MAX_WIDTH == %d", 
                 MIN_WIDTH, MAX_WIDTH)
        msg.logf("HOST_WIDTH = %d ; HOST_NON_NEG_WIDTH == %d", 
                 HOST_WIDTH, HOST_NON_NEG_WIDTH)
        
        msg.logf("MOD_MASK == %s", hex(MOD_MASK))
        msg.logf("SUB_MASK == %s", hex(SUB_MASK))
        msg.logf("TWO_WIDTH_MASK == %s", hex(TWO_WIDTH_MASK))
        
        msg.logf("RADIX - 1 == 2^%d - 1 == %s == %d",
                 WIDTH, hex(RADIX - 1), RADIX - 1)
        
        msg.logf("DEBUG_STRING_LIMB_FORMAT_OCT == %s",
                 mp_aux.sprint_value(DEBUG_STRING_LIMB_FORMAT_OCT))
        msg.logf("DEBUG_STRING_LIMB_FORMAT_DEC == %s",
                 mp_aux.sprint_value(DEBUG_STRING_LIMB_FORMAT_DEC))
        msg.logf("DEBUG_STRING_LIMB_FORMAT_HEX == %s",
                 mp_aux.sprint_value(DEBUG_STRING_LIMB_FORMAT_HEX))
                 
        msg.logf("DIGITS_PER_LIMB_DEC == %u", DIGITS_PER_LIMB_DEC)
        msg.logf("BIG_BASE_DEC == %u == %s", BIG_BASE_DEC, hex(BIG_BASE_DEC))
        msg.log("")-- newline
    end
    -- END DEBUG
end

-- BEGIN DEBUG
-- only for testing purposes
function mpn.__set_limb_width(width, purpose_str)
    assert(type(purpose_str) == "string", "argument purpose_str"
                                        .." is not a string")
    ---@type string
    local width_math_type = math.type(width)
    if width_math_type ~= "integer" then
        local width_type_str = type(width)
        if width_type_str == "number" then
            width_type_str = width_math_type
        end
        msg.errorf("%s provided as WIDTH,"
                 .." but WIDTH must be a positive integer", width_type_str)
        return 
    end
    if width < MIN_WIDTH then
        msg.errorf("%d provided as WIDTH,"
                 .." but WIDTH must be greater or equal MIN_WIDTH = %u.",
                   width, MIN_WIDTH)
        return
    elseif width > MAX_WIDTH then
        msg.errorf("%u provided as WIDTH,"
                 .." but WIDTH must be less or equal MAX_WIDTH = %u",
                   width, MAX_WIDTH)
        return
    end
    mpn.__set_global_vars(width, purpose_str)
end
-- END DEBUG

mpn.__set_global_vars(MAX_WIDTH, DEFAULT_PURPOSE_STR)

-- BEGIN DEBUG

--- returns the count of bits currently used for a limb
---@return integer limb_width count of bits per limb
function mpn.limb_width()
    return WIDTH
end

--- returns the radix of the positional number system the limbs currently represent
---@return integer limb_radix radix == 2^limb_width
function mpn.limb_radix()
    return RADIX
end

--- returns the count of hexadecimal digits needed to denotate any limb
---@return integer count_of_hex_digits_per_limb
function mpn.get_count_of_hex_digits_per_limb()
    return DEBUG_STRING_LIMB_FORMAT_HEX_DIGITS_PER_LIMB
end
-- END DEBUG

--- @package
--- 
--- checks whether the range {`t`, `i`, `e`} is valid:
--- - `t` must be a table.
--- - The start index `i` must be an integer.
--- - The end index `e` must be an integer.
--- - The end index `e` must be equal or greater than the starting index `i`.
--- - `t` must have an element at every index from including `i` to excluding `e`, which must be
---   - an integer
---   - non-negative
---   - less than the limb radix
---
---@param t integer[] range array
---@param i integer   range start index
---@param e integer   source end index
---
---@return boolean ok whether all requirements are met
function mpn.__is_valid(t, i, e)
    local ok = true
    local t_type = type(t)
    if not rawequal(t_type, "table") then
        msg.warnf("The provided argument for the natural integer's table"
                 .." is not a table.\nInstead it is a %s .", t_type)
        ok = false
    end
    local i_math_type = math.type(i)
    if not rawequal(i_math_type, "integer") then
        local i_type = i_math_type or type(i)
        msg.warnf("The provided argument for the natural integer's start index"
                 .." is not an integer.\nInstead it is a %s .", i_type)
        ok = false
    end
    local e_math_type = math.type(e)
    if not rawequal(e_math_type, "integer") then
        local e_type = e_math_type or type(e)
        msg.warnf("The provided argument for the natural integer's end index"
                 .." is not an integer.\nInstead it is a %s .", e_type)
        ok = false
    end
    if e < i then
        msg.warnf("The provided argument for the natural integer's end index"
                 .." is less than that for the start index."
                 .."\ni == %d, e == %d", i, e)
        ok = false
    end
    while i < e do
        local limb = t[i]
        if rawequal(limb, nil) then
            msg.warnf("The provided table misses the limb at index %d.", i)
            ok = false
        else
            local limb_math_type = math.type(limb)
            if rawequal(limb_math_type, "integer") then
                if limb < 0 then
                    msg.warnf("The integer at the index %d of the provided"
                             .." table is negative."
                             .."\ntable[%d] == %X (hex).", i, i, limb)
                    ok = false
                elseif limb >= RADIX then
                    msg.warnf("The integer at the index %d of the provided" 
                             .." table is greater than or equal"
                             .." to the RADIX %d."
                             .."\ntable[%d] == %X (hex).", i, i, limb)
                    ok = false
                end
            else
                local limb_type = limb_math_type or type(limb)
                msg.warnf("The value at the index %d of the provided table"
                         .." is not an integer."
                         .."\nInstead it is a %s .", limb_type)
                ok = false
            end
        end
        i = i +1
    end
    return ok
end

function mpn.assert_is_valid_input(t, i, e) -- source
    local ok = true
    if  math.type(i) == "integer"
    and math.type(e) == "integer"
    and e <= i then
        msg.warnf("The provided argument for the INPUTTED natural integer's" 
                 .." end index is less or equal than that of for the"
                 .." start index."
                 .."\ni==%d, e==%e"
                 .."\nNote that an INPUTTED natural integer must not be zero.",
                   i, e)
        ok = false
    end
    return mpn.__is_valid(t, i, e) and ok
end

-- for debugging
function mpn:__debug_string___limb_str_objs_comp(other)
    return self.k > other.k
end

--- works upto some degree also for invalid ranges
--- 
---@param t integer[] source array
---@param i integer   source start index
---@param e integer   source end index
---@param prefix string some kind of prefix before the formatted limbs
---@param format_func fun(limb: integer): string callback to format a limb
---
---@return string formatted_range
function mpn.__debug_string(t, i, e, -- source
                            prefix, format_func)
    local str = "i="..mp_aux.sprint_value(i)
              .." e="..mp_aux.sprint_value(e)
    if e == i then
        return str.." =^= 0"
    elseif e < i then
        return str.." =^= invalid"
    end
    -- collects each integer field
    local limb_str_objs = {}
    local temp_str
    for k, v in pairs(t) do
        if rawequal(math.type(k), "integer") and (k >= i) and (k < e) then
            temp_str = string.format(" [%d]=", k)
            if math.type(v) == "integer" then
                temp_str = temp_str..format_func(v)
            else
                temp_str = temp_str..mp_aux.sprint_value(v)
            end
            table.insert(limb_str_objs, { k = k ; s = temp_str })
        end
    end
    -- sort limb string objects by decreasing key
    table.sort(limb_str_objs, mpn.__debug_string___limb_str_objs_comp)
    -- print each limb in this sorted order
    temp_str = ""
    for _, limb_str_obj in ipairs(limb_str_objs) do
        temp_str = temp_str..limb_str_obj.s
    end
    if rawequal(temp_str, "") then
        temp_str = " no limbs at specified indices"
    else
        -- add prefix if at least one "limb"
        temp_str = " ("..prefix..")"..temp_str
    end
    return str..temp_str
end

local function DEBUG_STRING_FORMAT_LIMB_BIN(limb)
    local str = mp_aux.binary_from_int(limb)
    return string.rep("0", WIDTH-string.len(str))..str -- pad with zeros
end
local function DEBUG_STRING_FORMAT_LIMB_OCT(limb)
    return string.format(DEBUG_STRING_LIMB_FORMAT_OCT, limb)
end
local function DEBUG_STRING_FORMAT_LIMB_DEC(limb)
    return string.format(DEBUG_STRING_LIMB_FORMAT_DEC, limb)
end
local function DEBUG_STRING_FORMAT_LIMB_HEX(limb)
    return string.format(DEBUG_STRING_LIMB_FORMAT_HEX, limb)
end

function mpn.debug_string_bin(t, i, e)
    return mpn.__debug_string(t, i, e, "bin", DEBUG_STRING_FORMAT_LIMB_BIN)
end
function mpn.debug_string_oct(t, i, e)
    return mpn.__debug_string(t, i, e, "oct", DEBUG_STRING_FORMAT_LIMB_OCT)
end
function mpn.debug_string_dec(t, i, e)
    return mpn.__debug_string(t, i, e, "dec", DEBUG_STRING_FORMAT_LIMB_DEC)
end
function mpn.debug_string_hex(t, i, e)
    return mpn.__debug_string(t, i, e, "hex", DEBUG_STRING_FORMAT_LIMB_HEX)
end

--- converts a non-negative Lua Integer to a natural number
---
---@param t integer[] destination range array
---@param i integer   destination range start index
---@param int integer non-negative Lua integer
---
---@nodiscard
---@return integer de destination end index
function mpn.split_lua_int(t, i,
                           int)
    
    assert( math.type(int) == "integer",
           "argument must be a Lua integer"
         .." (neither a float nor something other)")
    assert( int >= 0, "Lua integer is negative" )
    local e = i
    while int ~= 0 do
        t[e] = int & MOD_MASK
        int = int >> WIDTH
        e = e +1
    end
    assert( mpn.__is_valid(t, i, e) )-- DEBUG
    return e
end

--- tries to convert a range into a (non-negative) Lua integer
--- The value of the range must less equal `math.maxinteger`
--- 
--- If the range is valid and its value is less equal `math.maxinteger`,
--- then the return value is a non-negative integer.<br>
--- If the range is valid and its value equals the absolute value of `math.mininteger`,
--- the the return value is `math.mininteger`, which is negative.<br>
--- Else the return value is `nil`
--- 
---@param t integer[] range array
---@param i integer   range start index
---@param e integer   range end index
---
---@nodiscard
---@return integer|nil lua_int Lua Integer or nil if the value does not fit in a Lua integer.
function mpn.try_to_lua_int(t, i, e)
    assert( mpn.__is_valid(t, i, e) )-- DEBUG
    
    if e <= i then
        return 0
    end
    
    local j = e
    
    -- omit leading zero limbs
    local first_non_zero_limb
    repeat
        j = j -1
        if j < i then
            return 0
        end
        first_non_zero_limb = t[j]
    until first_non_zero_limb > 0
    
    local free_bits = mp_aux.count_leading_zeros(
                            first_non_zero_limb, HOST_WIDTH)
    
    -- abs(math.mininteger) distugish itself from other x,
    -- where x >= 0 and clz(abs(math.mininteger) == clz(x),
    -- because abs(math.mininteger) is a power of two.
    -- thus if one limb is a power of two, and all other limbs are zero
    
    local only_zero_limbs = true
    local int = first_non_zero_limb
    local limb
    for j=e-2, i, -1 do
         -- msg.logf("j == %d", j)
        if free_bits < WIDTH then
            return -- return implicitly nil
        end
        limb = t[j]
        -- The following branch is needed to detect abs(math.mininteger)
        if limb > 0 then
            only_zero_limbs = false
        end
        int = (int << WIDTH) | limb -- consumes WIDTH more binary digits
        free_bits = free_bits - WIDTH
    end
    assert( free_bits >= 0 )-- DEBUG
    
    -- handle math.mininteger special
    if free_bits < 1 then
        if only_zero_limbs
        and ( rawequal( first_non_zero_limb & (first_non_zero_limb-1) , 0) ) 
        then -- see mp_aux.is_power_of_two()
            return math.mininteger
        end
        return -- return implicitly nil
    end
    
    assert( free_bits >= 1 )-- DEBUG
    assert( int >= 0 )-- DEBUG
    return int
end

-- copies a sequence of limbs from one table to another table
-- The natural integer can be zero.
-- returns the destination end index (for convenience)
function mpn.copy(dt, di, -- destination by start index
                  t, i, e) -- source
    assert( mpn.__is_valid(t, i, e) )-- DEBUG
    
    table.move(t, i, e-1, -- source
               di, dt) -- destination by start index
    
    assert( mpn.__is_valid(t, i, e) )-- DEBUG
    assert( mpn.__is_valid(dt, di, di+e-i) )-- DEBUG
    return di + e-i
end

-- compares two natural integers
-- The return values follow the convention of GNU MP's mpn_cmp()
-- if 1st/self <  2nd/other, returns -1
-- if 1st/self == 2nd/other, returns  0 
-- if 1st/self >  2nd/other, returns +1
-- Mnemonic: mpn.cmp() returns the sign of the directed difference of
--           the 1st range minus the 2nd range.
-- in contrast to GNU MP's mpn_cmp() the arguments can have different lengths.
---@param self_t integer[] "self" source range array
---@param self_i integer   "self" source range start index
---@param self_e integer   "self" source range end index
---@param other_t integer[] "other" source range array
---@param other_i integer   "other" source range start index
---@param other_e integer   "other" source range end index
---@return integer cmp_res sign of the directed difference "self" - "other"
function mpn.cmp( self_t,  self_i,  self_e, -- 1st source range
                 other_t, other_i, other_e) -- 2nd source range
    assert( mpn.__is_valid( self_t,  self_i,  self_e) )-- DEBUG
    assert( mpn.__is_valid(other_t, other_i, other_e) )-- DEBUG
    
    local  self_l =  self_e- self_i
    local other_l = other_e-other_i
    local common_l = math.min(self_l, other_l)
    -- search for first non-zero limb in the more significant limbs of the 
    -- longer range, which are additional with respect to the smaller range
    if self_l > other_l then
        -- e == 5, common_l == 3, i == 0 --> lower_end_index = 3
        local lower_end_index = self_i+common_l
        while self_e > lower_end_index do
            self_e = self_e -1
            if not rawequal(self_t[self_e], 0) then
                return 1
            end
        end
    else
        local lower_end_index = other_i+common_l
        while other_e > lower_end_index do
            other_e = other_e -1
            if not rawequal(other_t[other_e], 0) then
                return -1
            end
        end
    end
    assert(  self_e >=  self_i+common_l )-- DEBUG
    assert( other_e >= other_i+common_l )-- DEBUG
    -- determinate the first limb smaller or greater
    local self_limb, other_limb
    while self_e > self_i do
        self_e = self_e -1 ; other_e = other_e -1
        self_limb = self_t[self_e]
        other_limb = other_t[other_e]
        if self_limb < other_limb then
            return -1
        elseif self_limb > other_limb then
            return 1
        end
    end
    return 0
end

-- shifts a natural integer right by a certain count of binary digits
-- The right shift amount must be less than the limb width ("few")
-- writes the shifted copy to the destination
-- returns the end index of the destination natural integer (for convenience)
-- and a remainder.
-- The remainder are shifted out bits from the least significant end
-- The source and destination must not overlap! (currently)
function mpn.rshift_few_bounded(
        dt, di, -- destination by start index
        t, i, e, -- source
        crop_shift, -- right shift amount
        left_incoming_bits -- bits, that replace the away shifted bits
                           -- at the most significand end of dt
    )
    -- BEGIN DEBUG
    assert( math.type(crop_shift) == "integer" ,
            "right shift amount must be an integer")
    assert( crop_shift > 0 ,
            "right shift amount must be positive.")
    assert( crop_shift < WIDTH ,
            "right shift amount must be less than WIDTH.")
    assert( math.type(left_incoming_bits) == "integer" ,
            "left incoming bits must be an integer" )
    assert( left_incoming_bits >= 0 ,
            "left incoming bits must be non-negative")
    assert( (left_incoming_bits & MOD_MASK) == left_incoming_bits,
            f("left incoming bits should not have set bits beyond WIDTH"
            .."\nleft_incoming_bits == %s", bin(left_incoming_bits)) )
    assert( mpn.__is_valid(t, i, e) )
    -- END DEBUG
    
    local make_room_shift = WIDTH - crop_shift
    -- BEGIN DEBUG
    assert( (left_incoming_bits & ((1 << make_room_shift)-1)) == 0,
            f("left incoming bits must be restricted to the range"
            .." from excl. the WIDTH to incl. WIDTH - the right shift amount "
            .."\nleft_incoming_bits == %s", bin(left_incoming_bits)) )
    -- END DEBUG
    
    -- if e <= i then
    --     return di, left_incoming_bits
    -- end
    
    local de = di + e-i
    local saved_e = e -- DEBUG
    local saved_di = di -- DEBUG
    di = de
    while e > i do
        e = e -1 ; di = di -1
        dt[di] = ( left_incoming_bits | (t[e] >> crop_shift) ) & MOD_MASK
        left_incoming_bits = t[e] << make_room_shift
    end
    assert( di == saved_di )-- DEBUG
    assert( de-di == saved_e-i )-- DEBUG
    assert( mpn.__is_valid(dt, di, de) )-- DEBUG
    return de, left_incoming_bits & MOD_MASK
end

-- -- shifts a natural integer right by a certain count of binary digits
-- -- The right shift amount must be less than the limb width ("few")
-- -- writes the shifted copy to the destination
-- -- The return value is the start index of the shifted copy
-- -- The copy can be have one limb more than the argument ("unbounded").
-- -- The source and destination must not overlap! (currently)
function mpn.rshift_few_unbounded(
        dt, de, -- destination by end index
        t, i, e, -- source
        s, -- right shift amount
        left_incoming_bits -- bits, that replace the away shifted bits
                            -- at the most significant end of dt == de-1
    )
    -- BEGIN DEBUG
    assert( math.type(s) == "integer","left shift amount must be an integer")
    assert( s > 0 , "right shift amount must be positive.")
    assert( s < WIDTH , "right shift amount must be less than WIDTH.")
    assert( mpn.__is_valid(t, i, e) )
    -- END DEBUG
    
    local di = de - e+i
    local _de, rem_bits = mpn.rshift_few_bounded(
                                dt, di, -- destination by start index
                                t, i, e, -- source
                                s, -- right shift amount
                                left_incoming_bits)
    -- BEGIN DEBUG
    assert( _de == de , f("s == %d"
                        .."\nsource range == %s"
                        .."\nresult range == %s"
                        .."\n_de == %d ~= de == %d",
                          s,
                          mpn.debug_string_hex(t, i, e),
                          mpn.debug_string_hex(dt, di, _de),
                          _de, de) )
    -- END DEBUG
    di = di -1
    dt[di] = rem_bits
    assert( mpn.__is_valid(dt, di, de) )-- DEBUG
    return di
end

-- shifts a natural integer left by a certain count of binary digits
-- The left shift amount must be less than the limb width ("few")
-- writes the shifted copy to the destination
-- returns the end index of the destination natural integer (for convenience)
-- and a remainder.
-- The remainder is the shifted out bits from the most significant end.
-- The source and destination must not overlap! (currently)
function mpn.lshift_few_bounded(
        dt, di, -- destination
        t, i, e, -- source
        make_room_shift, -- left shift amount
        right_incoming_bits -- bits, that replace the away shifted bits
                            -- at the least significant end of dt
    )
    -- BEGIN DEBUG
    assert( math.type(make_room_shift) == "integer" ,
            "left shift amount must be an integer")
    assert( make_room_shift > 0 ,
            "left shift amount must be positive")
    assert( make_room_shift < WIDTH ,
            "left shift amount must be less than WIDTH")
    assert( math.type(right_incoming_bits) == "integer" ,
            "right incoming bits must be an integer" )
    assert( right_incoming_bits >= 0 ,
            "right incoming bits must be non-negative")
    assert( right_incoming_bits < (1 << make_room_shift) ,
            f("right incoming bits must be restricted to the range "
            .." upto excl. the left shift amount"
            .."\nright_incoming_bits == %s", bin(right_incoming_bits)) )
    assert( mpn.__is_valid(t, i, e) )
    -- END DEBUG
    
    local crop_shift = WIDTH - make_room_shift
    local saved_i = i -- DEBUG
    local saved_di = di -- DEBUG
    while i < e do
        dt[di] = ( (t[i] << make_room_shift) | right_incoming_bits ) & MOD_MASK
        right_incoming_bits = t[i] >> crop_shift
        i = i +1 ; di = di +1
    end
    
    assert( di-saved_di == e-saved_i )-- DEBUG
    assert( mpn.__is_valid(dt, saved_di, di) )-- DEBUG
    return di, right_incoming_bits
end

-- shifts a natural integer left by a certain count of binary digits
-- The left shift amount must be less than the limb width ("few")
-- writes the shifted copy to the destination
-- The return value is the end index of the shifted copy
-- The copy can be have one limb more than the argument ("unbounded").
-- The source and destination must not overlap! (currently)
function mpn.lshift_few_unbounded(
        dt, di, -- destination
        t, i, e, -- source
        s, -- left shift amount
        right_incoming_bits -- bits, that replace the away shifted bits
                            -- at the least significand end of dt
    )
    -- BEGIN DEBUG
    assert( math.type(s) == "integer","left shift amount must be an integer")
    assert( s > 0 , "left shift amount must be positive.")
    assert( s < WIDTH , "left shift amount must be less than WIDTH.")
    assert( mpn.__is_valid(t, i, e) )
    -- END DEBUG
    
    local de, rem_bits = mpn.lshift_few_bounded(
                                dt, di, -- destination by start index
                                t, i, e, -- source
                                s, -- left shift amount
                                right_incoming_bits)
    dt[de] = rem_bits
    de = de + 1
    assert( mpn.__is_valid(dt, di, de) )-- DEBUG
    return de
end

-- shifts a natural integer right by a certain count of binary digits
-- writes the more significant part of the shifted copy to the 1st destination
-- The 1st return value is the end index of that part
-- writes the less significant part of the shifted copy to the 2nd destination
-- The 2nd return value is the start index of that part
-- The source and destinations must not overlap! (currently)
function mpn.rshift_many_bounded(
        dt, di, -- destination for the integer part of the shifted copy
        ft, fe, -- destination for the fractional part of the shifted copy
        t, i, e, -- source
        crop_shift -- right shift amount
    )
    -- BEGIN DEBUG
    assert( math.type(crop_shift) == "integer",
            "right shift amount must be an integer")
    assert( crop_shift > 0 , "right shift amount must be positive.")
    assert( mpn.__is_valid(t, i, e) )
    msg.logf("source range == %s", mpn.debug_string_bin(t, i, e))
    msg.logf("input crop_shift == %d", crop_shift)
    -- END DEBUG
    
    if e <= i then
        return di, fe
    end
        
    -- Let ft_limbs_ratio be the /rational/ quotient of crop_shift by WIDTH
    -- Let ft_limbs be the /floored/ integer quotient of crop_shift by WIDTH
    -- Let extra be 1 if crop_shift > 0 and let extra be 0 if crop_shift == 0 .
    -- 
    -- The following inequalites for different indices hold:
    -- e >= i_split > i
    -- fe >= fi_first_zero_limb > fi
    -- de >= di
    -- l_ft >= partially_filled_limbs_of_ft > 1
    --
    -- If crop_shift == 0,
    -- then i_split points to the first limb, that still goes into dt.
    -- If crop_shift > 0,
    -- then i_split points to the limb, that goes partially into ft and dt.
    --
    -- Then
    -- i_split == min(i + floor(ft_limbs_ratio), e)
    --         == min(i + ft_limbs_trunc, e)
    -- l_ft == ceil(ft_limbs_ratio) == ft_limbs_trunc + extra
    -- fi == fe - l_ft == fe - ft_limbs_trunc - extra
    -- filled_limbs_of_dt == max(ceil(l_t - ft_limbs_ratio), 0)
    --                    == max(l_t + ceil(-ft_limbs_ratio), 0)
    --                    == max(l_t + (-ft_limbs_trunc), 0)
    --                    == max(l_t - ft_limbs_trunc, 0)
    -- de == di + filled_limbs_of_dt == di + max(l_t - ft_limbs_trunc, 0)
    --                               == max(di + l_t - ft_limbs_trunc, di)
    -- filled_limbs_of_ft == min(l_t + extra, l_ft)
    -- fi_first_zero_limb == min(fi + filled_limbs_of_ft, fe)
    --                    == min(fi + min(l_t + extra, l_ft), fe)
    --                    == min(min(fi + l_t + extra, fi + l_ft), fe)
    --                    == min(min(fi + l_t + extra, fe), fe)
    --                    == min(fi + l_t + extra, fe, fe)
    --                    == min(fi + l_t + extra, fe)
    --                    == min(fe - ft_limbs_trunc - extra + l_t + extra, fe)
    --                    == min(fe - ft_limbs_trunc + l_t, fe)
    --                    == min(fe + l_t-ft_limbs_trunc, fe)
    --                    == fe + min(l_t-ft_limbs_trunc, 0)
    --                    
    --                    == fi + filled_limbs_of_ft
    --                    == fi + min(l_t + extra, l_ft)
    --                    == min(fi + l_t + extra, fi + l_ft)
    --                    == min(fi + l_t + extra, fe)
    
    -- compute extra limbs and /necessary/ shift
    local ft_limbs_trunc = crop_shift // WIDTH
    crop_shift = crop_shift - ft_limbs_trunc*WIDTH
    local i_split = math.min(i + ft_limbs_trunc, e)
    local l_t__minus__ft_limbs_trunc = e-i - ft_limbs_trunc
    local de = di + math.max(l_t__minus__ft_limbs_trunc, 0)
    local fi = fe - ft_limbs_trunc ; if crop_shift > 0 then fi = fi -1 end
    local fi_first_zero_limb = fe + math.min(l_t__minus__ft_limbs_trunc, 0)
    
    local left_incoming_bits = 0
    
    -- BEGIN DEBUG
    msg.logf("working crop_shift == %d", crop_shift)
    msg.logf("i_split == %d", i_split)
    msg.logf("di == %d, de == %d", di, de)
    msg.logf("fi == %d, fi_first_zero_limb == %d, fe == %d",
             fi, fi_first_zero_limb, fe)
    -- END DEBUG
    
    -- There are 3 phases:
    -- 1. (homogen or heterogen) limbs into dt
    if i_split < e then
        if crop_shift > 0 then
            local _de -- DEBUG
            _de, left_incoming_bits =
                    mpn.rshift_few_bounded(
                            dt, di, -- destination by start index
                            t, i_split, e, -- source
                            crop_shift, -- left shift amount
                            0) -- left incoming bits
            -- BEGIN DEBUG
            assert( _de == de , f("crop_shift == %d"
                                .."\nsource range == %s"
                                .."\nresult range == %s"
                                .."\n_de == %d ~= de == %d",
                                  crop_shift,
                                  mpn.debug_string_hex(t, i_split, e),
                                  mpn.debug_string_hex(dt, di, _de),
                                  _de, de) )
            -- END DEBUG
        else
            assert( de == -- DEBUG
            mpn.copy(dt, di, -- destination by start index
                     t, i_split, e) -- source
            )-- DEBUG
        end
    end
    -- 2. pad /complete zero/ limbs in the more significant part of ft
    for fj = fe-1, fi_first_zero_limb, -1 do
        ft[fj] = 0
    end
    -- 3. (homogen or heterogen) limbs into ft
    if crop_shift > 0 then
        local _fi = -- DEBUG
        mpn.rshift_few_unbounded(
                ft, fi_first_zero_limb, -- destination by end index
                t, i, i_split, -- source
                crop_shift, -- left shift amount
                left_incoming_bits) -- left incoming bits
        -- BEGIN DEBUG
        assert( _fi == fi,
                f("_fi == %d ~= fi == %d", _fi, fi) )
        -- END DEBUG
    assert( mpn.__is_valid(ft, fi, fe) )-- DEBUG
    else
        local _fi_first_zero_limb = -- DEBUG
        mpn.copy(ft, fi, -- destination by start index
                 t, i, i_split) -- source
        -- BEGIN DEBUG
        assert( _fi_first_zero_limb == fi_first_zero_limb )
        -- END DEBUG
    end
    
    assert( mpn.__is_valid(dt, di, de) )-- DEBUG
    return de, fi
end

-- There is mpn.rshift_many_unbounded() function planned currently,
-- because that would mean, that it writes right of the provided start index. 
-- Or other: The function would must return a start index (= start index of the 
-- fractional part) and an end index (= end index of the integer part)

-- shifts a natural integer right by a certain count of binary digits
-- writes the more significant part of the shifted copy to the destination
-- The eturn value is the end index of that part
-- The less significant part of the shifted copy is discarded.
-- The source and destinations must not overlap! (currently)
function mpn.rshift_many_discard(
        dt, di, -- destination by start index
        t, i, e, -- source
        crop_shift -- right shift amount
    )
    -- BEGIN DEBUG
    assert( math.type(crop_shift) == "integer",
            "right shift amount must be an integer")
    assert( crop_shift > 0 , "right shift amount must be positive.")
    assert( mpn.__is_valid(t, i, e) )
    msg.logf("source range == %s", mpn.debug_string_bin(t, i, e))
    msg.logf("input crop_shift == %d", crop_shift)
    -- END DEBUG
    
    if e <= i then
        return di, fe
    end
    
    -- compute extra limbs and /necessary/ shift
    local ft_limbs_trunc = crop_shift // WIDTH
    crop_shift = crop_shift - ft_limbs_trunc*WIDTH
    local i_split = math.min(i + ft_limbs_trunc, e)
    local de = di + math.max(e-i - ft_limbs_trunc, 0)
    
    -- BEGIN DEBUG
    msg.logf("working crop_shift == %d", crop_shift)
    msg.logf("i_split == %d", i_split)
    msg.logf("di == %d, de == %d", di, de)
    -- END DEBUG
    
    -- There is 1 phase:
    -- 1. (homogen or heterogen) limbs into dt
    if i_split < e then
        if crop_shift > 0 then
            local _de = -- DEBUG
                    mpn.rshift_few_bounded(
                            dt, di, -- destination by start index
                            t, i_split, e, -- source
                            crop_shift, -- left shift amount
                            0) -- left incoming bits
            -- BEGIN DEBUG
            assert( _de == de , f("crop_shift == %d"
                                .."\nsource range == %s"
                                .."\nresult range == %s"
                                .."\n_de == %d ~= de == %d",
                                  crop_shift,
                                  mpn.debug_string_hex(t, i_split, e),
                                  mpn.debug_string_hex(dt, di, _de),
                                  _de, de) )
            -- END DEBUG
        else
            assert( de == -- DEBUG
            mpn.copy(dt, di, -- destination by start index
                     t, i_split, e) -- source
            )-- DEBUG
        end
    end
    
    assert( mpn.__is_valid(dt, di, de) )-- DEBUG
    return de
end

-- shifts a natural integer left by a certain count of binary digits
-- writes that part of the shifted copy of equal length to the 2nd destination
-- The 2nd return value is the end index of that part (for convenience)
-- writes the additional part of the shifted copy to the 1st destination
-- The 1st return value is the end index of that additional part
-- The source and destinations must not overlap! (currently)
function mpn.lshift_many_bounded(
        rt, ri, -- destination by start index for shifted out limbs/bits
        dt, di, -- destination by start index with length equal to source
        t, i, e, -- source
        make_room_shift -- left shift amount
    )
    -- BEGIN DEBUG
    assert( math.type(make_room_shift) == "integer",
            "left shift amount must be an integer")
    assert( make_room_shift > 0 , "left shift amount must be positive.")
    assert( mpn.__is_valid(t, i, e) )
    msg.logf("source range == %s", mpn.debug_string_bin(t, i, e))
    msg.logf("input make_room_shift == %d", make_room_shift)
    -- END DEBUG
    
    if e <= i then
        return ri, di
    end
    
    -- compute extra limbs and /necessary/ shift
    local complete_zero_limbs = make_room_shift // WIDTH
    make_room_shift = make_room_shift - complete_zero_limbs*WIDTH
    
    local de = di + e-i
    local re = ri + complete_zero_limbs
    if make_room_shift > 0 then
        re = re +1
    end
    -- If make_room_shift == 0,
    -- then i_split points after the last limb, that still goes into dt.
    -- If make_room_shift > 0,
    -- then i_split points to the limb after the limb,
    -- that goes partially into dt and rt.
    local i_split = math.max(e - complete_zero_limbs, i)
    
    -- BEGIN DEBUG
    msg.logf("complete_zero_limbs == %d", complete_zero_limbs)
    msg.logf("working make_room_shift == %d", make_room_shift)
    msg.logf("i_split == %d", i_split)
    msg.logf("ri == %d, re == %d", ri, re)
    msg.logf("di == %d, de == %d", di, de)
    -- END DEBUG
    
    local saved_di = di -- DEBUG
    local saved_ri = ri -- DEBUG
    local right_incoming_bits = 0
    
    -- There 4 phases:
    -- 1. pad zero limbs at dt from di upwards
    local complete_zero_limbs_j = 0
    while (di < de) and (complete_zero_limbs_j < complete_zero_limbs) do
        dt[di] = 0 ; di = di +1
        complete_zero_limbs_j = complete_zero_limbs_j +1 
    end
    -- 2. (homogen or heterogen) filled limbs for dt upto excluding de
    if di < de then
        if make_room_shift > 0 then
            local _de -- DEBUG
            _de, right_incoming_bits =
                    mpn.lshift_few_bounded(dt, di, -- destination by start index
                                           t, i, i_split, -- source
                                           make_room_shift, -- left shift amount
                                           0) -- right incoming bits
            assert( _de == de )-- DEBUG
        else
            assert( de == -- DEBUG
            mpn.copy(dt, di, --destination
                     t, i, i_split) -- source
            )-- DEBUG
        end
    end
    -- 3. pad zero limbs at rt from ri upwards
    while complete_zero_limbs_j < complete_zero_limbs do
        rt[ri] = 0 ; ri = ri +1
        complete_zero_limbs_j = complete_zero_limbs_j +1 
    end
    -- 4. (homogen or heterogen) filled limbs for rt upto excluding re
    if make_room_shift > 0 then
        local _re = -- DEBUG
        mpn.lshift_few_unbounded(rt, ri, -- destination by start index
                                 t, i_split, e, -- source
                                 make_room_shift, -- left shift amount
                                 right_incoming_bits)
        -- BEGIN DEBUG
        assert( _re == re, f("_re == %d ~= re == %d", _re, re) )
        -- END DEBUG
    else
        assert( re == -- DEBUG
        mpn.copy(rt, ri, -- destination by start index
                 t, i_split, e) -- source
        )-- DEBUG
    end
    
    assert( mpn.__is_valid(rt, saved_ri, re) )-- DEBUG
    assert( mpn.__is_valid(dt, saved_di, de) )-- DEBUG
    return re, de
end

-- shifts a natural integer left by a certain count of binary digits
-- and writes a shifted copy to the destination
-- The return value is the end index of the shifted copy
-- The source and destinations must not overlap! (currently)
function mpn.lshift_many_unbounded(
        dt, di, -- destination by start index
        t, i, e, -- source
        make_room_shift -- left shift amount
    )
    -- BEGIN DEBUG
    assert( math.type(make_room_shift) == "integer",
            "left shift amount must be an integer")
    assert( make_room_shift > 0 , "left shift amount must be positive.")
    assert( mpn.__is_valid(t, i, e) )
    -- END DEBUG
    local de
          , de_in_between-- DEBUG
            = mpn.lshift_many_bounded(
                    dt, di+e-i, -- destination by start index
                                -- for shifted out limbs/bits
                    dt, di, -- destination by start index,
                            -- length equal to source
                    t, i, e, -- source
                    make_room_shift) -- left shift amount
    -- BEGIN DEBUG
    assert( de_in_between == di+e-i )
    assert( mpn.__is_valid(dt, di, de_in_between) )
    assert( mpn.__is_valid(dt, de_in_between, de) )
    assert( mpn.__is_valid(dt, di, de) )
    -- END DEBUG
    return de
end

-- adds two ranges and writes the result range
-- The 1st source range must be longer than the 2nd source range
-- or equally long.
-- returns the end index, which is either di+se-si or di+se-si+1 .
-- The source ranges and the destination range must not overlap! (currently)
function mpn.add(dt, di, -- destination by start index
                 st, si, se, -- augend source "self"
                 ot, oi, oe, -- addend source "other"
                 carry) -- right incoming carry
    -- BEGIN DEBUG
    assert( (se-si) >= (oe-oi),
            "The 1st source range is shorter than the 2nd source range." )
    assert( mpn.__is_valid(st, si, se) )
    assert( mpn.__is_valid(ot, oi, oe) )
    assert( math.type(carry) == "integer",
            "incoming carry is not an integer" )
    assert( carry >= 0, "incoming carry is less than 0." )
    assert( carry <= 1, "incoming carry is greater than 1." )
    local saved_di = di
    local saved_si = si
    -- END DEBUG
    
    -- Lemma: The carry from two added limbs is either 0 or 1 and not more.
    -- Proof: B == RADIX. B >= 2. Maximium digits are B-1. B-1 + B-1 = 2B-2
    -- 2B-2 // B = floor((2B-2)/B) = floor(2 - 2/B) = 2 + floor(-(2/B))
    -- where 0 < 2/B <= 1 <==> -1 <= -(2/B) < 0
    -- Thus 2B-2 // B == 1 . (q.e.d)
    
    local temp
    -- common digits
    while oi < oe do -- note that oe is reached before
                     -- or at the same time as se
        temp = carry + st[si] + ot[oi]
        dt[di] = temp & MOD_MASK
        carry = temp >> WIDTH
        di = di +1 ; si = si +1 ; oi = oi +1
    end
    -- extra digits of self, while carry is positive
    while (carry > 0) and (si < se) do
        -- Altough this loop iterates only a few times,
        -- it could be multiple times for small WIDTH.
        temp = carry + st[si]
        dt[di] = temp & MOD_MASK
        carry = temp >> WIDTH
        di = di +1 ; si = si + 1
    end
    -- copy extra digits of self, because carry is 0
    -- and would also never again become 1
    while si < se do
        dt[di] = st[si]
        di = di +1 ; si = si + 1
    end
    -- if carry > 0 then
    --     -- if here carry > 0, then the last loop before was never executed
    --     -- possible "overflow" digit
    --     dt[di] = carry
    --     di = di +1
    -- end
    
    assert( (carry == 0) or (carry == 1) )-- DEBUG
    assert( (di-saved_di) == (si-saved_si) ) -- DEBUG
    assert( (di-saved_di) == (se-saved_si) ) -- DEBUG
    assert( mpn.__is_valid(dt, saved_di, di) )-- DEBUG
    return di, carry
end

--- subtracts the 2nd source range (subtrahend)
--- from the 1st source range (minuend)
--- and writes the result range (directed difference)
--- 
--- The 1st source range must be longer than the 2nd source range
--- or equally long.
--- 
--- If the natural integer represented by the 2nd source range is greater than 
--- those of the 1st source range, then the destination is given in the
--- RADIX-complement of the absolute difference (undirected difference). Then
--- and only then the outgoing borrow bit is 1.
--- 
--- The source ranges and the destination range must not overlap! (currently)
---
---@param dt integer[] destination range array
---@param di integer   destination range start index
---
---@param st integer[] self subtrahend source range array
---@param si integer   self subtrahend source range start index
---@param se integer   self subtrahend source range end index
---
---@param ot integer[] other minuend range array
---@param oi integer   other minuend range start index
---@param oe integer   other minuend range end index
---
---@param borrow integer right incoming borrow bit
---
---@nodiscard
---@return integer de destination range end index
---@return integer outgoing_borrow left outgoing borrow bit
function mpn.sub(dt, di,
                 st, si, se,
                 ot, oi, oe,
                 borrow)
    -- BEGIN DEBUG
    assert( (se-si) >= (oe-oi),
            "The 1st source range is smaller than the 2nd source range." )
    assert( mpn.__is_valid(st, si, se) )
    assert( mpn.__is_valid(ot, oi, oe) )
    assert( math.type(borrow) == "integer",
            "incoming borrow is not an integer" )
    assert( borrow >= 0, "incoming borrow is less than 0." )
    assert( borrow <= 1, "incoming borrow is greater than 1." )
    local saved_di = di
    local saved_si = si
    -- END DEBUG
    
    -- consider the minuend source range other padded with zero limbs
    -- at the most significand end with 
    
    -- only performs "positive normalisation":
    -- Every limbs must be non-negative. Else RADIX is added.
    
    local temp
    -- common digits
    while oi < oe do -- note that oe is reached before
                     -- or at the same time as se
        temp = ( st[si] - ( ot[oi] + borrow ) ) & SUB_MASK
        -- see mpn.__set_global_vars()
        dt[di] = temp & MOD_MASK
        borrow = temp >> WIDTH
        di = di +1 ; si = si +1 ; oi = oi +1
    end
    -- extra digits of self, until borrow is zero
    while (borrow > 0) and (si < se) do -- one if clause is not enough
        temp = ( st[si] - borrow ) & SUB_MASK
        dt[di] = temp & MOD_MASK
        borrow = temp >> WIDTH
        di = di +1 ; si = si +1
    end
    -- copy last extra digits of self, because borrow is zero
    while si < se do
        dt[di] = st[si]
        di = di +1 ; si = si +1
    end
    
    assert( (borrow == 0) or (borrow == 1) )-- DEBUG
    assert( (di-saved_di) == (si-saved_si) )-- DEBUG
    assert( (di-saved_di) == (se-saved_si) )-- DEBUG
    assert( mpn.__is_valid(dt, saved_di, di) )-- DEBUG
    return di, borrow
end

-- computes the absolute difference (undirected difference) between two ranges
-- The source ranges and the destination range must not overlap! (currently)
---
---@param dt integer[] destination range
---@param di integer   destination start index
---@param st integer[] self source range
---@param si integer   self source range start index
---@param se integer   self source range end index
---@param ot integer[] other source range
---@param oi integer   other source range start index
---@param oe integer   other source range end index
---
---@nodiscard
---@return integer de destination end index == di - se + si
---@return boolean is_negative whether 1st range - 2nd range is negative
function mpn.difference(dt, di,
                        st, si, se,
                        ot, oi, oe)

    local cmp_res = mpn.cmp(st, si, se, -- "self"  source range
                            ot, oi, oe) -- "other" source range
    if cmp_res > 0 then -- self > other
        local de, borrow -- DEBUG
                         = mpn.sub(dt, di, -- destination
                                   st, si, se, -- subtrahend "self"
                                   ot, oi, oe, -- minuend "other"
                                   0) -- right incoming borrow
        assert( borrow == 0 )-- DEBUG
        return de, false
    elseif cmp_res < 0 then -- self < other
        local de, borrow -- DEBUG
                         = mpn.sub(dt, di, -- destination
                                   ot, oi, oe, -- subtrahend "other"
                                   st, si, se, -- minuend "self"
                                   0) -- right incoming borrow
        assert( borrow == 0 )-- DEBUG
        return de, true
    else -- self == other
        return di, false
    end
end

-- multiplies the absolute values
-- If the product is zero, then it also sets the sign
-- Preconditions:
--     self:__is_valid()
--     other:__is_valid()
-- Postconditions:
--     if self.n < 1 then res:__is_valid_()
--     else               res:__is_valid_excl_sign()
function mpn:__mul_abs(other)
    if self.n < 1 or other.n < 1 then
        return Integer.ZERO()
    end
    
    assert( self.n > 0 )-- DEBUG
    assert( other.n > 0 )-- DEBUG
    
    local self_n, other_n = self.n, other.n
    local res_n = self_n + other_n -1
    
    local res = setmetatable({}, __Integer_meta)
    
    -- obvious implementation of schoolbook algorithm:
    -- self is the "multiplicand". other is the "multiplier".
    
    -- fill with zeros
    for i = 0, res_n do
        res[i] = 0
    end
    -- Imagine the limbs of the multiplicand self written at the top in a row.
    -- The significance of the limbs of self increases to the left. 
    -- Imagine the limbs of the multiplier other written right in a column. 
    -- The significance of the limbs of other increases downwards.
    -- Imagine the limbs of the product res written at the bottom in a row.
    -- The significance of the limbs of res increases to the left.
    -- The algorithm can be described as:
    --   - compute a "product row". These are all limbs of self multiplied with a the fixed limb of other in that row.
    --   - shift the product row as j times to the left, where j is the index of the fixed limb of other
    --   - add each such "product row" to the product so far.
    --   - assign the "surplus" carry from the computation of the "product row" to an extra limb
    -- The computation of a product row and adding this to the product so far is done synchronous:
    --   1. add the carry to                                      (the previous value of) the appropriate limb of the product
    --   2. add the product of the (next) limb of self with the fixed limb of other to    the appropriate limb of the product
    --   3. compute the new carry from                                                    the appropriate limb of the product
    --   4. compute the new value of the appropriate limb of the product from             the appropriate limb of the product
    for j = 0, other_n-1 do -- for each product row ...
        local carry = 0
        local other_j = other[j]
        for i = 0, self_n-1 do -- ... process all limbs of self
            local index = i+j
            local temp = res[index] + carry + self[i] * other_j
            -- This is the formula, which must fit into a Lua integer
            -- >>>> This formula thus induces the upperbound for WIDTH and RADIX. <<<<
            -- res[index], self[i] and other_j are bounded by RADIX-1 =: L =: 2^l -1
            -- We define W =: 2^w -1 as the RADIX of for positive Integer.
            -- Thus W = math.maxinteger+1
            -- The developer has deduced, that for the limb radix L the following inequality must hold:
            --     L^2 -1 < W   resp.   2^(2l) < 2^w +1
            -- Thus:
            --     l <= w/2
            -- For w = 31 we get l = 15. For w = 63 we get l = 31
            res[index] = temp & MOD_MASK
            carry = temp >> WIDTH
        end
        res[j+self_n] = carry
    end
    
    -- minimize result:
    if res[res_n] == 0 then
        res[res_n] = nil
        res.n = res_n
    else
        res.n = res_n + 1
    end
    
    assert(res:__is_valid_excl_sign())-- DEBUG
    return res
end

-- divides the absolute values |self| / |other|
-- In contrast to the Lua specification it rounds to zero (and not towards minus infinity)
-- Preconditions:
--     self:__is_valid()
--     other:__is_valid()
--     other.n == 1
--     self.n >= 1
--     |self| > |other|
-- Postconditions:
--     res:__is_valid_excl_sign()
--
-- This is the simple division algorithm tought in elementary schools
function mpn:__div_abs___single_limb(other)
    --msg.logf("single-limb division")--DEBUG
    assert(other.n == 1)--DEBUG
    assert(self.n >= 1)--DEBUG
    assert(Integer.__compare_abs(self, other) == 1)--DEBUG
    
    local q = setmetatable({}, __Integer_meta)
    local q_n = self.n
    
    local d = other[0]
    local r = 0 -- pad dividend with an extra zero
    local temp, q_i
    local i = q_n
    repeat
        i = i -1
        temp = (r << WIDTH) | self[i]
        q_i = temp // d
        --msg.logf("0x%04X << + 0x%04X / 0x%04X == 0x%04X, remainder == 0x%04X",--DEBUG
        --         r, self[i], d, q_i, temp-q_i*d)--DEBUG
        r = temp - q_i*d-- hopefully a bit faster than temp % d
        q[i] = q_i
    until i == 0
    
    -- Minimize quotient
    -- Because of the precondition |self| > |other|, we can assume, that
    -- the quotient is at least 1, und thus we have at least one non-zero limb.
    i = self.n - 1
    while q[i] == 0 do
        q[i] = nil
        i = i -1
    end
    q.n = i + 1
    
    assert(q:__is_valid_excl_sign())-- DEBUG
    return q
end

-- divides the absolute values |self| / |other|
-- In contrast to the Lua specification it rounds to zero (and not towards minus infinity)
-- Preconditions:
--     self:__is_valid()
--     other:__is_valid()
--     other.n > 1
--     self.n >= other.n
--     |self| > |other|
-- Postconditions:
--     res:__is_valid_excl_sign()
--
-- We implement the Algorithm D from
-- Donald E. Knuth:
-- The Art of Computer Programming
-- Volume 2 / Seminumerical Algorithms
-- Third Edition
-- see section 4.3. Multiple-Precision Arithmetic
-- 
-- also see Stefan Kanthak's Webseite
-- https://skanthak.homepage.t-online.de/division.html
-- 
-- Thus see also
-- Henry S. Warren, Jr:
-- Hacker’s Delight
-- Second Edition
function mpn:__div_abs___algo_d(other)
    --msg.logf("division with Algorithm D")--DEBUG
    assert(other.n > 1)--DEBUG
    assert(self.n >= other.n)--DEBUG
    assert(Integer.__compare_abs(self, other) == 1)--DEBUG
    
    local c_n = self.n -- actually the dividend has one more limb
    local d_n = other.n
    local i, j
    
    -- D1: copy and normalize arguments
    -- divisor[n-1] must be >= floor(RADIX/2) == 2^(WIDTH-1)
    local c = {} -- at the end c is the remainder
    local d = {}
        
    local make_room_shift = Integer.__count_leading_zeros(other[d_n-1], WIDTH)
    --msg.logf("make_room_shift == %d", make_room_shift)--DEBUG
    
    -- We can expect here, that c_n, d_n >= 1 .
    if make_room_shift == 0 then
        -- copy dividend
        i = c_n
        c[c_n] = 0
        repeat
            i = i -1
            c[i] = self[i]
        until i == 0
        -- copy divisor
        i = d_n
        repeat
            i = i -1
            d[i] = other[i]
        until i == 0
    else
        local crop_shift = WIDTH - make_room_shift
        -- shift dividend
        i = c_n -1
        j = self[i] >> crop_shift
        c[c_n] = j
        while i ~= 0 do
            j = i - 1
            c[i] = ( (self[i] << make_room_shift) | (self[j] >> crop_shift) ) & MOD_MASK
            i = j
        end
        c[0] = ( self[0] << make_room_shift ) & MOD_MASK
        -- shift divisor
        i = d_n -1
        while i ~= 0 do
            j = i - 1
            d[i] = ( (other[i] << make_room_shift) | (other[j] >> crop_shift) ) & MOD_MASK
            i = j
        end
        d[0] = ( other[0] << make_room_shift ) & MOD_MASK
    end
    -- BEGIN DEBUG
    -- c.n = c_n+1
    -- d.n = d_n
    -- msg.logf("unnormalized dividend self  == %s", Integer.debug_string(self))
    -- msg.logf("  normalized dividend c     == %s", Integer.debug_string(c))
    -- msg.logf("unnormalized divisor  other == %s", Integer.debug_string(other))
    -- msg.logf("  normalized divisor  d     == %s", Integer.debug_string(d))
    -- END DEBUG
    
    assert( d[d_n-1] >= (RADIX // 2) )-- DEBUG
    
    -- initialize quotient
    local q = setmetatable({}, __Integer_meta)
    
    -- main loop
    local qhat, rhat, carry, index, temp, d_i_qhat
    local d_1msl = d[d_n-1] -- most significant limb of divisor
    local d_2msl = d[d_n-2] -- 2nd most significant limb of divisor
    -- D2: initialize j (the loop counter) 
    local q_n = c_n-d_n+1
    assert(q_n > 0)--DEBUG
    j = q_n
    -- indices for 1st, 2nd, 3rd most significant limb of dividend for current iteration
    local c_1msl_index
    local c_2msl_index = c_n
    local c_3msl_index = c_2msl_index-1
    --msg.logf("d_1msl = 0x%04X, d_2msl = 0x%04X", d_1msl, d_2msl)--DEBUG
    --msg.logf("c_n = %d, d_n = %d, q_n = %d", c_n, d_n, q_n)--DEBUG
    repeat
        j = j -1
        --msg.logf("j = %d", j)--DEBUG
        c_1msl_index = c_2msl_index
        c_2msl_index = c_3msl_index
        c_3msl_index = c_3msl_index -1
        --msg.logf("c_1msl = 0x%04X, c_2msl = 0x%04X, c_3msl = 0x%04X", --DEBUG
        --         c[c_1msl_index], c[c_2msl_index], c[c_3msl_index])   --DEBUG
        -- D3: calculate qhat
        temp = (c[c_1msl_index] << WIDTH) | c[c_2msl_index]
        qhat = temp // d_1msl
        -- needs extra CPU division: rhat = temp % d_1msl
        rhat = temp - qhat*d_1msl-- hopefully a bit faster
        --msg.logf("qhat = %s (before adjustment)", hex(qhat))--DEBUG
        assert(qhat < RADIX +2)--DEBUG qhat <!= RADIX-1 +2
        local adjustment_count = 0--DEBUG
        repeat
            -- BEGIN DEBUG
            if adjustment_count > 2 then
                msg.error("Tried to adjust qhat and rhat a 3rd time."
                      .."\nBut according to Donald E. Knuth"
                        .." at maximum 2 adjustments are expected.")
            end
            -- END DEBUG
            if qhat >= RADIX or qhat*d_2msl > RADIX*rhat + c[c_3msl_index] then
                --msg.logf("")--DEBUG
                --msg.logf("adjust qhat 0x%04X --> 0x%04X", qhat, qhat-1)--DEBUG
                --msg.logf("adjust rhat 0x%04X --> 0x%04X", rhat, rhat+d_1msl)--DEBUG
                qhat = qhat -1
                rhat = rhat + d_1msl
                if rhat >= RADIX then
                    break
                end
            else
                break
            end
            adjustment_count = adjustment_count +1--DEBUG
        until false
        --msg.logf("qhat = %s (after final adjustment)", hex(qhat))--DEBUG
        -- D4: multiply and subtract
        -- Algorithm to multiply D := D * qhat
        --     i = 0 ; carry_mul = 0
        --     repeat
        --         temp_mul = d[i] * qhat + carry_mul
        --         d[i] = temp_mul & MOD_MASK ; carry_mul = temp_mul >> WIDTH
        --         i = i +1
        --     until i == d_n
        --     if carry_mul ~= 0 then
        --         d[d_n] = carry_mul ; d_n = d_n +1
        --     end
        -- Subtraction Algorithm C := C - D with c_n == d_n
        --     i = 0 ; carry_sub = 0
        --     repeat
        --         temp_sub = ( c[i] - d[i] - carry_sub ) & SUB_MASK
        --         c[i] = temp_sub & MOD_MASK ; carry_sub = temp_sub >> WIDTH
        --     until i == c_n
        --     if carry_sub ~= 0 then
        --         c[c_n] = carry_sub ; c_n = c_n + 1 -- C is negative
        --     end
        carry = 0
        i = 0
        repeat
            index = j+i
            d_i_qhat = d[i] * qhat
            temp = ( c[index] - ( (d_i_qhat & MOD_MASK) + carry ) ) & TWO_WIDTH_MASK
            c[index] = temp & MOD_MASK
            carry = ( (d_i_qhat >> WIDTH) - (temp >> WIDTH) ) & MOD_MASK
            -- I can not 100% strict proof, why the carry is a difference.
            -- But multiple reasons support this.
            i = i +1
        until i == d_n
        index = j+i
        temp = c[index] - carry
        c[index] = temp & MOD_MASK
        -- D5: Test remainder
        if temp < 0 then -- if subtracted to much
            carry = 0 -- then add back the divisor once
            i = 0
            repeat
                index = j+i
                temp = c[index] + d[i] + carry
                c[index] = temp & MOD_MASK
                carry = temp >> WIDTH
                i = i +1
            until i == d_n
            index = j+i
            c[index] = c[index] + carry
            q[j] = qhat - 1
        else
            q[j] = qhat
        end
    until j == 0 -- D7: loop on j (end main loop)
    -- D8: Unnormalize (the remainder)
    -- We do not need it
    
    -- Minimize quotient
    assert(q_n > 0)
    -- Because of the precondition |self| > |other, we can assume, that
    -- the quotient is at least 1, und thus we have at least one non-zero limb.
    i = q_n - 1
    while q[i] == 0 do
        q[i] = nil
        i = i -1
    end
    q.n = i + 1
    
    assert(q:__is_valid_excl_sign())-- DEBUG
    return q
end

-- divides the absolute values |self| / |other|
-- If the quotient is zero, then it also sets the sign
-- In contrast to the Lua specification it rounds to zero (and not towards minus infinity)
-- Preconditions:
--     self:__is_valid()
--     other:__is_valid()
-- Postconditions:
--     if self.n < 1 then res:__is_valid_()
--     else               res:__is_valid_excl_sign()
function mpn:__div_abs(other)
    if other.n < 1 then
        msg.error("Tried to divide by zero.")
        return
    end
    if self.n < 1 then
        --msg.logf("divide zero by non-zero --> quotient = 0")
        return Integer.ZERO()
    end
    
    assert( self.n > 0 )-- DEBUG
    assert( other.n > 0 )-- DEBUG
    local compare = Integer.__compare_abs(self, other)
    if compare == -1 then -- |self| < |other|
        --msg.log("divide an absolute smaller number by an abolsute bigger number"-- DEBUG
        --      .." --> quotient = 0")-- DEBUG
        return Integer.ZERO()
    elseif compare == 0 then -- |self| == |other|
        --msg.log("divide a number by an absolute equal number --> |quotient| = 1")-- DEBUG
        return Integer.ABS_ONE()
    else -- |self| > |other|
        if other.n == 1 then
            return Integer.__div_abs___single_limb(self, other)
        else
            return Integer.__div_abs___algo_d(self, other)
        end       
    end
end

-- square root
--
-- We implement the recursive Karatsuba Square Root Algorithm by Paul Zimmermann
-- as described in the following two papers:
-- https://hal.inria.fr/inria-00072854/document
-- https://hal.inria.fr/inria-00072113/document 
-- 
-- Preconditions:
--     self:__is_valid()
-- Postconditions:
--     res:__is_valid()
function mpn:__sqrt_abs_impl__OLD()
    local c_n = self.n -- actually the dividend has one more limb
    
    if c_n == 1 then
        -- msg.logf("base case self.n == 1")-- DEBUG
        return { [0] = math.floor(math.sqrt( self[0] )) ; n = 1 }    
    elseif c_n == 2 then
        -- msg.logf("base case self.n == 2")-- DEBUG
        return { [0] = math.floor(math.sqrt( (self[1] << WIDTH) | self[0] )) ; n = 1 }    
    end
    
    -- New implementation of the spliting and normalization subroutine
    -- The task is to split an Integer C into 3 parts:
    --   - a higher part D2 consisting of the highest half of the limbs
    --   - a lower middle part D1 consisiting of the second lowest quarter of the limbs
    --   - a lower part D0 consisting of the first lowest quarter of the limbs
    
    -- compute padding, such that a padded C can be split in 4 quarters of equal length.
    local r = c_n % 4
    local p, d_n_m1 -- padding, d_n minus 1
    if r == 0 then
        p = 0 ; d_n_m1 = (c_n // 4) -1
    else
        p = 4 - r ; d_n_m1 = c_n // 4
    end
    msg.logf("p == %d, d_n_m1 == %d", p, d_n_m1)-- DEBUG
    
    -- pad D's with zero limbs
    local D = { [0] = {} ; {} ; {} } -- D[0], D[1], D[2]
    local i = 0 -- index over limbs of C
    local j = 0 -- index over the limbs of D0, D1, D2 resp. Dk
    local k = 0 -- index of the part, 0, 1, 2
    local Dk = D[k] -- quarters D0 and D1, and the half D2
    while i < p do
        Dk[j] = 0
        if j == d_n_m1 then
            if k == 1 then
                d_n_m1 = (d_n_m1 << 1) +1 -- to d_n_m1 add d_n 
                msg.logf("d_n_m1 := %d (1)", d_n_m1)-- DEBUG
            end
            assert( k < 2 )-- DEBUG
            j = 0
            k = k +1 ; Dk = D[k]
        else
            j = j +1
        end
        i = i +1
    end
    
    -- compute shift
    local make_room_shift = Integer.__count_leading_zeros(self[c_n-1], WIDTH)
    
    i = 0
    if make_room_shift == 0 or make_room_shift == 1 then
        -- only coping
        msg.logf("only coping, because make_room_shift == %d", make_room_shift)--DEBUG
        repeat
            Dk[j] = self[i]
            if j == d_n_m1 then
                if k == 1 then
                    d_n_m1 = (d_n_m1 << 1) +1 -- to d_n_m1 add d_n 
                    msg.logf("d_n_m1 := %d (2)", d_n_m1)
                end
                if k == 2 then
                    break
                else
                    j = 0
                end
                k = k +1 ; Dk = D[k]
            else
                j = j +1
            end
            i = i +1
        until false
    else
        -- coping and shifting
        msg.logf("coping and shifting,"-- DEBUG
               .." because make_room_shift == %d", make_room_shift)-- DEBUG
        local crop_shift = WIDTH - make_room_shift
        r = 0 -- remaining lower bits of lower significant neighboring limb
        -- continue with current values of j, d_n_m1, k, Dk
        repeat
            Dk[j] = ((self[i] << make_room_shift) & MOD_MASK) | r
            if j == d_n_m1 then
                if k == 1 then
                    d_n_m1 = (d_n_m1 << 1) +1 -- to d_n_m1 add d_n 
                    msg.logf("d_n_m1 := %d (3)", d_n_m1)
                end
                if k == 2 then
                    break
                else
                    j = 0
                end
                k = k +1 ; Dk = D[k]
            else
                j = j +1
            end
            r = (self[i] >> crop_shift) & MOD_MASK
            i = i +1
        until false
    end
    assert( i == (c_n - 1) )
    -- BEGIN DEBUG
    d_n_m1 = d_n_m1 >> 1
    D[0].n = d_n_m1 + 1
    D[1].n = d_n_m1 + 1
    D[2].n = (d_n_m1 << 1) + 2
    msg.logf("self.n == %d", c_n)
    msg.logf("unnormalized argument self == %s", Integer.debug_string_bin(self) )
    msg.logf("normalized second half D[2] == %s", Integer.debug_string_bin(D[2]) )
    msg.logf("normalized second quarter D[1] == %s", Integer.debug_string_bin(D[1]) )
    msg.logf("normalized first quarter D[0] == %s", Integer.debug_string_bin(D[0]) )
    msg.logf("d_n == %d", d_n_m1 + 1 )
    -- END DEBUG
    assert( (4*(d_n_m1 + 1) % 2) == 0)-- DEBUG
    assert( D[2][(d_n_m1 << 1) + 1] >= (RADIX // 4) )-- DEBUG
    
    -- initialize root and remainder
    local S = {}
    
    return S
end

-- function mpn:__sqrt_abs_impl()
--     local mem
--     local clz = Integer.__count_of_leading_zeros(self[self.n], WIDTH)
--     if clz > 1 then
--         mem = Integer.lshift(self, )
--     else
--         mem = Integer.copy(self) 
--     end
-- end

function mpn:__sqrt_abs()
    if self.n < 1 then
        return Integer.ZERO()
    end
    local res = setmetatable(
                    Integer.__sqrt_abs_impl(self),
                    __Integer_meta)
    res.s = false
    --assert(res:__is_valid())-- DEBUG
    return res
end

local DIGITS_UPPERCASE = {
    [0] = "0";"1";"2";"3";"4";"5";"6";"7";"8";"9";"A";"B";"C";"D";"E";"F"}
local DIGITS_LOWERCASE = {
    [0] = "0";"1";"2";"3";"4";"5";"6";"7";"8";"9";"a";"b";"c";"d";"e";"f"}

-- converts an Integer to a decimal string
function mpn:dec()
    if self.n == 0 then
        return "0"
    end
    
    -- adapted from the GMP source file
    -- mpn/generic/get_str.c - function mpn_bc_get_str - branch /* not base 10 */
    
    local str = ""
    local y = Integer.__copy_abs(self)
    local y_n = y.n
    local r, i, temp, y_i, step_str
    repeat
        r = 0
        i = y_n
        repeat
            i = i -1
            -- We considered, to replace plain division
            -- by multiplication by a magic constant and right shifting.
            -- But because for Nx1 single limb division be require a 2x1 division.
            -- Considering the replacement of such a 2x1 division, it turned out,
            -- that intermediate value would overflow.
            -- Thus we would need to split the magic constant.
            -- This would add a significant number of operations.
            -- We think that this extra operations overturn the execution time
            -- of a plain divison.
            temp = (r << WIDTH) | y[i]
            y_i = temp // BIG_BASE_DEC
            r = temp - BIG_BASE_DEC*y_i
            y[i] = y_i
        until i == 0
        -- one additional fractional limb
        r = ( (r << WIDTH) // BIG_BASE_DEC ) + 1
        -- extract digits
        i = DIGITS_PER_LIMB_DEC
        step_str = ""
        repeat
            i = i -1
            -- The expression temp = (r << 3) + (r << 1) = 8*r + 2*r
            -- seems not perfrom better in Lua .
            temp = r * 10
            r = temp & MOD_MASK
            step_str = step_str..DIGITS_UPPERCASE[temp >> WIDTH]
        until i == 0
        -- prepend string
        str = step_str..str
        -- minimze y
        if y[y_n-1] == 0 then
            y[y_n-1] = nil-- DEBUG
            y_n = y_n -1
        end
        y.n = y_n-- DEBUG
        assert( y:__is_valid_excl_sign() )--DEBUG
    until y_n == 0
    
    -- sign and remove leading zeros
    temp = string.find(str, "[^0]")
    return (self.s and "-" or "")..string.sub(str, temp)
end

-- converts an Integer to a decimal string
function mpn.__str_in_pow_of_2_radix(self, bits_per_digit, digit_mask, digits)
    local self_n = self.n
    if self_n == 0 then
        return "0"
    end
    
    -- The algorithm was more or less copied from the GMP source file
    -- mpn/generic/get_str.c - function mpn_get_str - branch if (POW2_P (base))
    
    local i = self_n - 1
    local self_i = self[i]
    
    -- in this block imagine the following identifiers:
    -- lower_bit_index == bits
    -- digit_val == remainder
    local lower_bit_index =
        self_n*WIDTH - Integer.__count_leading_zeros(self_i, WIDTH)
    -- adjust, such that bits is a multiple of bits_per_digit
    -- greater (and not equal) to the overall number of bits.
    local digit_val = lower_bit_index % bits_per_digit
    if digit_val ~= 0 then
        lower_bit_index = lower_bit_index + bits_per_digit - digit_val
    end
    
    local lower_bit_index = lower_bit_index - (self_n-1)*WIDTH
    local str = ""
    repeat
        lower_bit_index = lower_bit_index - bits_per_digit
        while lower_bit_index >= 0 do
            str = str..digits[(self_i >> lower_bit_index) & digit_mask]
            lower_bit_index = lower_bit_index - bits_per_digit
        end
        if i == 0 then
            break
        end
        -- extract last bits from self[i] and shift them right to make room
        -- We do this by first making room (thus actually a left shift)
        -- for the next bits and then croping to the bits for one digit
        digit_val = (self_i >> lower_bit_index) & digit_mask
        i = i -1
        self_i = self[i]
        lower_bit_index = lower_bit_index + WIDTH
        digit_val = digit_val | ((self_i >> lower_bit_index) & digit_mask)
        str = str..digits[digit_val]
    until false
    
    return (self.s and "-" or "")..str
end

function mpn:hex()
    return mpn.__str_in_pow_of_2_radix(self, 4, 0xF, DIGITS_UPPERCASE)
end

function mpn:hex_lowercase()
    return mpn.__str_in_pow_of_2_radix(self, 4, 0xF, DIGITS_LOWERCASE)
end

function mpn:oct()
    return mpn.__str_in_pow_of_2_radix(self, 3, 7, DIGITS_UPPERCASE)
end

return mpn