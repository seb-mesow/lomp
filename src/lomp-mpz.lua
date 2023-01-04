local msg = require("lua-only-mp-msg")
local mp_aux = require("lua-only-mp-aux")

local mpn = require("lua-only-mpn")

-- ########## Integer class ##########

-- A Integer is a sequence of "digits". Each "digit" is an integer,
-- which is greater than or equal to 0 and less than RADIX.
-- An extra field "n" (see table.pack) stores the number of words. (0 <= i < n)
-- The count of words must always be minimal.
-- An extra field "s" stores the sign of the number
-- (false if positive/zero and true if negative.)
-- An integer is zero if its field "n" is less than 1

local mpz = {}

---@version 5.3
---@class mpz
---@field private n integer
---@field private s boolean
--- 
---@operator shl:mpz
---@operator shr:mpz
---@operator unm:mpz
---@operator add:mpz
---@operator sub:mpz
---@operator mul:mpz
---@operator idiv:mpz
local __mpz = {}

local __mpz_meta = { __index = __mpz }

---@param self mpz
---
---@return boolean is_valid_ignore_sign whether the mpz is valid, ignoring the sign
function __mpz:__is_valid_ignore_sign()
    local ok = true
    ---@type integer|nil
    local self_n = self.n -- must be set to nil if self.n is zero
    
    -- check type
    if not rawequal(getmetatable(self), __mpz_meta) then
        msg.warn("Object is not an Integer,"
               .." because its metatable is not __mpz_meta.") 
        ok = false
    end
    
    -- check self.n
    local type_self_n = type(self_n)
    if rawequal(self_n, nil) then
        msg.warn("Integer has no field \"n\" for the number of digits")
        ok = false
        self_n = nil
    elseif type_self_n ~= "number" then
        msg.warnf("Integer has a field \"n\", but it is not a number."
                .." Instead it is a %s.",
                  type_self_n)
        ok = false
        self_n = nil
    else
        local math_type_self_n = math.type(self_n)
        if math_type_self_n ~= "integer" then
            msg.warnf("Integer has a field \"n\", which is a number,"
                    .." but it is not an integer. Instead it is a %s.", 
                      math_type_self_n)
            ok = false
            self_n = nil
        elseif self_n < 0 then
            msg.warnf("Integer has a negative field \"n\". It is %d .", self_n)
            ok = false
            self_n = nil
        end
    end
    
    -- check each expected integer field
    if not rawequal(self_n, nil) and self_n > 0 then
        -- no digit is at the field place self.n
        local i = self_n
        repeat
            i = i -1
            local self_i = self[i]
            local type_self_i = type(self_i)
        until i < 0 or ( type_self_i == "number" and self_i ~= 0 )
        local most_significant_field_with_non_zero_value = i
        for i = 0, self_n-1 do
            local self_i = self[i]
            if rawequal(self_i, nil) then
                msg.warnf("Integer misses some expected fields"
                        .." or its field \"n\" has a too big value:"
                      .."\nThe field \"n\" has a value of %d,"
                        .." but the expected integer field %d is missing.",
                          self_n, i)
                ok = false
            else
                local type_self_i = type(self_i)
                if type_self_i ~= "number" then
                    msg.warnf("Integer contains the expected integer field %d,"
                            .." but its value is not a number."
                          .."\nInstead it is a %s.",
                              i, type_self_i)
                    ok = false
                else
                    local math_type_self_i = math.type(self_i)
                    if math.type(self_i) ~= "integer" then
                        msg.warnf("Integer contains the expected"
                                .." integer field %d,"
                                .." but its value is not an integer."
                                .."\nInstead it is a %s.",
                                  i, math_type_self_i)
                        ok = false
                    elseif self_i >= mpn.limb_radix() then
                        msg.warnf("Integer contains the expected"
                                .." integer field %d, but its value"
                                .." 0x%04X is >= the RADIX 0x%04X .",
                                  i, self_i, mpn.limb_radix())
                        ok = false
                    elseif self_i < 0 then
                        msg.warnf("Integer contains the expected"
                                .." integer field %d,"
                                .." but its value %d is negative.", i, self_i)
                        ok = false
                    elseif most_significant_field_with_non_zero_value < 0 then 
                        -- all fields are zero
                        msg.warnf("Integer is zero and not minimal:"
                                .."\nInteger contains the field %d"
                                .." with a value of zero"
                                .." as ALL expected integer fields."
                                .."\nThus the field \"n\" must have"
                                .." a value of not %d, but better 0 .",
                                  i, self_n)
                        ok = false
                    elseif (self_i < 1)
                    and (i > most_significant_field_with_non_zero_value) then
                        msg.warnf("Integer is not minimal:"
                                .."\nInteger contains the field %d"
                                .." with a value of zero, but the most" 
                                .." significant field with a non-zero value"
                                .." is only %d ."
                                .."\nThus the field \"n\" must have"
                                .." a value of not %d, but better %d .",
                                  i, most_significant_field_with_non_zero_value,
                                  self_n, 
                                  most_significant_field_with_non_zero_value+1)
                        ok = false
                    end
                end
            end
        end
    end
    
    -- check each field, especially alls fields with integer keys
    for k,v in pairs(self) do
        type_k = type(k)
        type_v = type(v)
        if ( type_k == "string" ) then
            -- check string field
            if k ~= "n" and k ~= "s" then
                msg.warnf("Integer contains an unused string field:"
                      .."\n[%s (%s)] == %s (%s)",
                          k, type_k, v, type_v)
                ok = false
            end
        elseif (type_k == "number") then
            -- check numeric key
            local math_type_k = math.type(k)
            if (math_type_k ~= "integer") then
                msg.warnf("Integer contains an unused number field:"
                      .."\n[%s (%s)] == %s (%s)",
                          k, type_k, v, math_type_k)
                ok = false
            elseif k < 0 then
                msg.warnf("Integer contains the unexpected"
                        .." negative integer field %d .", k)
                ok = false
            elseif rawequal(self_n, nil) then
                msg.warnf("Integer's field \"n\" is \"defunct\""
                        .." and Integer contains the thus unexpected"
                        .." integer field %s", k)
                ok = false
            elseif k >= self_n then
                msg.warnf("Integer contains the unexpected integer field %d,"
                        .." which is >= self.n == %d .", k, self_n)
                ok = false
            end
        else
            -- unused field
            msg.warnf("Integer contains an unused field:"
                    .."\n[%s (%s)] == %s (%s)",
                      mp_aux.sprint_value(k), type_k, 
                      mp_aux.sprint_value(v), type_v)
            ok = false
        end
    end
    
    return ok
