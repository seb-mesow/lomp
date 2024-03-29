local msg = require("lomp-msg")
local err_msg = require("lomp-err_msg")
local aux = require("lomp-aux")

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
-- If a process like reading and writing happens "rightwards",
-- then at first the more significant limbs and at last the less significant limbs are considered.
-- If a process like reading and writing happens "leftwards",
-- then at first the less significant limbs and at last the more significant limbs are considered.
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
    return "(bin) "..aux.binary_from_int(int)
end
-- END DEBUG

local mpn = {}

-- declaration of module-wide global vars

local HOST_WIDTH = aux.host_width()
local HOST_NON_NEG_WIDTH = aux.host_non_neg_width()

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
    return aux.grouped_hex_from_int(
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
--- @param width integer count of bits per limb
--- @param purpose_str string description, why to set the value
function mpn.__set_global_vars(width, purpose_str)
    -- BEGIN DEBUG
    -- if purpose_str ~= DEFAULT_PURPOSE_STR then
    --     msg.logf("Set the following values for global variables"
    --            .." for the purpose: \"%s\"", purpose_str)
    -- end
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
    -- if purpose_str ~= DEFAULT_PURPOSE_STR then
    --     msg.logf("WIDTH == %d ; RADIX == 2^%d == %s == %d",
    --              WIDTH, WIDTH, hex(RADIX), RADIX)
    --     msg.logf("MIN_WIDTH == %d ; MAX_WIDTH == %d", 
    --              MIN_WIDTH, MAX_WIDTH)
    --     msg.logf("HOST_WIDTH = %d ; HOST_NON_NEG_WIDTH == %d", 
    --              HOST_WIDTH, HOST_NON_NEG_WIDTH)
    --     
    --     msg.logf("MOD_MASK == %s", hex(MOD_MASK))
    --     msg.logf("SUB_MASK == %s", hex(SUB_MASK))
    --     msg.logf("TWO_WIDTH_MASK == %s", hex(TWO_WIDTH_MASK))
    --     
    --     msg.logf("RADIX - 1 == 2^%d - 1 == %s == %d",
    --              WIDTH, hex(RADIX - 1), RADIX - 1)
    --     
    --     msg.logf("DEBUG_STRING_LIMB_FORMAT_OCT == %s",
    --              aux.sprint_value(DEBUG_STRING_LIMB_FORMAT_OCT))
    --     msg.logf("DEBUG_STRING_LIMB_FORMAT_DEC == %s",
    --              aux.sprint_value(DEBUG_STRING_LIMB_FORMAT_DEC))
    --     msg.logf("DEBUG_STRING_LIMB_FORMAT_HEX == %s",
    --              aux.sprint_value(DEBUG_STRING_LIMB_FORMAT_HEX))
    --              
    --     msg.logf("DIGITS_PER_LIMB_DEC == %u", DIGITS_PER_LIMB_DEC)
    --     msg.logf("BIG_BASE_DEC == %u == %s", BIG_BASE_DEC, hex(BIG_BASE_DEC))
    --     msg.log("")-- newline
    -- end
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
---@param e integer   range end index
---
---@nodiscard
---@return boolean ok whether all requirements are met
---@return err_msg? err_msg describes the failed requirements
function mpn.__is_valid(t, i, e)
    local em = err_msg.new()
    
    local t_type = type(t)
    if not rawequal(t_type, "table") then
        em:appendf("The provided argument for the range array"
                 .." is not a table.\nInstead it is a %s .", t_type)
    end
    local i_math_type = math.type(i)
    if not rawequal(i_math_type, "integer") then
        local i_type = i_math_type or type(i)
        em:appendf("The provided argument for the range start index"
                 .." is not a Lua integer.\nInstead it is a %s .", i_type)
    end
    local e_math_type = math.type(e)
    if not rawequal(e_math_type, "integer") then
        local e_type = e_math_type or type(e)
        em:appendf("The provided argument for the range end index"
                 .." is not an Lua integer.\nInstead it is a %s .", e_type)
    end
    
    -- do not check further, if arguments are not of correct type
    if em:has_error() then
        return em:pass_to_assert()
    end
    
    if e < i then
        em:appendf("The provided argument for the range end index"
                 .." is less than that for the start index."
                 .."\ni == %d, e == %d", i, e)
    end
    
    while i < e do
        local limb = t[i]
        if rawequal(limb, nil) then
            em:appendf("The provided range array misses the limb at index %d.", i)
        else
            local limb_math_type = math.type(limb)
            if rawequal(limb_math_type, "integer") then
                if limb < 0 then
                    em:appendf("The Lua integer at the index %d of the provided"
                             .." range array is negative."
                             .."\ntable[%d] == %X (hex).", i, i, limb)
                elseif limb >= RADIX then
                    em:appendf("The Lua integer at the index %d of the provided" 
                             .." range array is greater than or equal"
                             .." to the RADIX %d."
                             .."\nrange_array[%d] == %X (hex).", i, i, limb)
                end
            else
                local limb_type = limb_math_type or type(limb)
                em:appendf("The value at the index %d of the provided range array"
                         .." is not a Lua integer."
                         .."\nInstead it is a %s .", limb_type)
            end
        end
        i = i +1
    end
    
    return em:pass_to_assert()
end

---@nodiscard
---@return boolean ok whether the range is valid input
---@return err_msg? err_msg describes the failed requirements
function mpn.assert_is_valid_input(t, i, e) -- source
    local em = err_msg.new()
    
    if  math.type(i) == "integer"
    and math.type(e) == "integer"
    and e <= i then
        em:appendf("The provided argument for the INPUTTED range" 
                 .." end index is less or equal than that of for the"
                 .." start index."
                 .."\ni==%d, e==%e"
                 .."\nNote that an INPUTTED range must not be zero.",
                   i, e)
    end
    
    local _, is_valid_em = mpn.__is_valid(t, i, e)
    em:append(is_valid_em)
    
    return em:pass_to_assert()
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
    local str = "i="..aux.sprint_value(i)
              .." e="..aux.sprint_value(e)
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
                temp_str = temp_str..aux.sprint_value(v)
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
    local str = aux.binary_from_int(limb)
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

--- converts a non-negative Lua integer to a range
---
---@param t integer[] destination range array
---@param i integer   destination range start index
---@param int integer non-negative Lua integer to convert from
---
---@nodiscard
---@return integer e destination end index
---
--- range behavior:
--- - writes `int` leftwards to `(t;i;e)`
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
--- 
--- The value of the range must less equal `math.maxinteger`
--- 
--- If the range is valid and its value is less equal `math.maxinteger`,
--- then the return value is a non-negative integer.<br>
--- If the range is valid and its value equals the absolute value of `math.mininteger`,
--- then the return value is `math.mininteger`, which is negative.<br>
--- Else the return value is `nil`
--- 
---@param t integer[] range array
---@param i integer   range start index
---@param e integer   range end index
---
---@nodiscard
---@return integer|nil opt_int Lua integer or nil if the value does not fit in a Lua integer.
---
--- range behavior:
--- - reads `(t;i;e)` rightwards
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
    
    local free_bits = aux.count_leading_zeros(
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

--- finds the index of the first non-zero limb from the more significant end ("left") 
--- 
--- If all limbs are zero or the range is empty, then the returned index is less than `i`.
---
---@param t integer[] range array
---@param i integer   range start index
---@param e integer   range end   index
---
---@nodiscard
---@return integer left_most_non_zero_index index of the left most non-zero limb
---
--- Preconditions:
--- - `e >= i`
--- 
--- Postconditions:
--- - `left_most_non_zero_index < e`
--- - `left_most_non_zero_index < i` <==> All limbs in {`t`, `i`, `e`} are zero.
---
--- range behavior:
--- - reads `(t;i;e)` rightwards
function mpn.find_left_most_non_zero_limb(t, i, e)
    while (e > i) do
        e = e -1
        if t[e] > 0 then
            return e
        end
    end
    return e - 1
end

--- checks whether a range is minimal at the more significant end ("left")
--- 
--- This means, that the most significant limbs are not zero.
---
---@param t integer[] range array
---@param i integer   range start index
---@param e integer   range end   index
---
---@nodiscard
---@return boolean is_minimal_at_left whether the range is minimal at the left
---
--- range behavior:
--- - reads `(t;i;e)` rightwards
function mpn.is_minimal_at_left(t, i, e)
    while (e > i) do
        e = e -1
        if t[e] <= 0 then
            return false
        end
    end
    return true
end

--- minimizes a range at the more significant end ("left")
--- 
--- Therefore starting with the most significant limb
--- removes a sequence of zero limbs.
--- Thus the new most significant limb is greater than or equals 1.
---
---@param t integer[] range array
---@param i integer   range start index
---@param e integer   range end   index
---
---@nodiscard
---@return integer new_de range new end index
---
--- range behavior:
--- - in `(t;i;e)` removes a continous sequence of zero limbs since including `e-1` rightwards
function mpn.minimize_at_left(t, i, e)
    e = e -1 -- calc last index
    while (e >= i) and (t[e] <= 0) do
        t[e] = nil
        e = e -1
    end
    return e +1
end

--- copies a range to another
---
--- The source range can be zero
---
---@param dt integer[] destination range array
---@param di integer   destination range start index
---@param t  integer[] source range array
---@param i  integer   source range start index
---@param e  integer   source range end   index
---
---@return integer de destination end index (for convenience)
---
---range behavior:
--- - reads `(t;i;e)` leftwards
--- - writes `(dt;di;de)` leftwards
--- - `(dt;di;de)` and `(t;i;e)` may overlap
function mpn.copy(dt, di, -- destination by start index
                  t, i, e) -- source
    assert( mpn.__is_valid(t, i, e) )-- DEBUG
    
    table.move(t, i, e-1, -- source
               di, dt) -- destination by start index
    
    assert( mpn.__is_valid(t, i, e) )-- DEBUG
    assert( mpn.__is_valid(dt, di, di+e-i) )-- DEBUG
    return di + e-i
end

--- compares two ranges
---
--- The return values follow the convention of GNU MP's `mpn_cmp()`:<br>
--- if self <  other, returns -1<br>
--- if self == other, returns  0<br>
--- if self >  other, returns +1<br>
--- Mnemonic: `mpn.cmp()` returns the sign of the directed difference of
---           the 1st range minus the 2nd range.
--- in contrast to GNU MP's `mpn_cmp()` the arguments can have different lengths.
---
---@param st integer[] self  source range array
---@param si integer   self  source range start index
---@param se integer   self  source range end   index
---@param ot integer[] other source range array
---@param oi integer   other source range start index
---@param oe integer   other source range end   index
---
---@nodiscard
---@return integer cmp_res sign of the directed difference self - other
---
--- range behavior:
--- - reads `(st;si;se)` rightwards
--- - reads `(ot;oi;oe)` rightwards
function mpn.cmp(st, si, se, -- 1st source range
                 ot, oi, oe) -- 2nd source range
    
    assert( mpn.__is_valid(st, si, se) )-- DEBUG
    assert( mpn.__is_valid(ot, oi, oe) )-- DEBUG
    
    local sl = se-si
    local ol = oe-oi
    local common_l = math.min(sl, ol)
    -- search for first non-zero limb in the more significant limbs of the 
    -- longer range, which are additional with respect to the smaller range
    if sl > ol then
        -- e == 5, common_l == 3, i == 0 --> lower_end_index = 3
        local lower_end_index = si+common_l
        while se > lower_end_index do
            se = se -1
            if not rawequal(st[se], 0) then
                return 1
            end
        end
    else
        local lower_end_index = oi+common_l
        while oe > lower_end_index do
            oe = oe -1
            if not rawequal(ot[oe], 0) then
                return -1
            end
        end
    end
    assert( se >= si+common_l )-- DEBUG
    assert( oe >= oi+common_l )-- DEBUG
    -- determinate the first limb smaller or greater
    local self_limb, other_limb
    while se > si do
        se = se -1 ; oe = oe -1
        self_limb = st[se]
        other_limb = ot[oe]
        if self_limb < other_limb then
            return -1
        elseif self_limb > other_limb then
            return 1
        end
    end
    return 0
end

--- shifts a range right by a certain, small count of bit positions
---
--- The destination range is truncated at the destination start index ("bounded").
--- Thus bits from the lower significant end are discarded from the destination,
--- but returned.
---
--- The right shift amount must be less than the limb width ("few").
---
---@param dt integer[] destination range array
---@param di integer   destination range start index
---@param t  integer[] source range array
---@param i  integer   source range start index
---@param e  integer   source range end  index
---@param crop_shift integer count of bit postitions to shift the source range right by
---@param left_incoming_bits integer bits to shift into the more significant end of the destination range
---
---@return integer de destination end index (for convenience)
---@return integer right_outgoing_bits bits shifted out of the less significant end of the destination range
---
--- range behavior:
--- - reads `(t;i;e)` rightwards
--- - writes `(dt;di;de)` rightwards
--- - If `(t;i;e)` and `(dt;di;de)` overlap, then must be `de >= e` or `i >= de`, where `de == di+(e-i)`.
function mpn.rshift_few_bounded___rightward_impl(
        dt, di, -- destination by start index
        t, i, e, -- source
        crop_shift, -- right shift amount
        left_incoming_bits)
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
    
    local de = di + e-i
    di = de
    local cur_limb
    while e > i do
        e = e -1 -- rightwards
        cur_limb = t[e]
        di = di -1 -- rightwards
        dt[di] = ( left_incoming_bits | (cur_limb >> crop_shift) ) & MOD_MASK
        left_incoming_bits = cur_limb << make_room_shift
    end
    
    assert( mpn.__is_valid(dt, di, de) )-- DEBUG
    return de, left_incoming_bits & MOD_MASK
end

--- shifts a range right by a certain, small count of bit positions
---
--- The destination range is truncated at the destination start index ("bounded").
--- Thus bits from the lower significant end are discarded from the destination,
--- but returned.
---
--- The right shift amount must be less than the limb width ("few").
---
---@param dt integer[] destination range array
---@param di integer   destination range start index
---@param t  integer[] source range array
---@param i  integer   source range start index
---@param e  integer   source range end  index
---@param crop_shift integer count of bit postitions to shift the source range right by
---@param left_incoming_bits integer bits to shift into the more significant end of the destination range
---
---@return integer de destination end index (for convenience)
---@return integer right_outgoing_bits bits shifted out of the less significant end of the destination range
---
--- range behavior:
--- - `(t;i;e)` must consist of at least one limb
--- - reads `(t;i;e)` leftwards
--- - writes `(dt;di;de)` leftwards
--- - If `(t;i;e)` and `(dt;di;de)` overlap, then must be `di >= e` or `i >= di`.
function mpn.rshift_few_bounded___leftward_impl(
        dt, di, -- destination by start index
        t, i, e, -- source
        crop_shift, -- right shift amount
        left_incoming_bits)
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
    -- assert( e > i, "source range must consist of at least one limb")
    if e <= i then
        return di, left_incoming_bits
    end
    assert( mpn.__is_valid(t, i, e) )
    -- END DEBUG
    
    local make_room_shift = WIDTH - crop_shift
    
    -- BEGIN DEBUG
    assert( (left_incoming_bits & ((1 << make_room_shift)-1)) == 0,
            f("left incoming bits must be restricted to the range"
            .." from excl. the WIDTH to incl. WIDTH - the right shift amount "
            .."\nleft_incoming_bits == %s", bin(left_incoming_bits)) )
    -- END DEBUG
    
    local saved_di = di -- DEBUG
    
    local left_limb = t[i]
    i = i +1 -- leftwards
    local right_outgoing_bits = (left_limb << make_room_shift) & MOD_MASK
    local right_limb_right_shifted = left_limb >> crop_shift
    -- At the begin of every iteration i points to the left_limb.
    while i < e do
        left_limb = t[i]
        i = i +1 -- leftwards
        dt[di] = ((left_limb << make_room_shift) | right_limb_right_shifted) & MOD_MASK
        di = di +1 -- leftwards
        right_limb_right_shifted = left_limb >> crop_shift
    end
    dt[di] = left_incoming_bits | right_limb_right_shifted
    
    assert( mpn.__is_valid(dt, saved_di, di) )-- DEBUG
    return di +1, right_outgoing_bits
end

--- shifts a range left by a certain, small count of bit positions
---
--- The destination range is truncated to the length of the source range ("bounded").
--- Thus bits from the more significant end are discarded from the destination,
--- but returned.
---
--- The left shift amount must be less than the limb width ("few").
--- 
--- The source and destination must not overlap! (currently)
---
---@param dt integer[] destination range array
---@param di integer   destination range start index
---@param t  integer[] source range array
---@param i  integer   source range start index
---@param e  integer   source range end  index
---@param make_room_shift integer count of bit positions to shift the source range left by
---@param right_incoming_bits integer bits to shift into the less significant end of the destination range
---
---@return integer de destination end index (for convenience)
---@return integer left_outgoing_bits bits shifted out of the more significant end of the destination range
---
--- range behavior:
--- - reads `(t;i;e)` leftwards
--- - writes `(dt;di;de)` leftwards
--- - If `(t;i;e)` and `(dt;di;de)` overlap, then must be `di >= e` or `i >= di`.
function mpn.lshift_few_bounded___leftward_impl(
        dt, di, -- destination
        t, i, e, -- source
        make_room_shift, -- left shift amount
        right_incoming_bits)
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
    
    local cur_limb
    while i < e do
        cur_limb = t[i]
        i = i +1 -- leftwards
        dt[di] = ( (cur_limb << make_room_shift) | right_incoming_bits ) & MOD_MASK
        di = di +1 -- leftwards
        right_incoming_bits = cur_limb >> crop_shift
    end
    
    assert( di-saved_di == e-saved_i )-- DEBUG
    assert( mpn.__is_valid(dt, saved_di, di) )-- DEBUG
    return di, right_incoming_bits
end

--- shifts a range left by a certain, small count of bit positions
---
--- The destination range is truncated to the length of the source range ("bounded").
--- Thus bits from the more significant end are discarded from the destination,
--- but returned.
---
--- The left shift amount must be less than the limb width ("few").
--- 
--- The source and destination must not overlap! (currently)
---
---@param dt integer[] destination range array
---@param di integer   destination range start index
---@param t  integer[] source range array
---@param i  integer   source range start index
---@param e  integer   source range end  index
---@param make_room_shift integer count of bit positions to shift the source range left by
---@param right_incoming_bits integer bits to shift into the less significant end of the destination range
---
---@return integer de destination end index (for convenience)
---@return integer left_outgoing_bits bits shifted out of the more significant end of the destination range
---
--- range behavior:
--- - reads `(t;i;e)` rightwards
--- - writes `(dt;di;de)` rightwards
--- - If `(t;i;e)` and `(dt;di;de)` overlap, then must be `de >= e` or `i >= de`, where `de == di+(e-i)`.
function mpn.lshift_few_bounded___rightward_impl(
        dt, di, -- destination
        t, i, e, -- source
        make_room_shift, -- left shift amount
        right_incoming_bits)
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
    assert( e > i, "source range must consist of at least one limb")
    -- if e <= i then
    --     return di, right_incoming_bits
    -- end
    assert( mpn.__is_valid(t, i, e) )
    -- END DEBUG
    
    local crop_shift = WIDTH - make_room_shift
    local de = di + e-i
    e = e -1 -- rightwards
    local right_limb = t[e]
    local left_outgoing_bits = right_limb >> crop_shift
    local left_limb_left_shifted = (right_limb << make_room_shift) & MOD_MASK
    di = de
    while e > i do
        e = e -1 -- rightwards
        right_limb = t[e]
        di = di -1 -- rightwards
        dt[di] = left_limb_left_shifted | (right_limb >> crop_shift)
        left_limb_left_shifted = (right_limb << make_room_shift ) & MOD_MASK
    end
    di = di -1 -- rightwards
    dt[di] = left_limb_left_shifted | right_incoming_bits
    
    assert( mpn.__is_valid(dt, di, de) )-- DEBUG
    return de, left_outgoing_bits
end

---@alias rshift_few_bounded_func fun(dt: integer[], di: integer, t: integer[], i: integer, e: integer, crop_shift     : integer, left_incoming_bits : integer): de: integer, right_outgoing_bits: integer
---@alias lshift_few_bounded_func fun(dt: integer[], di: integer, t: integer[], i: integer, e: integer, make_room_shift: integer, right_incoming_bits: integer): de: integer, left_outgoing_bits : integer

--- shifts a range right by a certain, small count of bit positions
---
--- All bits from the source range are written to the destination range.
--- Thus the destination range can be have one limb more than the source range ("unbounded").
--- Thus no bits from the less significant end are discarded.
---
--- The right shift amount must be less than the limb width ("few")
--- 
---@param dt integer[] destination range array
---@param de integer   destination range **end** index
---@param t  integer[] source range array
---@param i  integer   source range start index
---@param e  integer   source range end   index
---@param right_shift_amount integer count of bit positions to shift the source range right by
---@param left_incoming_bits integer bits to shift into the more significant end of the destination range
---@param rshift_few_bounded_func rshift_few_bounded_func `mpn.rshift_few_bounded___rightward_impl` or `mpn.rshift_few_bounded___leftward_impl`
---
---@nodiscard
---@return integer di destination **start** index
---
--- range behavior:
--- - see selected `rshift_few_bounded_func`
function mpn.rshift_few_unbounded(
        dt, de, -- destination by end index
        t, i, e, -- source
        right_shift_amount, -- right shift amount
        left_incoming_bits,
        rshift_few_bounded_func
    )
    -- BEGIN DEBUG
    assert( math.type(right_shift_amount) == "integer","left shift amount must be an integer")
    assert( right_shift_amount > 0 , "right shift amount must be positive.")
    assert( right_shift_amount < WIDTH , "right shift amount must be less than WIDTH.")
    assert( mpn.__is_valid(t, i, e) )
    -- END DEBUG
    
    local di = de - e+i
    local _de, rem_bits = rshift_few_bounded_func(
                                dt, di, -- destination by start index
                                t, i, e, -- source
                                right_shift_amount, -- right shift amount
                                left_incoming_bits)
    -- BEGIN DEBUG
    assert( _de == de , f("s == %d"
                        .."\nsource range == %s"
                        .."\nresult range == %s"
                        .."\n_de == %d ~= de == %d",
                          right_shift_amount,
                          mpn.debug_string_hex(t, i, e),
                          mpn.debug_string_hex(dt, di, _de),
                          _de, de) )
    -- END DEBUG
    di = di -1
    dt[di] = rem_bits
    assert( mpn.__is_valid(dt, di, de) )-- DEBUG
    return di
end

--- shifts a range left by a certain count of bit positions
---
--- All bits from the source range are written to the destination range.
--- Thus the destination range can be have one limb more than the source range ("unbounded").
--- Thus no bits from the more significant end of the destination range are discarded.
---
--- The left shift amount must be less than the limb width ("few").
--- 
--- The source and destination must not overlap! (currently)
---
---@param dt integer[] destination range array
---@param di integer   destination range start index
---@param t  integer[] source range array
---@param i  integer   source range start index
---@param e  integer   source range end   index
---@param left_shift_amount integer count of bit positions to shift the source range left by
---@param right_incoming_bits integer bits to shift into the less significant end of the destination range
---@param lshift_few_bounded_func lshift_few_bounded_func `mpn.lshift_few_bounded___leftward_impl` or `mpn.lshift_few_bounded___rightward_impl`
---
---@nodiscard
---@return integer de destination end index
---
--- range behavior:
--- - see selected `lshift_few_bounded_func`
function mpn.lshift_few_unbounded(
        dt, di, -- destination
        t, i, e, -- source
        left_shift_amount, -- left shift amount
        right_incoming_bits,
        lshift_few_bounded_func
    )
    -- BEGIN DEBUG
    assert( math.type(left_shift_amount) == "integer","left shift amount must be an integer")
    assert( left_shift_amount > 0 , "left shift amount must be positive.")
    assert( left_shift_amount < WIDTH , "left shift amount must be less than WIDTH.")
    assert( mpn.__is_valid(t, i, e) )
    -- END DEBUG
    
    local de, rem_bits = lshift_few_bounded_func(
                                dt, di, -- destination by start index
                                t, i, e, -- source
                                left_shift_amount, -- left shift amount
                                right_incoming_bits)
    dt[de] = rem_bits
    de = de + 1
    assert( mpn.__is_valid(dt, di, de) )-- DEBUG
    return de
end

--- shifts a range right by a certain count of bit positions
--- 
--- Bits, that would be shifted out from the less significant end of the source range
--- are written to the "fractional" destination range.<br>
--- Bits, that would remain in the source range are written to the "integer" destination range.
--- 
---@param dt integer[] integer    destination range array
---@param di integer   integer    destination range start index
---@param ft integer[] fractional destination range array
---@param fe integer   fractional destination range **end** index
---@param t  integer[] source range array
---@param i  integer   source range start index
---@param e  integer   source range end   index
---@param crop_shift integer count of bit positions to shift the source range right by
---@param rshift_few_bounded_func rshift_few_bounded_func `mpn.rshift_few_bounded___rightward_impl` or `mpn.rshift_few_bounded___leftward_impl`
---
---@nodiscard
---@return integer de integer    destination range   end     index
---@return integer fi fractional destination range **start** index
---
--- range behavior:
--- - see selected `rshift_few_bounded_func`
function mpn.rshift_many_bounded(
        dt, di, -- destination for the integer part of the shifted copy
        ft, fe, -- destination for the fractional part of the shifted copy
        t, i, e, -- source
        crop_shift, -- right shift amount
        rshift_few_bounded_func
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
        
    -- Let ft_limbs_ratio be the /rational/ quotient of crop_shift by WIDTH.
    -- Let ft_limbs_trunc be the /floored/ integer quotient of crop_shift by WIDTH.
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
                    rshift_few_bounded_func(
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
                left_incoming_bits, -- left incoming bits
                rshift_few_bounded_func)
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

-- There is no mpn.rshift_many_unbounded() function planned currently,
-- because that would mean, that it writes right of the provided start index. 
-- Or other: The function would must return a start index (= start index of the 
-- fractional part) and an end index (= end index of the integer part)

--- shifts a range right by a certain count of bit positions
--- 
--- Bits, that would be shifted out from the less significant end of the source range
--- are discarded.
---
--- The source and destination range must not overlap! (currently)
--- 
---@param dt integer[] destination range array
---@param di integer   destination range start index
---@param t  integer[] source range array
---@param i  integer   source range start index
---@param e  integer   source range end   index
---@param crop_shift integer count of bit positions to shift the source range right by
---@param rshift_few_bounded_func rshift_few_bounded_func `mpn.rshift_few_bounded___rightward_impl` or `mpn.rshift_few_bounded___leftward_impl`
---
---@nodiscard
---@return integer de destination range end index
---
--- range behavior:
--- - see selected `lshift_few_bounded_func`
function mpn.rshift_many_discard(
        dt, di, -- destination by start index
        t, i, e, -- source
        crop_shift, -- right shift amount
        rshift_few_bounded_func
    )
    -- BEGIN DEBUG
    assert( math.type(crop_shift) == "integer",
            "right shift amount must be an integer")
    assert( crop_shift > 0 , "right shift amount must be positive.")
    assert( mpn.__is_valid(t, i, e) )
    -- msg.logf("source range == %s", mpn.debug_string_bin(t, i, e))
    -- msg.logf("input crop_shift == %d", crop_shift)
    -- END DEBUG
    
    if e <= i then
        return di
    end
    
    -- compute extra limbs and /necessary/ shift
    local ft_limbs_trunc = crop_shift // WIDTH
    crop_shift = crop_shift - ft_limbs_trunc*WIDTH -- crop_shift % WIDTH
    local i_split = math.min(i + ft_limbs_trunc, e)
    local de = di + math.max(e-i - ft_limbs_trunc, 0)
    
    -- BEGIN DEBUG
    -- msg.logf("working crop_shift == %d", crop_shift)
    -- msg.logf("i_split == %d", i_split)
    -- msg.logf("di == %d, de == %d", di, de)
    -- END DEBUG
    
    -- There is 1 phase:
    -- 1. (homogen or heterogen) limbs into dt
    if i_split < e then
        if crop_shift > 0 then
            local _de = -- DEBUG
                rshift_few_bounded_func(
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
-- The source and destination range must not overlap! (currently)

--- shifts a range left by a certain count of bit positions
--- 
--- Bits, that would be shifted out from the more significant end of the source range
--- are written to the "integer" destination range.<br>
--- Bits, that would remain in the source range are written to the "fractional" destination range.
--- 
--- The source and destination range must not overlap! (currently)
--- 
--- **TODO** get         fractional destination range end   index (instead of start index)<br>
--- **TODO** thus return fractional destination range start index (instead of end   index)
---
---@param it integer[] integer    destination range array
---@param ii integer   integer    destination range start index
---@param ft integer[] fractional destination range array
---@param fi integer   fractional destination range **start** index
---@param t  integer[] source range array
---@param i  integer   source range start index
---@param e  integer   source range end   index
---@param make_room_shift integer count of bit positions to shift the source range left by
---@param lshift_few_bounded_func lshift_few_bounded_func `mpn.lshift_few_bounded___leftward_impl` or `mpn.lshift_few_bounded___rightward_impl`
---
---@nodiscard
---@return integer de integer    destination range   end     index
---@return integer fe fractional destination range **end** index
---
--- range behavior:
--- - see selected `lshift_few_bounded_func`
function mpn.lshift_many_bounded(
        it, ii, -- destination by start index for shifted out limbs/bits
        ft, fi, -- destination by start index with length equal to source
        t, i, e, -- source
        make_room_shift,
        lshift_few_bounded_func
    )
    -- BEGIN DEBUG
    assert( math.type(make_room_shift) == "integer",
            "left shift amount must be an integer")
    assert( make_room_shift > 0 , "left shift amount must be positive.")
    assert( mpn.__is_valid(t, i, e) )
    -- msg.logf("source range == %s", mpn.debug_string_bin(t, i, e))
    -- msg.logf("input make_room_shift == %d", make_room_shift)
    -- END DEBUG
    
    if e <= i then
        return ii, fi
    end
    
    -- compute extra limbs and /necessary/ shift
    local complete_zero_limbs = make_room_shift // WIDTH
    make_room_shift = make_room_shift - complete_zero_limbs*WIDTH
    
    local de = fi + e-i
    local re = ii + complete_zero_limbs
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
    -- msg.logf("complete_zero_limbs == %d", complete_zero_limbs)
    -- msg.logf("working make_room_shift == %d", make_room_shift)
    -- msg.logf("i_split == %d", i_split)
    -- msg.logf("ri == %d, re == %d", ii, re)
    -- msg.logf("di == %d, de == %d", fi, de)
    -- END DEBUG
    
    local saved_di = fi -- DEBUG
    local saved_ri = ii -- DEBUG
    local right_incoming_bits = 0
    
    -- There 4 phases:
    -- 1. pad zero limbs at dt from di upwards
    local complete_zero_limbs_j = 0
    while (fi < de) and (complete_zero_limbs_j < complete_zero_limbs) do
        ft[fi] = 0 ; fi = fi +1
        complete_zero_limbs_j = complete_zero_limbs_j +1 
    end
    -- 2. (homogen or heterogen) filled limbs for dt upto excluding de
    if fi < de then
        if make_room_shift > 0 then
            local _de -- DEBUG
            _de, right_incoming_bits =
                    lshift_few_bounded_func(
                            ft, fi, -- destination by start index
                            t, i, i_split, -- source
                            make_room_shift, -- left shift amount
                            0) -- right incoming bits
            assert( _de == de )-- DEBUG
        else
            assert( de == -- DEBUG
            mpn.copy(ft, fi, --destination
                     t, i, i_split) -- source
            )-- DEBUG
        end
    end
    -- 3. pad zero limbs at rt from ri upwards
    while complete_zero_limbs_j < complete_zero_limbs do
        it[ii] = 0 ; ii = ii +1
        complete_zero_limbs_j = complete_zero_limbs_j +1 
    end
    -- 4. (homogen or heterogen) filled limbs for rt upto excluding re
    if make_room_shift > 0 then
        local _re = -- DEBUG
        mpn.lshift_few_unbounded(
                it, ii, -- destination by start index
                t, i_split, e, -- source
                make_room_shift, -- left shift amount
                right_incoming_bits,
                lshift_few_bounded_func)
        -- BEGIN DEBUG
        assert( _re == re, f("_re == %d ~= re == %d", _re, re) )
        -- END DEBUG
    else
        assert( re == -- DEBUG
        mpn.copy(it, ii, -- destination by start index
                 t, i_split, e) -- source
        )-- DEBUG
    end
    
    assert( mpn.__is_valid(it, saved_ri, re) )-- DEBUG
    assert( mpn.__is_valid(ft, saved_di, de) )-- DEBUG
    return re, de
end

-- shifts a natural integer left by a certain count of binary digits
-- and writes a shifted copy to the destination
-- The return value is the end index of the shifted copy
-- The source and destination range must not overlap! (currently)

--- shifts a range left by a certain count of bit postitions
--- 
--- All bits from the source range are written to the destination range.
--- Thus the destination range can be have more limbs than the source range ("unbounded").
--- Thus no bits from the more significant end are discarded.
--- 
---@param dt integer[] destination range array
---@param di integer   destination range start index
---@param t  integer[] source range array
---@param i  integer   source range start index
---@param e  integer   source range end index
---@param make_room_shift integer count of bit positions to shift the source range left by
---@param lshift_few_bounded_func lshift_few_bounded_func `mpn.lshift_few_bounded___leftward_impl` or `mpn.lshift_few_bounded___rightward_impl`
---
---@nodiscard
---@return integer de destination range end index
---
--- range behavior:
--- - see selected `lshift_few_bounded_func`
function mpn.lshift_many_unbounded(
        dt, di, -- destination by start index
        t, i, e, -- source
        make_room_shift, -- left shift amount
        lshift_few_bounded_func
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
                    make_room_shift, -- left shift amount
                    lshift_few_bounded_func)
    
    -- BEGIN DEBUG
    assert( de_in_between == di+e-i )
    assert( mpn.__is_valid(dt, di, de_in_between) )
    assert( mpn.__is_valid(dt, de_in_between, de) )
    assert( mpn.__is_valid(dt, di, de) )
    -- END DEBUG
    return de
end

--- adds two ranges, propagates a carry.
--- 
--- The length of the 1st source range (augend, "self") must be greater than or equal to
--- the length of the 2nd source range (addend, "other").
--- 
---@param dt integer[] destination range array
---@param di integer   destination range start index
---@param st integer[] augend source range ("self")  array
---@param si integer   augend source range ("self")  start index
---@param se integer   augend source range ("self")  end   index
---@param ot integer[] addend source range ("other") array
---@param oi integer   addend source range ("other") start index
---@param oe integer   addend source range ("other") end   index
---@param carry integer right incoming carry
---
---@nodiscard
---@return integer de destination range end index
---@return integer carry left outgoing carry
---
--- range behavior:
--- - reads `(st;si;se)` leftwards
--- - reads `(ot;oi;oe)` leftwards
--- - writes `(dt;di;de)` leftwards
--- - `(st;si;se)`, `(ot;oi;oe)`, `(dt;di;de)` may overlap
function mpn.add_bounded(dt, di, -- destination by start index
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
        di = di +1
        si = si +1
        oi = oi +1
    end
    -- extra digits of self, while carry is positive
    while (carry > 0) and (si < se) do
        -- Altough this loop iterates only a few times,
        -- it could be multiple times for small WIDTH.
        temp = carry + st[si]
        dt[di] = temp & MOD_MASK
        carry = temp >> WIDTH
        di = di +1
        si = si +1
    end
    -- Here holds:
    -- (carry == 0) or (si == se) -- Note normal or (not xor)
    
    -- copy extra digits of self, because carry is 0
    -- and would also never again become 1
    while si < se do -- If this loop is executed, because si < se,
                     -- then must be carry == 0 .
        dt[di] = st[si]
        di = di +1
        si = si +1
    end
    
    assert( (di-saved_di) == (si-saved_si) ) -- DEBUG
    assert( (di-saved_di) == (se-saved_si) ) -- DEBUG
    assert( mpn.__is_valid(dt, saved_di, di) )-- DEBUG
    return di, carry
end

--- adds two ranges, prepends a carry to the destination range
--- 
--- The length of the 1st source range (augend, "self") must be greater than or equal to
--- the length of the 2nd source range (addend, "other").
--- 
--- The source ranges and the destination range must not overlap! (currently)
--- 
---@param dt integer[] destination range array
---@param di integer   destination range start index
---@param st integer[] augend source range ("self")  array
---@param si integer   augend source range ("self")  start index
---@param se integer   augend source range ("self")  end   index
---@param ot integer[] addend source range ("other") array
---@param oi integer   addend source range ("other") start index
---@param oe integer   addend source range ("other") end   index
---@param carry integer right incoming carry
---
---@nodiscard
---@return integer de destination range end index
---
--- range behavior:
--- - reads `(st;si;se)` leftwards
--- - reads `(ot;oi;oe)` leftwards
--- - writes `(dt;di;de)` leftwards
--- - `(st;si;se)`, `(ot;oi;oe)`, `(dt;di;de)` may overlap
function mpn.add_unbounded(dt, di, -- destination by start index
                           st, si, se, -- augend source "self"
                           ot, oi, oe, -- addend source "other"
                           carry) -- right incoming carry
    local de, carry = mpn.add_bounded(dt, di,
                                      st, si, se,
                                      ot, oi, oe,
                                      carry)
    if carry > 0 then
        dt[de] = carry
        de = de +1
    end
    return de
end

--- subtracts one range from another (directed difference)
--- 
--- The 1st source range (subtrahend, "self") must be longer than
--- the 2nd source range (minuend, "other") or equally long.
--- 
--- If the natural integer represented by the 1nd source range is less than 
--- those of the 2nd source range, then the destination is given in the
--- `RADIX`-complement of the absolute difference (undirected difference).
--- Then and only then the outgoing borrow bit is 1.
--- 
---@param dt integer[] destination range array
---@param di integer   destination range start index
---@param st integer[] subtrahend source range ("self") array
---@param si integer   subtrahend source range ("self") start index
---@param se integer   subtrahend source range ("self") end index
---@param ot integer[] minuend range ("other") array
---@param oi integer   minuend range ("other") start index
---@param oe integer   minuend range ("other") end index
---@param borrow integer right incoming borrow bit
---
---@nodiscard
---@return integer de destination range end index
---@return integer outgoing_borrow left outgoing borrow bit
---
--- range behavior:
--- - reads `(st;si;se)` leftwards
--- - reads `(ot;oi;oe)` leftwards
--- - writes `(dt;di;de)` leftwards
--- - `(st;si;se)`, `(ot;oi;oe)`, `(dt;di;de)` may overlap
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
    
    -- consider the minuend source range other with padded with zero limbs
    -- at the most significand end
    
    -- only performs "positive normalisation":
    -- All limbs must be non-negative. Else RADIX is added.
    
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

--- computes the absolute difference (undirected difference) between two ranges
---
--- The source ranges and the destination range must not overlap! (currently)
---
---@param dt integer[] destination range array
---@param di integer   destination range start index
---@param st integer[] self source range
---@param si integer   self source range start index
---@param se integer   self source range end index
---@param ot integer[] other source range array
---@param oi integer   other source range start index
---@param oe integer   other source range end index
---
---@nodiscard
---@return integer de destination range end index == `di - se + si`
---@return boolean is_negative whether the directed difference self range - other range is negative
--- 
--- range behavior:
--- 1. with `mpn.cmp()`:
---     - reads `(st;si;se)` rightwards
---     - reads `(ot;oi;oe)` rightwards
--- 2. with `mpn.sub()`:
---     - reads `(st;si;se)` leftwards
---     - reads `(ot;oi;oe)` leftwards
--- - writes `(dt;di;de)` leftwards
--- - `(st;si;se)`, `(ot;oi;oe)`, `(dt;di;de)` may overlap
function mpn.diff(dt, di,
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

--- multiplies two ranges
--- 
---
--- The most significant limb of `dt` at `de-1` can be zero.
--- 
---@param dt integer[] destination range
---@param di integer   destination start index
---@param st integer[] multiplicand source range ("self")
---@param si integer   multiplicand source range ("self") start index
---@param se integer   multiplicand source range ("self") end index
---@param ot integer[] multiplier source range ("other")
---@param oi integer   multiplier source range ("other") start index
---@param oe integer   multiplier source range ("other") end index
---
---@nodiscard
---@return integer de destination range end index `== di + se-si + oe-oi`
---
--- range behavior:
--- - reads `(st;si;se)` leftwards
--- - reads `(ot;oi;oe)` leftwards
--- - writes `(dt;di;de)` leftwards
--- - `(st;si;se)` and `(ot;oi;oe)` may overlap
--- - `(dt;di;de)` and `(st;si;se)` must be distinct
--- - `(dt;di;de)` and `(ot;oi;oe)` must be distinct (except the most significant limb of `(ot;oi;oe)`)
function mpn.mul(dt, di, -- destination range
                 st, si, se, -- self source range
                 ot, oi, oe) -- other source range
    
    if (se <= si) or (oe <= oi) then
        return di -- product is null
    end
    
    local de = di + se-si + oe-oi -1
    -- DIRECTLY points to the to last possible limb
    
    -- obvious implementation of schoolbook algorithm:
    -- self is the "multiplicand". other is the "multiplier".
    
    -- fill with zeros
    for oj = di, de do
        dt[oj] = 0
    end
    -- Imagine the limbs of the multiplicand self written at the top in a row.
    -- The significance of the limbs of self increases to the left. 
    -- Imagine the limbs of the multiplier other written right in a column. 
    -- The significance of the limbs of other increases downwards.
    -- Imagine the limbs of the product res written at the bottom in a row.
    -- The significance of the limbs of res increases to the left.
    -- The algorithm can be described as follows:
    --   - compute a "product row". These are all limbs of self multiplied with the fixed limb of other in that row.
    --   - shift the product row j times to the left, where j is the null-based index of the fixed limb of other
    --   - add each such "product row" to the product so far.
    --   - assign the "surplus" carry from the computation of the "product row" to an extra limb
    -- The computation of a product row and adding this to the product so far is done synchronous:
    --   1. add the carry to                                      (the previous value of) the appropriate limb of the product
    --   2. add the product of the (next) limb of self with the fixed limb of other to    the appropriate limb of the product
    --   3. compute the new carry from                                                    the appropriate limb of the product
    --   4. compute the new value of the appropriate limb of the product from             the appropriate limb of the product
    local dj
    for oj = oi, oe-1 do -- for each product row ...
        local carry = 0
        local otj = ot[oj]
        for sj = si, se-1 do -- ... process all limbs of self
            dj = di + oj-oi + sj-si
            local temp = dt[dj] + carry + st[sj] * otj
            -- This is the formula, which must fit into a Lua integer
            -- >>>>> This formula thus induces the upperbound for WIDTH and RADIX. <<<<<
            -- res[index], self[i] and other_j are bounded by RADIX-1 =: L =: 2^l -1
            -- We define W =: 2^w -1 as the RADIX of for positive Integer.
            -- Thus W = math.maxinteger+1
            -- The developer has deduced, that for the limb radix L the following inequality must hold:
            --     L^2 -1 < W   resp.   2^(2l) < 2^w +1
            -- Thus:
            --     l <= w/2
            -- For w = 31 we get l = 15. For w = 63 we get l = 31
            dt[dj] = temp & MOD_MASK
            carry = temp >> WIDTH
        end
        dt[dj+1] = carry
    end
    
    assert(mpn.__is_valid(dt, di, de +1))-- DEBUG
    return de +1
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

---@private
---
--- divides a range by a word
--- 
--- rounds the quotient range to zero
---
---@param dt integer[] destination range
---@param di integer   destination start index
---@param st integer[] dividend source range ("self")
---@param si integer   dividend source range ("self") start index
---@param se integer   dividend source range ("self") end index
---@param o  integer   divisor Lua integer `<= RADIX` ("other")
---
---@nodiscard
---@return integer de destination range end index
---
--- range behavior:
--- - reads `(st;si;se)` rightwards
--- - writes `(dt;di;de)` rightwards
--- - `(dt;di;de)` and `(st;si;se)` may overlap
function mpn.__idiv_word(dt, di, -- destination range
                         st, si, se, -- dividend range
                         o) -- divisor word
    
    -- This is the schoolbook division algorithm (still currently taught).
    
    local r = 0
    local de = se-si + di
    local de_ret = de
    local temp, q
    repeat
        se = se -1
        de = de -1
        temp = (r << WIDTH) | st[se]
        q = temp // o
        r = temp - q*o-- hopefully a bit faster than temp % d
        dt[de] = q
    until se <= si
    
    -- -- Minimize quotient
    -- -- Because of the precondition |self| > |other|, we can assume, that
    -- -- the quotient is at least 1, und thus we have at least one non-zero limb.
    -- i = self.n - 1
    -- while q[i] == 0 do
    --     q[i] = nil
    --     i = i -1
    -- end
    -- q.n = i + 1
    
    -- Note that the result range is not minimized by intention.
    
    assert(mpn.__is_valid(dt, di, de_ret))-- DEBUG
    return de_ret
end

---@private
---
--- divides a range by another, where the divisor range must consist of multiple limbs
--- 
--- rounds the quotient range to zero
---
---@param dt integer[] destination range
---@param di integer   destination start index
---@param st integer[] dividend source range ("self")
---@param si integer   dividend source range ("self") start index
---@param se integer   dividend source range ("self") end index
---@param ot integer[] divisor source range ("other")
---@param oi integer   divisor source range ("other") start index
---@param oe integer   divisor source range ("other") end index
---
---@nodiscard
---@return integer de destination range end index
---
--- range behavior:
--- - reads `(st;si;se)` rightwards
--- - reads `(ot;oi;oe)` rightwards
--- - `(st;si;se)` and `(ot;oi;oe)` may overlap
--- - writes `(dt;di;de)` leftwards
--- - `(dt;di;de)` and `(st;si;se)` must be distinct
--- - `(dt;di;de)` and `(ot;oi;oe)` must be distinct
function mpn.__idiv_multiple_limbs(dt, di, -- destination (d) range
                                   st, si, se, -- dividend (dd) range
                                   ot, oi, oe) -- divisor (dr) range
    
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
    
    --msg.logf("division with Algorithm D")--DEBUG
    -- assert(other.n > 1)--DEBUG
    -- assert(self.n >= other.n)--DEBUG
    -- assert(Integer.__compare_abs(self, other) == 1)--DEBUG
    
    local dde = se-si -- current dividend (dd) range end index; actually the dividend has one more limb
    local dre = oe-oi -- current divisior (dr) range end index
    local i, j
    
    -- D1: copy and normalize arguments
    -- divisor[n-1] must be >= floor(RADIX/2) == 2^(WIDTH-1)
    local ddt = {} -- normalized dividend (dd) range; at the end c is the remainder range
    local drt = {} -- normalized divisor  (dr) range
        
    local make_room_shift = aux.count_leading_zeros(ot[oe-1], WIDTH)
    --msg.logf("make_room_shift == %d", make_room_shift)--DEBUG
    
    -- We can expect here, that c_n, d_n >= 1 .
    if make_room_shift == 0 then
        -- copy dividend (dd) range
        i = dde
        ddt[dde] = 0
        repeat
            i = i -1
            ddt[i] = st[i]
        until i == 0
        -- copy divisor (dr) range
        i = dre
        repeat
            i = i -1
            drt[i] = ot[i]
        until i == 0
    else
        local crop_shift = WIDTH - make_room_shift
        -- shift dividend (dd) range
        i = dde -1
        j = st[i] >> crop_shift
        ddt[dde] = j
        while i ~= 0 do
            j = i - 1
            ddt[i] = ( (st[i] << make_room_shift) | (st[j] >> crop_shift) ) & MOD_MASK
            i = j
        end
        ddt[0] = ( st[0] << make_room_shift ) & MOD_MASK
        -- shift divisor (dr) range
        i = dre -1
        while i ~= 0 do
            j = i - 1
            drt[i] = ( (ot[i] << make_room_shift) | (ot[j] >> crop_shift) ) & MOD_MASK
            i = j
        end
        drt[0] = ( ot[0] << make_room_shift ) & MOD_MASK
    end
    -- BEGIN DEBUG
    -- c.n = c_n+1
    -- d.n = d_n
    -- msg.logf("unnormalized dividend self  == %s", Integer.debug_string(self))
    -- msg.logf("  normalized dividend c     == %s", Integer.debug_string(c))
    -- msg.logf("unnormalized divisor  other == %s", Integer.debug_string(other))
    -- msg.logf("  normalized divisor  d     == %s", Integer.debug_string(d))
    -- END DEBUG
    
    assert( drt[dre-1] >= (RADIX // 2) )-- DEBUG
    
    -- main loop
    local qhat, rhat, carry, index, temp, dr_i_qhat
    local dr_1msl = drt[dre-1] -- most significant limb of divisor (dr)
    local dr_2msl = drt[dre-2] -- 2nd most significant limb of divisor (dr)
    
    -- D2: initialize j (the loop counter)
    local de = dde-dre+1
    assert(de > 0)--DEBUG
    j = de
    -- indices for 1st, 2nd, 3rd most significant limb of dividend (dd) for current iteration
    local dd_1msl_index
    local dd_2msl_index = dde
    local dd_3msl_index = dd_2msl_index -1
    --msg.logf("d_1msl = 0x%04X, d_2msl = 0x%04X", d_1msl, d_2msl)--DEBUG
    --msg.logf("c_n = %d, d_n = %d, q_n = %d", c_n, d_n, q_n)--DEBUG
    repeat
        j = j -1
        --msg.logf("j = %d", j)--DEBUG
        dd_1msl_index = dd_2msl_index
        dd_2msl_index = dd_3msl_index
        dd_3msl_index = dd_3msl_index -1
        --msg.logf("c_1msl = 0x%04X, c_2msl = 0x%04X, c_3msl = 0x%04X", --DEBUG
        --         c[c_1msl_index], c[c_2msl_index], c[c_3msl_index])   --DEBUG
        
        -- D3: calculate qhat
        temp = (ddt[dd_1msl_index] << WIDTH) | ddt[dd_2msl_index]
        qhat = temp // dr_1msl
        -- needs extra CPU division: rhat = temp % d_1msl
        rhat = temp - qhat*dr_1msl-- hopefully a bit faster
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
            if qhat >= RADIX or qhat*dr_2msl > RADIX*rhat + ddt[dd_3msl_index] then
                --msg.logf("")--DEBUG
                --msg.logf("adjust qhat 0x%04X --> 0x%04X", qhat, qhat-1)--DEBUG
                --msg.logf("adjust rhat 0x%04X --> 0x%04X", rhat, rhat+d_1msl)--DEBUG
                qhat = qhat -1
                rhat = rhat + dr_1msl
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
            dr_i_qhat = drt[i] * qhat
            temp = ( ddt[index] - ( (dr_i_qhat & MOD_MASK) + carry ) ) & TWO_WIDTH_MASK
            ddt[index] = temp & MOD_MASK
            carry = ( (dr_i_qhat >> WIDTH) - (temp >> WIDTH) ) & MOD_MASK
            -- I can not 100% strict proof, why the carry is a difference.
            -- But multiple reasons support this.
            i = i +1
        until i == dre
        index = j+i
        temp = ddt[index] - carry
        ddt[index] = temp & MOD_MASK
        
        -- D5: Test remainder
        if temp < 0 then -- if subtracted to much
            carry = 0 -- then D7: Add back the divisor once to the dividend
            i = 0
            repeat
                index = j+i
                temp = ddt[index] + drt[i] + carry
                ddt[index] = temp & MOD_MASK
                carry = temp >> WIDTH
                i = i +1
            until i == dre
            index = j+i
            ddt[index] = ddt[index] + carry
            dt[j] = qhat - 1
        else
            dt[j] = qhat
        end
    until j == 0 -- D7: loop on j (end main loop)
    -- D8: Unnormalize (the remainder)
    -- We do not need it.
    
    -- Minimize quotient
    assert(de > 0)
    -- -- Because of the precondition |self| > |other|, we can assume, that
    -- -- the quotient is at least 1, und thus we have at least one non-zero limb.
    -- i = de - 1
    -- while q[i] == 0 do
    --     q[i] = nil
    --     i = i -1
    -- end
    -- q.n = i + 1
    
    assert(mpn.__is_valid(dt, di, de))-- DEBUG
    return de
end

-- TODO check mpn_divrem() on how it diverges between single limb division and multiple limb division

--- divides one range by another
--- 
--- The source ranges and the destination range must not overlap! (currently)
--- 
---@param dt integer[] destination range
---@param di integer   destination start index
---@param st integer[] dividend source range ("self")
---@param si integer   dividend source range ("self") start index
---@param se integer   dividend source range ("self") end index
---@param ot integer[] divisor source range ("other")
---@param oi integer   divisor source range ("other") start index
---@param oe integer   divisor source range ("other") end index
---
---@nodiscard
---@return boolean has_succeeded whether no error occurred
---@return integer|err_msg de_or_err_msg destination range end index or concrete error message
function mpn.idiv(dt, di, -- destination range
                  st, si, se, -- dividend range
                  ot, oi, oe) -- divisor range
    
    -- see GMP - mpn/generic/tdiv_qr.c - mpn_tdiv_qr()
    
    assert( mpn.__is_valid(st, si, se) )-- DEBUG
    assert( mpn.__is_valid(ot, oi, oe) )-- DEBUG
    
    local ol = oe-oi --- length of divisor
    
    if ol < 1 then -- is divisor zero
        local em = err_msg.new()
        em:append("Tried to divide by zero.")
        return em:pass_error_to_assert()
    end
    
    if ol > (se-si) then -- is dividend shorter/less than divisor?
        return true, di -- then return zero
    end
    
    if ol == 1 then
        -- single-limb/word division
        return true, mpn.__idiv_word(dt, di,
                                     st, si, se,
                                     ot[oi])
    else
        return true, mpn.__idiv_multiple_limbs(dt, di,
                                               st, si, se,
                                               ot, oi, oe)
    end
    
    -- if other.n < 1 then
    --     msg.error("Tried to divide by zero.")
    --     return di -1
    -- end
    -- if self.n < 1 then
    --     --msg.logf("divide zero by non-zero --> quotient = 0")
    --     return Integer.ZERO()
    -- end
    
    -- local compare = Integer.__compare_abs(self, other)
    -- if compare == -1 then -- |self| < |other|
    --     --msg.log("divide an absolute smaller number by an abolsute bigger number"-- DEBUG
    --     --      .." --> quotient = 0")-- DEBUG
    --     return Integer.ZERO()
    -- elseif compare == 0 then -- |self| == |other|
    --     --msg.log("divide a number by an absolute equal number --> |quotient| = 1")-- DEBUG
    --     return Integer.ABS_ONE()
    -- else -- |self| > |other|
    --     if other.n == 1 then
    --         return Integer.__div_abs___single_limb(self, other)
    --     else
    --         return Integer.__div_abs___algo_d(self, other)
    --     end       
    -- end
end

--- integer square root with remainder
---
---@param st integer[] square root range array
---@param si integer   square root range start index
---@param t  integer[] source/remainder range array
---@param i  integer   source/remainder range start index
---@param e  integer   source           range end   index
---
---@nodiscard
---@return integer se square root range end index
---@return integer re remainder   range end index
---
--- range behavior:
--- - overwrites `(t;i;e)` with the remainder `(t;i;re)`
--- - overwrites `(st;si;se)` with the square root
--- - Because the root remainder is at maximum the double of the integer root,
---   it will be `se-si +1 >= re-i >= se-si`.
function mpn.isqrt(
        st, si,
        t, i, e
    )
    
    return 42, 42
end

--- wrapper to the implementation of the square root algorithm
---
--- The actual remainder will be `{t;i;i+n}` prefixed with the `rem_overflow_bit`.
---
---@param st integer[] square root range array
---@param si integer   square root range start index
---@param t  integer[] source/remainder range array
---@param i  integer   source/remainder range start index
---@param m  integer   source range **length**
---
---@nodiscard
---@return integer rem_overflow_bit
---
--- range behavior:
--- - overwrites `(t;i;e)` with the remainder `(t;i;re)`
--- - overwrites `(st;si;se)` with the square root
--- - Because the root remainder is at maximum the double of the integer root,
---   it will be `se-si +1 >= re-i >= se-si`.
function mpn.__isqrt_wrapper(
        st, si, 
        t, i, m
    )
    
    -- CURRENTLTY THIS CODE IS ONLY A SKETCH.
    
    -- 1. left shift (t;i;e) in-place
    --    to comply the precondition
    
    local shift = mpn.clz(t, i, e) -- count of necessary bit positions to left shift the input by
    local n = m // 2 -- half length of input
    if m % 1 == 1 then
        shift = shift + WIDTH
        n = n + 1
    end
    if shift > 0 then
        e = mpn.lshift_many_unbounded(
                t, i,
                t, i, e,
                shift,
                mpn.lshift_few_bounded___leftward_impl)
    end
    return 42
end

--- implementation of the square root algorithm
---
--- The actual remainder will be `{t;i;i+n}` prefixed with the `rem_overflow_bit`.
---
---@param st integer[] square root range array
---@param si integer   square root range start index
---@param nt integer[] source/remainder range array
---@param ni integer   source/remainder range start index
---@param n  integer   half of the **even** length of the source range
---
---@nodiscard
---@return integer rem_overflow_bit
---
--- **Preconditions:**
--- - The length of the source/remainder range is even.
--- - The most significant bit of the source/remainder range is set.
---
--- range behavior:
--- - reads `(t;i;i+2*n)` as the source range
--- - overwrites `(t;i;i+n)` with the remainder (`rem_overflow_bit` omitted)
--- - overwrites `(st;si;si+n)` with the square root
function mpn.__isqrt_impl(
        st, si,
        nt, ni, n
    )
    -- We implement the recursive Karatsuba Square Root Algorithm by Paul Zimmermann
    -- as described in the following two papers:
    -- https://hal.inria.fr/inria-00072854/document
    -- https://hal.inria.fr/inria-00072113/document
    
    -- CURRENTLTY THIS CODE IS ONLY A SKETCH.
    
    -- The notation {table;main_start_index|offset;length} stands for a range
    -- in table table
    -- with the least significant limb at main_start_index + offset
    -- and  the most  significant limb at main_start_index + offset + length -1
    
    -- assert, that most significant bit of the range is set
    assert( mpn.__is_valid(t, i, i+2*n) )
    assert( t[i+2*n-1] & (1 << (WIDTH-1)) == 1, "range is not normalized")
    
    -- 1. Basecase: direct computing with builtin
    if n < 2 then
        local radicand = (t[i+1] << WIDTH) | t[i]
        local root = math.floor(math.sqrt(radicand))
        local rem = radicand - root*root
        assert( rem <= 2*root ) -- DEBUG
        st[i] = root
        t[i] = rem & MOD_MASK
        return rem >> WIDTH
    end
    
    -- variables:
    -- m   ... length of input
    --         - must be even
    -- n   ... half length of input
    -- l   ... length of the lower two quarters of input N1 and N0
    -- h   ... half length of the higher half of input N23
    --
    -- N   ... radix correspondig to n
    --         N := 2^(n*WIDTH)
    -- L   ... radix corresponding to l
    --         L := 2^(l*WIDTH)
    -- H   ... radix corresponding to h
    --         H := 2^(h*WIDTH)
    --
    -- N23 ... higher half of input (length 2*h)
    -- N1  ... 2nd quarter of input (length l)
    --         N1 < L
    -- N0  ... 1st quarter of input (length l)
    --         N1 < L
    -- 
    -- Sp  ... partial square root (length h)
    --         Sp < H
    -- Rpo ... partial square root remainder without its overflow bit rp (length h)
    --         Rpo < H
    -- Rp  ... partial square root remainder with    its overflow bit rp
    --         Rp == rp*H + Rpo
    --         Rp <= H
    -- rp  ... partial square root remainder overflow bit
    --
    -- Qto ... preliminary quotient without its overflow bit qt (length l == n-l)
    --         Qto < L
    -- Qt  ... preliminary quotient with    its overflow bit qt
    --         Qt == qt*L + Rpo
    --         Qt <= L
    -- qt  ... preliminary quotient overflow bit
    -- Ut  ... preliminary division remainder (length l)
    --         Ut < L
    -- 
    -- Qo ... quotient without its overflow bit q (length l)
    --        Qo < L
    -- Q  ... quotient with    its overflow bit q
    --        Q == q*L + Qo
    --        Q <= L
    -- q  ... quotient overflow bit
    -- Uo ... division remainder without its overflow bit (length h)
    --        Uo < H
    -- U  ... division remainder with    its overflow bit (length h)
    --        U == u*H + Uo
    --        U <= H
    -- u  ... division remainder overflow bit
    --
    -- Rto ... preliminary square root remainder without its overflow bit rt (length n)
    --         Rto < N
    -- Rt  ... preliminary square root remainder with    its overflow bit rt
    --         Rt == rt*N + Rto
    --         Rt <= N
    -- rt  ... preliminary square root remainder overflow bit
    --
    -- So ... square root without its temporary overflow bit s (length n)
    --        S < N
    -- S  ... square root with    its temporary overflow bit
    --        S == s*N + So
    --        temporary: S <= N
    --        finally  : S <  N
    -- s  ... square root temporary overflow bit
    -- Ro ... square root remainder without its overflow bit r (length n)
    --        Ro < N
    -- R  ... square root remainder with    its overflow bit r
    --        R == r*N + Ro
    --        R <= N
    -- r  ... square root remainder overflow bit
    
    -- important equalities
    -- n is |    even    |        odd
    -- -----|------------|–--------------------
    -- (1)  |   l == n/2 |       l == n/2 - 0,5
    -- (2)  | 2*l == n   | 2*l + 1 == n
    -- (3)  |   h == n/2 |       h == n/2 + 0,5
    -- (4)  | 2*h == n   |  2h - 1 == n
    -- (5)  |      h + l == n
    -- (6)  |  2*h + 2*l == 2*n == m
    
    local l = n // 2 -- length of 1st and 2nd quarter of input
    local h = n - l -- length of higher half of input
    
    -- 3. recursively compute the partial square root Sp and the partial square root remainder Rp
    --    of the higher half of the radicand N23
    -- Sp, Rp = SqrtRem( N23 )
    -- <==> Sp, rp*H + Rpo = SqrtRem( N23 )
    local rp =
            mpn.__isqrt_wrapper(-- partial root remainder Rpo into {nt;ni|2l;h}
                st, si+l, -- partial square root Sp into {st;si|l;h}
                nt, ni+2*l,  -- higher half of radicand N23 in {nt;ni|2l;2h}
                h
            )
    
    -- 3.2 correct the partial root remainder Rp
    -- if Rp > H, then Rp := Rp - Sp
    --                 <==> rp*H + Rp := rp*H + Rp - Sp
    if rp > 0 then
        mpn.sub(
            -- TODO
            -- partial root remainder Rpo into {nt;ni|2l;h}
            -- partial root remainder Rpo in {nt;ni|2l;h}
            -- partial square root Sp in {st;si|l;h}
        )
    end
    
    -- 4. divide the partial root remainder Rp and the 2nd quarter by the double of the partial square root
    -- Q, U = DivRem( Rp*L + N1, Sp )
    
    -- 4.1 divide the partial root remainder Rp and the 2nd quarter N1 by the partial square root Sp
    -- Qt, Ut = DivRem( Rp*L + N1, Sp )
    local qt =
            mpn.idivrem( -- preliminary division remainder Ut into {nt;ni|l;h}
                st, si, -- preliminary quotient Qto into {st;si|0;l}
                nt, ni+l, ni+l+n, -- partial root remainder Rpo in {nt;ni|2l;h} and the 2nd quarter N1 in {nt;ni|l;l} are together in {nt;ni|l,n}
                st, si+l, si+l+h -- partial square root is in {st;si|l;h}
            )
    
    -- 4.2 correct the preliminary division remainder (corresponds to dividing the preliminary quotient by 2)
    -- if Qt is odd, then U = Ut + Sp
    --                    <==> u*L + U = Ut + Sp
    if st[si] & 1 == 1 then
        local u =
            mpn.add_bounded(
                nt, ni+l, -- division remainder Uto into {nt;ni|l;h}
                nt, ni+l, ni+l+h, -- preliminary division remainder Ut is in {nt;ni|l;h}
                st, si+l, si+l+h, -- partial square root Sp is in {st;si|l;h}
                0 -- left-incoming carry bit
            )
    end
    
    -- 4.3 divide the preliminary quotient by 2
    -- Q = Qt // 2 
    -- <==> (qt*L + Qto) >>= 1
    mpn.rshift_few_bounded___rightward_impl(
        st, si, -- quotient Qo into {st;si|0;l}
        st, si, si+l, -- preliminary quotient Qto is in {st;si|0;l}
        1, -- shift distance
        0 -- left-incoming bits
    )
    st[si+l-1] = (qt << (WIDTH - 1)) | st[si+l-1] 
    qt = qt >> 1
    
    
    
    -- Now the square root is (st;si;se), which is composed of
    -- the partial square root in (st;l;se) and
    -- the quotient in (st;si;l).
    
    -- 5. square the quotient
    local sqr_quot_e
    sqr_quot_e = mpn.sqr(
                    t, re, -- squared quotient into (t;re;sqr_quot_e)
                    st, si, l) -- quotient is in (st;si;l)
    
    -- 6. subtraction
    local is_diff_neg
    re, is_diff_neg = mpn.diff(
                t, i, -- difference will be the root remainder into (t;i;re)
                t, i, divrem_e, -- subtrahend is the division remainder in (t;l;divrem_e) and the 1st quarter in (t;i;l)
                t, re, sqr_quot_e, -- minuend is the squared quotient in (t;re;sqr_quot_e)
                0)
    
    -- 7. correction
    if is_diff_neg then
        -- 7.1 double the square root into a temporary
        dbl_sqrt_e = mpn.lshift_few_unbounded(
                dbl_sqrt_t, 0, -- doubled square root into (dbl_sqrt_t;0;dbl_sqrt_e)
                st, si, se,
                1, 0,
                mpn.rshift_few_bounded___rightward_impl)
        -- 7.2 to the root remainder add the doubled square root
        re = mpn.add_unbounded(
                    t, i, 
                    t, i, re,
                    dbl_sqrt_t, 0, dbl_sqrt_e,
                    0)
        -- 7.3 subtract one from the root remainder
        re = mpn.sub_word(
                    t, i,
                    t, i, re,
                    1)
        -- 7.4 subtract one from the square root
        se = mpn.sub_word(
                    st, si,
                    st, si, se,
                    1)
    end
    
    return se, re
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
