---@diagnostic disable: duplicate-set-field

-- auxillary functios for the Lua-only MP library

local mp_aux = {}

local HOST_WIDTH = 0x40 -- 64 bit
local HOST_NON_NEG_WIDTH = 0x3F -- 63 bit

if (0x7FFFFFFF + 1) < 0 then
    HOST_WIDTH = 0x20 -- 32 bit
    HOST_NON_NEG_WIDTH = 0x1F -- 31 bit
end

-- HOST_WIDTH and HOST_NON_NEG_WIDTH should be considered as constant after this point.
-- Thus it is ok, that their values are captured (copied) as upvalues,
-- by the following function definitions

--- get the width of Lua integers in the host
---
---@return integer host_width width of Lua integers
function mp_aux.host_width()
    return HOST_WIDTH
end

--- get the width of non-negative Lua integers in the host
---
---@return integer host_non_neg_width width of non-negative Lua integers
function mp_aux.host_non_neg_width() 
    return HOST_NON_NEG_WIDTH
end

--- compute the count of leading zeros
--- 
--- returns 0 for negative integer `x`
--- because they are represented with the twos-complement.
--- 
---@param x integer integer as a word of width `width_arg`
---@param width_arg integer fixed width of the word `x`
---
---@nodiscard
---@return integer clz count of leading zeros of the word `x`
function mp_aux.count_leading_zeros(x, width_arg)
    assert( math.type(x) == "integer" , "argument must be an integer." )
    assert( math.type(width_arg) == "integer" , "width must be an integer")
    assert( width_arg > 0 , "width must be a positive integer." )
    assert( width_arg <= HOST_WIDTH,
            "width must be less or equal to"
          .." the host's width of non-negative integers" )
    if x < 0 then
        return 0
    end
    assert( (x >> width_arg) == 0, "argument must be less than 2^width_arg" )
    -- We perform a binary search
    -- The algorithm is ROUGHLY:
    -- 1. initialize the number of leading zeros with WIDTH
    -- 2. initialize the width with width_arg
    -- 3. half the width
    -- 4. check if x right shifted by width is zero.
    -- 5. If not so: // A bit equal or higher than the width-th bit is a 1.
    -- 6.     set x to the right shifted version
    -- 7.     subtract width from the number of leading zeros
    -- 8. repeat from 3. on while width is > 1
    -- 9. return the number of leading zeros
    local width = width_arg
    local clz = width_arg
    local temp_x
    while width > 1 do
        width = width + (width & 1) >> 1
        -- 1. round width up to next even integer
        -- 2. divide by 2 (Because of the even intger there is no remainder)
        -- Thus the formula divides by 2 and rounds UP.
        temp_x = x >> width
        if temp_x ~= 0 then
            x = temp_x
            clz = clz -width
        end
    end
    assert( width == 1 )-- DEBUG
    assert( x == 1 or x == 0 )-- DEBUG
    return clz - x
end

--- test whether an integer is a power of two
--- 
--- Note that 0 is NOT a power of two.
--- 
--- returns false for negative operands
---
---@param x integer integer to test
---
---@nodiscard
---@return boolean is_a_power_of_two whether `x` is a power of two
function mp_aux.is_power_of_two(x)
    assert( math.type(x) == "integer", "argument is not an integer")
    return (x > 0) and rawequal(x & (x-1), 0)
         -- alternative: rawequal(x & -x, x)
end

function mp_aux.sprint_value(v)
    local t = type(v)
    if t == "string" then
        return "\""..string.gsub(v, "\"", "\\\"").."\""
    elseif t == "boolean" then
        return t and "true" or "false"
    elseif t == "nil" then
        return "nil"
    else
        return tostring(v)
    end
end

-- prints a binary representation of a non-negative integer
-- no prefix, no padding, no sign, no grouping
function mp_aux.binary_from_int(int)
    assert( math.type(int) == "integer", "argument is not an integer" )
    -- right shifting of negative integer is not defined, and thus must be avoided
    local str = ""
    if int < 0 then
        int = -int
        while int & 1 == 0 do
            str = "0"..str
            int = int >> 1
        end
        str = "1"..str
        int = int >> 1
        while int ~= 0 do
            str = ((int & 1 == 0) and "1" or "0")..str
            int = int >> 1
        end
        return string.rep("1", HOST_WIDTH-string.len(str))..str
    else
        while int ~= 0 do
            str = ((int & 1 == 0) and "0" or "1")..str
            int = int >> 1
        end
        return str
    end
end

-- returns a decimal representation of an integer:
-- A certain amount of digits is grouped together.
-- Each such digit group is seperated by a space.
-- The first grouped is NOT padded.
-- The sign is provided as a prefix.
--
-- num_arg - integer to print
-- group_width (optional) - number of hexadecimal characters per group
--                          - default: 3
function mp_aux.grouped_dec_from_int(num_arg, group_width)
    assert( math.type(num_arg) == "integer", "argument is not an integer" )
    local num = (num_arg < 0) and -num_arg or num_arg
    if rawequal(group_width, nil) then
        group_width = 3
    elseif math.type(group_width) ~= "integer" then
        error("group_width must be an integer.")
    elseif group_width < 1 then
        error("group_width is less than 1.")
    end
    local chars = string.format("%u", num)
    local chars_len = string.len(chars)
    local i = chars_len
    local j = chars_len-group_width
    local str = ""
    while j > 0 do
        str = " "..string.sub(chars, j+1, i)..str
        i = j
        j = j-group_width
    end
    str = string.sub(chars, 1, i)..str
    return (num_arg < 0 and "-" or "+")..str
end

-- returns a hexadecimal representation of an integer:
-- A certain amount of digits is grouped together.
-- Each such digit group is seperated by a space.
-- The first grouped is padded with "0".
-- The sign is provided as a prefix.
--
-- num_arg - integer to print
-- group_width (optional) - number of hexadecimal characters per group
--                          - default: 4
function mp_aux.grouped_hex_from_int(num_arg, group_width)
    assert( math.type(num_arg) == "integer" )
    local num = (num_arg < 0) and -num_arg or num_arg
    if rawequal(group_width, nil) then
        group_width = 4
    elseif math.type(group_width) ~= "integer" then
        error("group_width must be an integer.")
    elseif group_width < 1 then
        error("group_width is less than 1.")
    end
    local chars = string.format("%X", num)
    local chars_len = string.len(chars)
    local i = chars_len
    local j = chars_len-group_width
    local str = ""
    while j > 0 do
        str = " "..string.sub(chars, j+1, i)..str
        i = j
        j = j-group_width
    end
    
    str = string.rep("0", -j)..string.sub(chars, 1, i)..str
    return (num_arg < 0 and "-" or "+").." 0x "..str
end

return mp_aux