end

function __mpz:__is_valid_sign()
    local ok = true
    local self_s = self.s
    
    if rawequal(self_s, nil) then
        msg.warn("Integer has no field \"s\" for the sign.")
        ok = false
    else
        local type_self_s = type(self_s)
        if type_self_s ~= "boolean" then
            msg.warnf("Integer has a field \"s\", but it is not a boolean."
                    .." Instead it is a %s.", type(self.s))
            ok = false
        else
            local self_n = self.n
            if (type(self_n) == "number")
            and (math.type(self_n) == "integer") 
            and (self_n < 1)
            and (self_s) then
                msg.warnf("Integer is zero, but its sign field \"s\" is true"
                        .." (which indicates a negative Integer).")
                ok = false
            end
        end
    end
    
    return ok
end

-- checks if an Integer is well formed according to the previous definition
-- but contains no sign yet
function __mpz:__is_valid_excl_sign()
    local ok = __mpz.__is_valid_ignore_sign(self)
    local self_s = self.s
    if not rawequal(self_s, nil) then
        msg.warnf("Integer already contains the field \"s\" for the sign,"
                .." which is %s (=^= %s)."
              .."\nBut because __mpz:__is_valid_excl_sign() was called,"
              .."\nthe field \"s\" for the sign is not already expected.",
                  self_s, self_s and "negative" or "non-negative")
        ok = false
    end
    if not ok then
        msg.warnf_callstack("\nThe invalid Integer is\n%s", tostring(self))
    end
    return ok
end

-- checks if an Integer is well formed according to the previous definition
function __mpz:__is_valid()
    local ok = __mpz.__is_valid_ignore_sign(self)
    ok = __mpz.__is_valid_sign(self) and ok
    if not ok then
        msg.warnf_callstack("\nThe invalid Integer is\n%s", tostring(self))
    end
    return ok
end


-- internal constructor:
-- creates a new number from an integer
-- Postconditions:
--      self:__is_valid()
function __mpz.__new_impl(int)
    local self = setmetatable({}, __mpz_meta)
    if int < 0 then
        self.s = true
        int = -int
        -- In modular arithmetic math.mininteger is its own negative (as also 0)
        if int < 0 then -- handle math.mininteger special
            assert( (int-1) == math.maxinteger )-- DEBUG
            assert( (int-1) >= 0 )-- DEBUG
            self.n = mpn.split_lua_int(self, 0, -- destination
                                       int-1) -- == math.maxinteger
            -- TODO use mpn.add_1()
            self.n = mpn.add(self, 0, -- destination
                             self, 0, self.n, -- augend source
                             {}, 0, 0, -- addend source
                             1)-- right incoming carry)
            assert(self:__is_valid())-- DEBUG
            return self
        end
    else
        self.s = false
    end
    self.n = mpn.split_lua_int(self, 0, -- destination
                               int)
    assert(self:__is_valid())-- DEBUG
    return self
end

-- Constructor:
-- constructs an Integer, floats are rounded in an undefined way
function mpz.new(int)
    if math.type(int) == "integer" then
        return __mpz.__new_impl(int)
    end
    msg.error("argument must be an integer"
            .." (neither a float nor something other)")
end

-- Preconditons:
--     self:__is_valid_excl_sign()
-- Postconditons:
--     copy:__is_valid_excl_sign()
function mpz:__copy_abs()
    local copy = setmetatable({
        n = self.n ;
    }, __mpz_meta)
    for i=0, self.n-1 do
        -- Because the limit is evaluated only once,
        -- a for loop with limit self.n -1 is still faster than a while loop.
        copy[i] = self[i]
    end
    assert(copy:__is_valid_excl_sign())-- DEBUG
    return copy
end

-- Constants
-- are independent of WIDTH, because contain no limbs
-- or at maximum one limb of value 1 and every width creates limbs,
-- that hold at least 1

-- We must provided them as functions, because as returned tables,
-- they may be changed after returning them.
function mpz.ZERO()
    return setmetatable({ s = false ; n = 0 ; }, __mpz_meta)
end
function mpz.ONE()
    return setmetatable({ s = false ; n = 1 ; [0] = 1 }, __mpz_meta)
end
function mpz.ABS_ONE()
    return setmetatable({ n = 1 ; [0] = 1 }, __mpz_meta)
end


-- Postconditions:
--      obj:__is_valid()
function mpz.__ensure_is_Integer(obj)
    if getmetatable(obj) == __mpz_meta then
        return obj
    end
    return mpz.new(obj)
end

-- for debugging
function mpz:__debug_string___limb_str_objs_comp(other)
    return self.k > other.k
end

-- works also on invalid Integer
function mpz:__debug_string(mpn_debug_string_func)
    local str = ""
    if rawequal(self.s, nil) then
        str = "(no sign)"
    else
        str = self.s and "-" or "+"
    end
    if rawequal(self.n, nil) then
        return str.." (no length)" -- print indicator, but still print "limbs"
    end
    return str.." "..mpn_debug_string_func(self, 0, self.n)
end

function mpz:debug_string_bin()
    return mpz.__debug_string(self, mpn.debug_string_bin)
end
function mpz:debug_string_oct()
    return mpz.__debug_string(self, mpn.debug_string_oct)
end
function mpz:debug_string_dec()
    return mpz.__debug_string(self, mpn.debug_string_dec)
end
function mpz:debug_string_hex()
    return mpz.__debug_string(self, mpn.debug_string_hex)
end
  mpz.debug_string    = mpz.debug_string_hex
__mpz.debug_string    = mpz.debug_string
__mpz_meta.__tostring = mpz.debug_string -- conversion to string with tostring()



--- tries to convert a Lua integer into a mpz<br>
--- If the mpz does not fit into a Lua integer, returns nil.
---
--- Preconditons:
--- - `self:__is_valid()`
---
---@param self mpz
---
---@nodiscard
---@return integer|nil lua_int Lua Integer
function __mpz:try_to_lua_int()
    assert( self:__is_valid() )-- DEBUG
    local int = mpn.try_to_lua_int(self, 0, self.n)
    -- mpn.try_to_lua_int() returns math.mininteger,
    -- if the range == abs(math.mininteger) ;
    -- thus if abs(self) == abs(math.mininteger) .
    if not rawequal(int, nil) then
        if int < 0 then
            if not self.s then
                -- implicitly return nil, because abs(math.mininteger) can not
                -- be represented in a Lua integer
                return -- implicitly return nil
            end
        elseif self.s then
            return -int
        end
    end
    return int
end

-- returns a Lua integer from the natural integer
-- If the natural integer does not fit into a Lua integer,
-- raises a warning and returns math.maxinteger resp. math.mininteger
-- Preconditons:
--     self:__is_valid()
function __mpz:to_lua_int()
    assert( self:__is_valid() )-- DEBUG
    local int = mpz.try_to_lua_int(self)
    if rawequal(int, nil) then
        local int_descr
        if self.s then
            int = math.mininteger ; int_descr = "math.mininteger"
        else
            int = math.maxinteger ; int_descr = "math.maxinteger"
        end
        msg.warnf("mpz is too big to represent as a Lua integer."
                .."\nreturning %s"
                .."\nThe too big mpz is:\n%s",
                  int_descr, self)
    end
    return int
end

-- compares two integers
-- if self <  other, return -1
-- if self == other, return  0
-- if self >  other, return +1
-- Preconditions:
--     self:__is_valid()
--     other:__is_valid()
function mpz:cmp(other)
    self  = mpz.__ensure_is_Integer(self )
    other = mpz.__ensure_is_Integer(other)
    if self.s then
        if other.s then
            return mpn.cmp(other, 0, other.n,
                            self, 0,  self.n)
        else
            return -1
        end
    else
        if other.s then
            return 1
        else
            return mpn.cmp( self, 0,  self.n,
                           other, 0, other.n)
        end
    end
end
-- cmp() not provided as member function by intention

function mpz:less(other)
    return mpz.cmp(self, other) == -1
end
function mpz:less_equal(other)
    return mpz.cmp(self, other) ~= 1
end
function mpz:equal(other)
    return mpz.cmp(self, other) == 0
end
function mpz:greater_equal(other)
    return mpz.cmp(self, other) ~= -1
end
function mpz:greater(other)
    return mpz.cmp(self, other) == 1
end

-- deep copy
-- Preconditons:
--     self:__is_valid()
-- Postconditions:
--     copy:__is_valid()
--     copy == self
function mpz:copy()
    assert( self:__is_valid() , "self")-- DEBUG
    local copy = setmetatable({ s = self.s }, __mpz_meta)
    copy.n = mpn.copy(copy, 0, -- destination
                      self, 0, self.n) -- source
    assert( copy:__is_valid() )-- DEBUG
    assert( mpz.equal(self, copy) , "copy")-- DEBUG
    return copy
end
__mpz.copy = mpz.copy

-- absolute value
function mpz:abs()
    assert( self:__is_valid() , "self")-- DEBUG
    local copy = setmetatable({ s = false }, __mpz_meta)
    copy.n = mpn.copy(copy, 0, -- destination
                      self, 0, self.n) -- source
    assert( copy:__is_valid() , "copy")-- DEBUG
    return copy
end
__mpz.abs = mpz.abs

-- unary negation operator
-- Preconditions:
--     self:__is_valid()
-- Postconditions:
--     copy:__is_valid()
function mpz:neg()
    assert( self:__is_valid() , "self")-- DEBUG
    local copy = setmetatable({}, __mpz_meta)
    copy.n = mpn.copy(copy, 0, -- destination
                      self, 0, self.n) -- source
    if copy.n < 1 then
        copy.s = false
    else
        copy.s = not self.s
    end
    assert( copy:__is_valid() , "copy")-- DEBUG
    return copy
end
__mpz.neg = mpz.neg
__mpz_meta.__unm = mpz.neg

-- shifts an integer by s bits to the left
-- This may add limbs at the most significant end.
function mpz:__lshift(res, s)
    assert( s > 0 )-- DEBUG
    local n = mpn.lshift_many_unbounded(res, 0, -- destination
                                        self, 0, self.n, -- source
                                        s) -- left shift amount
    local nm1 = n -1
    if rawequal(res[nm1], 0) then
        res[nm1] = nil 
        res.n = nm1
    else
        res.n = n
    end
    return res
end

-- shifts an integer by s bits to the right
-- This may discards some limbs at the least significant end
function mpz:__rshift(res, s)
    assert( s > 0 )-- DEBUG
    -- local n = mpn.rshift_many_bounded(
    --         res, 0, -- destination for the integer part of the shifted copy
    --         {}, 0, -- destination for the fractional part of the shifted copy
    --         self, 0, self.n, -- source
    --         s) -- right shift amount
    local n = mpn.rshift_many_discard(
            res, 0, -- destination for the integer part of the shifted copy
            self, 0, self.n, -- source
            s) -- right shift amount
    local nm1 = n -1
    if rawequal(res[nm1], 0) then
        res[nm1] = nil 
        res.n = nm1
    else
        res.n = n
    end
    return res
end

function mpz:lshift(s)
    assert( math.type(s) == "integer", "shift amount must be an integer.")
    assert( self:__is_valid() , "self")-- DEBUG
    if (self.n < 1) or (s == 0) then
        return mpz.copy(self)
    end
    local res = setmetatable({}, __mpz_meta)
    if s > 0 then
        mpz.__lshift(self, res, s)
        res.s = self.s
    else
        mpz.__rshift(self, res, -s)
        if res.n < 1 then
            res.s = false
        else
            res.s = self.s
        end
    end
    assert( res:__is_valid() , "res")-- DEBUG
    return res
end
__mpz.lshift = mpz.lshift
__mpz_meta.__shl = mpz.lshift

function mpz:rshift(s)
    assert( math.type(s) == "integer", "shift amount must be an integer.")
    assert( self:__is_valid() , "self")-- DEBUG
    if (self.n < 1) or (s == 0) then
        return mpz.copy(self)
    end
    local res = setmetatable({}, __mpz_meta)
    if s > 0 then
        mpz.__rshift(self, res, s)
        if res.n < 1 then
            res.s = false
        else
            res.s = self.s
        end
    else
        mpz.__lshift(self, res, -s)
        res.s = self.s
    end
    assert( res:__is_valid() , "res")-- DEBUG
    return res
end
__mpz.rshift = mpz.rshift
__mpz_meta.__shr = mpz.rshift

function mpz:__add_impl(other)
    local res = setmetatable({}, __mpz_meta)
    
    if self.n < other.n then
        self, other = other, self
    end
    local n, carry = mpn.add(res, 0, -- destination
                             self, 0, self.n, -- augend
                             other, 0, other.n, -- addend
                             0) -- right incoming carry
    if carry > 0 then
        res[n] = 1
        res.n = n +1
    else
        res.n = n
    end
    res.s = self.s
    
    assert( res:__is_valid() )-- DEBUG
    return res
end

-- from the absolute value of self subtracts the absolute value of other
-- In contrast to __add_abs() it also sets the sign
-- Preconditions:
--     self:__is_valid_excl_sign()
--     other:__is_valid_excl_sign()
-- Postconditions:
--     res:__is_valid()
function mpz:__sub_impl(other)
    local res = setmetatable({}, __mpz_meta)
    
    res.n, res.s = mpn.difference(res, 0, -- destination
                                self, 0, self.n, -- 1st source
                                other, 0, other.n, -- 2nd source
                                0) -- right incoming borrow
    
    -- TODO avoid that an Integer must be minimal
    -- minimize result
    n = res.n -1
    while n >= 0 and res[n] <= 0 do
        res[n] = nil
        n = n -1
    end
    res.n = n +1
    
    assert( res:__is_valid() )-- DEBUG
    return res
end

-- addition
-- Preconditions:
--     self:__is_valid()
--     other:__is_valid()
-- Postconditions:
--     res:__is_valid()
function mpz:add(other)
    self = mpz.__ensure_is_Integer(self)
    other = mpz.__ensure_is_Integer(other)
    
    -- In the comments s and o are the absolute values of self and other. 
    
    local self_s = self.s
    if self_s == other.s then
        -- self and other are non-negative
        -- ( +s + +o == s + o with s >= 0 and o >= 0 )
        -- self and other are negative
        -- ( -s + -o == -(s + o) with s >= 1 and o >= 1 )
        return mpz.__add_impl(self, other)
    elseif self_s then
        -- self is negative, other is non-negative
        -- ( -s + +o == o - s with s >= 1 and o >= 0 )
        return mpz.__sub_impl(other, self)
    end
    -- self is non-negative, other is negative
    -- ( +s + -o == s - o with s >= 0 and o >= 1 )
    return mpz.__sub_impl(self, other)
end
__mpz_meta.__add = mpz.add

-- subtraction
-- Preconditions:
--     self:__is_valid()
--     other:__is_valid()
-- Postconditions:
--     res:__is_valid()
function mpz:sub(other)
    self = mpz.__ensure_is_Integer(self)
    other = mpz.__ensure_is_Integer(other)
    
    local self_s = self.s
    if self_s ~= other.s then
        -- self is non-negative, other is negative
        -- ( +s - -o == s + o with s >= 0 and o >= 1 )
        -- self is negative, other is non-negative
        -- ( -s - +o == -(s + o) with s >= 1 and o >= 0 )
        return mpz.__add_impl(self, other)
    elseif self_s then
        -- self and other are negative
        -- ( -s - -o == o - s with s >= 1 and o >= 1 )
        return mpz.__sub_impl(other, self)
    end
    -- self and other are non-negative
    -- ( +s - +o == s - o with s >= 0 and o >= 0 )
    return mpz.__sub_impl(self, other)
end
__mpz_meta.__sub = mpz.sub

-- multiplication
-- Preconditions:
--     self:__is_valid()
--     other:__is_valid()
-- Postconditions:
--     res:__is_valid()
function mpz:mul(other)
    self = mpz.__ensure_is_Integer(self)
    other = mpz.__ensure_is_Integer(other)
    
    local res = mpz.__mul_abs(self, other)
    
    if res.n < 1 then-- DEBUG
        assert( res:__is_valid() )-- DEBUG
    else-- DEBUG
        assert( res:__is_valid_excl_sign() )-- DEBUG
    end-- DEBUG
    
    if res.n > 0 then
        res.s = self.s ~= other.s
        -- res. s == false if
        --    1. self and other are negative     ( -a * -b == +(a * b) with a >= 1 and b >= 1 )
        -- or 2. self and other are non-negative ( +a * +b == +(a * b) with a >= 0 and b >= 0 )
        -- res. s == true if
        --    1. self is negative    , other is non-negative ( -a * +b == -(a * b) with a >= 1 and b >= 0 )
        -- or 2. self is non-negative, other is negative     ( +a * -b == -(a * b) with a >= 0 and b >= 1 )
    end
    
    assert(res:__is_valid_sign())-- DEBUG
    return res
end
__mpz_meta.__mul = mpz.mul

-- divides the absolute values |self| / |other|
-- If the quotient is zero, then it also sets the sign
-- In contrast to the Lua specification it rounds to zero (and not towards minus infinity)
-- Preconditions:
--     self:__is_valid()
--     other:__is_valid()
-- Postconditions:
--     if self.n < 1 then res:__is_valid_()
--     else               res:__is_valid_excl_sign()
function mpz:__div_abs(other)
    if other.n < 1 then
        msg.error("Tried to divide by zero.")
        return
    end
    if self.n < 1 then
        --msg.logf("divide zero by non-zero --> quotient = 0")
        return mpz.ZERO()
    end
    
    assert( self.n > 0 )-- DEBUG
    assert( other.n > 0 )-- DEBUG
    local compare = mpz.__compare_abs(self, other)
    if compare == -1 then -- |self| < |other|
        --msg.log("divide an absolute smaller number by an abolsute bigger number"-- DEBUG
        --      .." --> quotient = 0")-- DEBUG
        return mpz.ZERO()
    elseif compare == 0 then -- |self| == |other|
        --msg.log("divide a number by an absolute equal number --> |quotient| = 1")-- DEBUG
        return mpz.ABS_ONE()
    else -- |self| > |other|
        if other.n == 1 then
            return mpz.__div_abs___single_limb(self, other)
        else
            return mpz.__div_abs___algo_d(self, other)
        end       
    end
end

-- division
-- Preconditions:
--     self:__is_valid()
--     other:__is_valid()
-- Postconditions:
--     res:__is_valid()
function mpz:div(other)
    self = mpz.__ensure_is_Integer(self)
    other = mpz.__ensure_is_Integer(other)
    
    local res = mpz.__div_abs(self, other)
    if res.n ~= 0 then
        assert(res:__is_valid_excl_sign())-- DEBUG
        res.s = self.s ~= other.s
        -- res. s == false if
        --    1. self and other are negative     ( -a // -b == +(a // b) with a >= 1 and b >= 1 )
        -- or 2. self and other are non-negative ( +a // +b == +(a // b) with a >= 0 and b >= 0 )
        -- res. s == true if
        --    1. self is negative    , other is non-negative ( -a // +b == -(a // b) with a >= 1 and b >= 0 )
        -- or 2. self is non-negative, other is negative     ( +a // -b == -(a // b) with a >= 0 and b >= 1 )
        assert(res:__is_valid_sign())-- DEBUG
    else
        assert(res:__is_valid())-- DEBUG
    end
    
    return res
end
__mpz_meta.__idiv = mpz.div

-- square root
-- Preconditions:
--     self:__is_valid()
--     other:__is_valid()
-- Postconditions:
--     res:__is_valid()
function mpz:sqrt()
    self = mpz.__ensure_is_Integer(self)
    
    if self.s then
        msg.error("Tried to take the square root of a negative number.")
        return
    else
        return mpz.__sqrt_abs(self)
    end
end


local DIGITS_UPPERCASE = {
    [0] = "0";"1";"2";"3";"4";"5";"6";"7";"8";"9";"A";"B";"C";"D";"E";"F"}
local DIGITS_LOWERCASE = {
    [0] = "0";"1";"2";"3";"4";"5";"6";"7";"8";"9";"a";"b";"c";"d";"e";"f"}

-- converts an Integer to a decimal string
function __mpz:dec()
    if self.n == 0 then
        return "0"
    end
    
    -- adapted from the GMP source file
    -- mpn/generic/get_str.c - function mpn_bc_get_str - branch /* not base 10 */
    
    local str = ""
    local y = mpz.__copy_abs(self)
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
function mpz.__str_in_pow_of_2_radix(self, bits_per_digit, digit_mask, digits)
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
        self_n*WIDTH - mpz.__count_leading_zeros(self_i, WIDTH)
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

function __mpz:hex()
    return mpz.__str_in_pow_of_2_radix(self, 4, 0xF, DIGITS_UPPERCASE)
end
mpz.hex = __mpz.hex

function __mpz:hex_lowercase()
    return mpz.__str_in_pow_of_2_radix(self, 4, 0xF, DIGITS_LOWERCASE)
end
mpz.hex_lowercase = __mpz.hex_lowercase

function __mpz:oct()
    return mpz.__str_in_pow_of_2_radix(self, 3, 7, DIGITS_UPPERCASE)
end
mpz.oct = __mpz.oct

return mpz
