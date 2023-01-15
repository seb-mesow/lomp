---@diagnostic disable: invisible

local msg = require("lomp-msg")
local err_msg = require("lomp-err_msg")
local mp_aux = require("lomp-aux")

local mpn = require("lomp-mpn")

-- ########## Integer class ##########

-- A Integer is a sequence of "digits". Each "digit" is an integer,
-- which is greater than or equal to 0 and less than RADIX.
-- An extra field "n" (see table.pack) stores the number of words. (0 <= i < n)
-- The count of words must always be minimal.
-- An extra field "s" stores the sign of the number
-- (false if positive/zero and true if negative.)
-- An integer is zero if its field "n" is less than 1

---@version 5.3
local mpz = {}

---@class mpz
---@field private n integer end index / count of limbs
---@field private s boolean sign (true if negative, false if positive or zero)
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

---@private
---
--- asserts, that the `mpz` complies with the specification
--- But the sign is not checked.
---
---@nodiscard
---@return boolean ok whether the `mpz` is valid, ignoring the sign
---@return err_msg? err_msg describes the errors
function __mpz:__is_valid_ignore_sign()
    local em = err_msg.new()
    ---@type integer?
    local self_n = self.n -- must be set to nil if self.n is zero
    
    -- check type
    if not rawequal(getmetatable(self), __mpz_meta) then
        em:append("The object is not an mpz,"
                .." because its metatable is not __mpz_meta.")
    end
    
    -- check self.n
    local type_self_n = type(self_n)
    if rawequal(self_n, nil) then
        em:append("The mpz has no field \"n\" for the number of digits")
        self_n = nil
    elseif type_self_n ~= "number" then
        em:appendf("The mpz has a field \"n\", but it is not a number."
                 .." Instead it is a %s.",
                   type_self_n)
        self_n = nil
    else
        local math_type_self_n = math.type(self_n)
        if math_type_self_n ~= "integer" then
            em:appendf("The mpz has a field \"n\", which is a number,"
                     .." but it is not a Lua integer. Instead it is a %s.", 
                       math_type_self_n)
            self_n = nil
        elseif self_n < 0 then
            em:appendf("The mpz has a negative field \"n\". It is %d .", self_n)
            self_n = nil
        end
    end
    
    -- check each expected integer field
    if (not rawequal(self_n, nil)) and (self_n > 0) then
        ---@cast self_n -nil
        local _, mpn_is_valid_em = mpn.__is_valid(self, 0, self_n)
        em:append(mpn_is_valid_em)
        
        local left_most_non_zero_index = mpn.find_left_most_non_zero_limb(self, 0, self_n)
        if left_most_non_zero_index ~= self_n - 1 then
            em:appendf("The mpz is not minimal:"
                   .."\nself.n == %d, but the left most non-zero limb is at %d .",
                        self_n, left_most_non_zero_index)
        end
    end
    
    -- check each field, especially all fields with integer keys
    for k,v in pairs(self) do
        local type_k = math.type(k) or type(k)
        local type_v = math.type(v) or type(v)
        if type_k == "string" then
            -- check string field
            if (k ~= "n") and (k ~= "s") then
                em:appendf("The mpz contains an unused string field:"
                       .."\n[%s (%s)] == %s (%s)",
                            k, type_k, v, type_v)
            end
        elseif type_k == "integer" then
            if k < 0 then
                em:appendf("The mpz contains the unexpected"
                         .." negative integer field %d .", k)
            elseif rawequal(self_n, nil) then
                em:appendf("The mpz's field \"n\" is \"defunct\""
                         .." and the mpz contains the thus unexpected"
                         .." integer field %d", k)
            elseif k >= self_n then
                em:appendf("The mpz contains the unexpected integer field %d,"
                         .." which is >= self.n == %d .", k, self_n)
            end
        else
            -- unused field
            em:appendf("The mpz contains an unused field:"
                   .."\n[%s (%s)] == %s (%s)",
                       mp_aux.sprint_value(k), type_k, 
                       mp_aux.sprint_value(v), type_v)
        end
    end
    
    return em:pass_to_assert()
end


---@private
---
--- asserts, that the sign of the `mpz` complies with the specification
---
---@nodiscard
---@return boolean ok whether the sign is valid
---@return err_msg? err_msg describes the errors
function __mpz:__is_valid_sign()
    local em = err_msg.new()
    
    local self_s = self.s
    local type_self_s = math.type(self_s) or type(self_s)
    
    if type_self_s == "nil" then
        em:append("The mpz has no field \"s\" for the sign.")
    elseif type_self_s ~= "boolean" then
        em:appendf("The mpz has a field \"s\", but it is not a boolean."
                 .." Instead it is a %s.", type(self.s))
    else
        local self_n = self.n
        if (type(self_n) == "number")
        and (math.type(self_n) == "integer") 
        and (self_n < 1)
        and (self_s) then
            em:appendf("The mpz is zero, but its sign field \"s\" is true"
                     .." (which indicates a negative Integer).")
        end
    end
    
    return em:pass_to_assert()
end

---@private
---
--- asserts, that the `mpz` complies with the specification
--- 
--- The sign is not checked and no expected:
--- If the `mpz` has a sign, then a warning is raised.
---
---@nodiscard
---@return boolean ok whether the `mpz` is valid without the sign
---@return err_msg? err_msg describes the errors
function __mpz:__is_valid_excl_sign()
    local em = err_msg.new()
    
    local ok = __mpz.__is_valid_ignore_sign(self)
    local self_s = self.s
    if not rawequal(self_s, nil) then
        em:appendf("The mpz already contains the field \"s\" for the sign,"
                 .." which is %s (=^= %s)."
               .."\nBut because __mpz:__is_valid_excl_sign() was called,"
               .."\nthe field \"s\" for the sign is not already expected.",
                   self_s, self_s and "negative" or "non-negative")
    end
    if not ok then
        em:appendf("\nThe invalid mpz is\n%s", tostring(self))
    end
    
    return em:pass_to_assert()
end

---@private
---
--- asserts, that the `mpz` fully complies with the specification
---
---@nodiscard
---@return boolean ok whether the `mpz` is fully valid
---@return err_msg? err_msg describes the errors
function __mpz:__is_valid()
    local _, em = __mpz.__is_valid_ignore_sign(self)
    if rawequal(em, nil) then
        em = err_msg.new()
    end
    ---@cast em -nil
    local _, sign_em = __mpz.__is_valid_sign(self)
    em:append(sign_em)
    if em:has_error() then
        em:appendf("The invalid mpz is\n%s", tostring(self))
    end
    return em:pass_to_assert()
end

---@private
---
--- creates a new `mpz` from a Lua integer
---
---@param int integer Lua integer
---
---@nodiscard
---@return mpz new_mpz constructed `mpz` object
--- 
--- Postconditions:
--- - `new_mpz:__is_valid()`
function mpz.__new(int)
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
            -- TODO use mpn.add_owrd_unbounded()
            self.n = mpn.add_unbounded(self, 0,         -- destination
                                       self, 0, self.n, -- augend source
                                       {}  , 0, 0     , -- addend source
                                       1)-- right incoming carry)
            assert(self:__is_valid())-- DEBUG
            return self
        end
    else
        self.s = false
    end
    self.n = mpn.split_lua_int(self, 0, -- destination
                               int)
    assert( self:__is_valid() )-- DEBUG
    return self
end

---@private
---
--- deep copies the absolute value
---
---@param self mpz
---
---@nodiscard
---@return mpz abs_copy deep copy with the absolute value
--- 
--- Preconditons:
--- - `self:__is_valid_ignore_sign()`
---
--- Postconditons:
--- - `abs_copy:__is_valid_excl_sign()`
function mpz.__copy_abs(self)
    assert( self:__is_valid_ignore_sign() )-- DEBUG
    local copy = setmetatable({
        n = self.n ;
    }, __mpz_meta)
    for i=0, self.n-1 do
        -- Because the limit is evaluated only once,
        -- a for loop with limit self.n -1 is still faster than a while loop.
        copy[i] = self[i]
    end
    assert( copy:__is_valid_excl_sign() )-- DEBUG
    return copy
end

--- deep copies a `mpz`
---
---@param self mpz
---
---@nodiscard
---@return mpz copy deep copy
--- 
--- Preconditons:
--- - `self:__is_valid()`
---
--- Postconditons:
--- - `copy:__is_valid()`
function mpz.__copy(self)
    assert( self:__is_valid() )-- DEBUG
    local copy = mpz.__copy_abs(self)
    copy.s = self.s
    assert( copy:__is_valid() )-- DEBUG
    return copy
end

--- deep copies a `mpz` or constructs a new `mpz` from a Lua Integer
---
---@param mpz_or_lua_int mpz|integer other `mpz` or Lua integer
---
---@nodiscard
---@return mpz copy copied or newly constructed `mpz`
---
--- Postconditions:
--- - `copy:__is_valid()`
function mpz.copy(mpz_or_lua_int)
    if getmetatable(mpz_or_lua_int) == __mpz_meta then
        ---@cast mpz_or_lua_int mpz
        return mpz.__copy(mpz_or_lua_int)
    end
    ---@cast mpz_or_lua_int integer
    return mpz.__new(mpz_or_lua_int)
end
mpz.new = mpz.copy

---@private
---
--- returns a `mpz` with the same value as its argument
---
---@param mpz_or_int mpz|integer operand
---
---@return mpz op_mpz operand as `mpz`
--- 
--- Preconditons:
--- - if `mpz_or_int` is of type `mpz`, then `mpz_or_int:__is_valid()`
--- 
--- Postconditions:
--- - `op_mpz:__is_valid()`
function mpz.__ensure_is_mpz(mpz_or_int)
    if getmetatable(mpz_or_int) == __mpz_meta then
        ---@cast mpz_or_int mpz
        return mpz_or_int -- do not deep copy, just pass reference
    end
    ---@cast mpz_or_int integer
    return mpz.__new(mpz_or_int)
end

-- Constants
-- are independent of WIDTH, because contain no limbs
-- or at maximum one limb of value 1 and every width creates limbs,
-- that hold at least 1

-- We must provided them as functions, because as returned tables,
-- they may be changed after returning them.

---@deprecated
---@return mpz zero `mpz` with the value 0 (has a sign)
function mpz.ZERO()
    return setmetatable({ s = false ; n = 0 ; }, __mpz_meta)
end

---@deprecated
---@return mpz one positive `mpz` with the value 1
function mpz.ONE()
    return setmetatable({ s = false ; n = 1 ; [0] = 1 }, __mpz_meta)
end

---@deprecated
---@return mpz abs_one `mpz` with **no sign** and the absolute value 1
function mpz.ABS_ONE()
    return setmetatable({ n = 1 ; [0] = 1 }, __mpz_meta)
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

---@return string
function mpz:debug_string_bin()
    return mpz.__debug_string(self, mpn.debug_string_bin)
end
---@return string
function mpz:debug_string_oct()
    return mpz.__debug_string(self, mpn.debug_string_oct)
end
---@return string
function mpz:debug_string_dec()
    return mpz.__debug_string(self, mpn.debug_string_dec)
end
---@return string
function mpz:debug_string_hex()
    return mpz.__debug_string(self, mpn.debug_string_hex)
end
  mpz.debug_string    = mpz.debug_string_hex
__mpz.debug_string    = mpz.debug_string
__mpz_meta.__tostring = mpz.debug_string -- conversion to string with tostring()



--- tries to convert a Lua integer into a mpz
---
--- If the `mpz` does not fit into a Lua integer, returns `nil`.
---
---@nodiscard
---@return integer|nil opt_int Lua Integer or `nil`
--- 
--- Preconditons:
--- - `self:__is_valid()`
function __mpz:try_to_lua_int()
    assert( self:__is_valid() )-- DEBUG
    local int = mpn.try_to_lua_int(self, 0, self.n)
    -- mpn.try_to_lua_int() returns math.mininteger,
    -- if the range == abs(math.mininteger) ;
    -- thus if abs(self) == abs(math.mininteger) .
    if rawequal(int, nil) then
        return
    end
    if int < 0 then
        -- Here we know, that self == -+ math.mininteger.
        if self.s then
            -- self == math.mininteger
            return int
        end
        -- implicitly return nil, because self == -math.mininteger can not
        -- be represented in a Lua integer
        return -- implicitly return nil
    elseif self.s then
        return -int
    end
    return int
end

--- converts a `mpz` to a Lua integer
--- 
--- If the `mpz` does not fit into a Lua integer,
--- raises a warning and returns `math.maxinteger` resp. `math.mininteger`
--- according to the sign of the `mpz`
---
---@nodiscard
---@return integer int Lua_integer
--- 
--- Preconditons:
--- - `self:__is_valid()`
function __mpz:to_lua_int()
    assert( self:__is_valid() )-- DEBUG
    local int = __mpz.try_to_lua_int(self)
    if rawequal(int, nil) then
        local int_descr
        if self.s then
            int = math.mininteger ; int_descr = "math.mininteger"
        else
            int = math.maxinteger ; int_descr = "math.maxinteger"
        end
        msg.warnf("mpz is too big to represent as a Lua integer."
              .."\nreturning %s"
            .."\n\nThe too big mpz is:\n%s",
                  int_descr, self)
    end
    ---@cast int -nil
    return int
end

--- compares two integers
---
--- returns -1 if `self <  other`<br>
--- returns  0 if `self == other`<br>
--- returns +1 if `self >  other`
--- 
---@param self  mpz|integer 1st operand
---@param other mpz|integer 2nd operand
---
---@nodiscard
---@return integer cmp_res integer descriping the relation of self to other
--- 
--- Preconditions:
--- - `self:__is_valid()`
--- - `other:__is_valid()`
function mpz.cmp(self, other)
    self  = mpz.__ensure_is_mpz(self )
    other = mpz.__ensure_is_mpz(other)
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

--- less operator `<`
---
---@param self  mpz|integer 1st operand
---@param other mpz|integer 2nd operand
---
---@nodiscard
---@return boolean is_less_or_equal whether the 1st operand is strictly less than the 2nd operand
function mpz.less(self, other)
    return mpz.cmp(self, other) == -1
end

--- less equal operator `<=`
--- 
---@param self  mpz|integer 1st operand
---@param other mpz|integer 2nd operand
---
---@nodiscard
---@return boolean is_less_or_equal whether the 1st operand is less than or equals the 2nd operand
function mpz.less_equal(self, other)
    return mpz.cmp(self, other) ~= 1
end

--- equal operator `==`
---
---@param self  mpz|integer 1st operand
---@param other mpz|integer 2nd operand
---
---@nodiscard
---@return boolean are_equal whether both operands are equal
function mpz.equal(self, other)
    return mpz.cmp(self, other) == 0
end

--- greater equal operator `>=`
--- 
---@param self  mpz|integer 1st operand
---@param other mpz|integer 2nd operand
---
---@nodiscard
---@return boolean is_greater_or_equal whether the 1st operand is greater than or equals the 2nd operand
function mpz.greater_equal(self, other)
    return mpz.cmp(self, other) ~= -1
end

--- greater operator `>`
---
---@param self  mpz|integer 1st operand
---@param other mpz|integer 2nd operand
---
---@nodiscard
---@return boolean is_greater whether the 1st operand is strictly greater than the 2nd operand
function mpz.greater(self, other)
    return mpz.cmp(self, other) == 1
end

--- creates a deep copy
---
---@return mpz copy deep copy
---
--- Preconditons:
--- - `self:__is_valid()`
--- 
--- Postconditions:
--- - `copy:__is_valid()`
--- - `copy == self`
function __mpz:copy()
    assert( self:__is_valid() , "self")-- DEBUG
    local copy = setmetatable({ s = self.s }, __mpz_meta)
    copy.n = mpn.copy(copy, 0, -- destination
                      self, 0, self.n) -- source
    assert( copy:__is_valid() )-- DEBUG
    assert( mpz.equal(self, copy) , "copy")-- DEBUG
    return copy
end

--- computes the absolute value
---
--- @param self mpz|integer
---
---@nodiscard
---@return mpz abs_copy the absolute value of `self`
---
--- Postconditions:
--- - `abs_copy:__is_valid()`
function mpz.abs(self)
    self = mpz.__ensure_is_mpz(self)
    local copy = setmetatable({ s = false }, __mpz_meta)
    copy.n = mpn.copy(copy, 0, -- destination
                      self, 0, self.n) -- source
    assert( copy:__is_valid() , "copy")-- DEBUG
    return copy
end

--- unary negation operator
--- 
---@param self mpz|integer
---
---@nodiscard
---@return mpz neg_copy the negative of `self`
--- 
--- Postconditions:
--- - `neg_copy:__is_valid()`
function mpz.neg(self)
    self = mpz.__ensure_is_mpz(self)
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
__mpz_meta.__unm = mpz.neg

---@private
---
--- shift strictly to the left
--- This may add limbs at the most significant end.
---
---@param self mpz operand to shift left
---@param res table table to store the result in (must already be declared as `mpz`)
---@param s integer count of bit positions to shift left by (must be positive)
---
--- Preconditons:
--- - `s > 0`
---
--- Postconditions:
--- - `res:__is_valid()`
function mpz.__lshift(self, res, s)
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
    -- return res
end

---@private
---
--- shift strictly to the right
--- 
--- This may discards some limbs at the least significant end
---
---@param self mpz operand to shift right
---@param res table table to store the result in (must already be declared as `mpz`)
---@param right_shift_amount integer count of bit positions to shift right by (must be positive)
---
--- Preconditons:
--- - `s > 0`
---
--- Postconditions:
--- - `res:__is_valid()`
function mpz.__rshift(self, res, right_shift_amount)
    assert( right_shift_amount > 0 )-- DEBUG
    -- local n = mpn.rshift_many_bounded(
    --         res, 0, -- destination for the integer part of the shifted copy
    --         {}, 0, -- destination for the fractional part of the shifted copy
    --         self, 0, self.n, -- source
    --         s) -- right shift amount
    local n = mpn.rshift_many_discard(
            res, 0, -- destination for the integer part of the shifted copy
            self, 0, self.n, -- source
            right_shift_amount) -- right shift amount
    local nm1 = n -1
    if rawequal(res[nm1], 0) then
        res[nm1] = nil 
        res.n = nm1
    else
        res.n = n
    end
    -- return res
end

--- left shifting operator `<<`
--- 
--- Actually shifts to the right if the shift amount is negative.
---
---@param self mpz operand to shift left
---@param left_shift_amount integer count of bit positions to shift left by
---
---@nodiscard
---@return mpz res
---
--- Postconditions:
--- - `res:__is_valid()`
function mpz.shl(self, left_shift_amount)
    assert( math.type(left_shift_amount) == "integer", "left shift amount is not an integer.")
    assert( self:__is_valid() , "self")-- DEBUG
    if (self.n < 1) or (left_shift_amount == 0) then
        return mpz.copy(self)
    end
    local res = setmetatable({}, __mpz_meta)
    if left_shift_amount > 0 then
        mpz.__lshift(self, res, left_shift_amount)
        res.s = self.s
    else
        mpz.__rshift(self, res, -left_shift_amount)
        if res.n < 1 then
            res.s = false
        else
            res.s = self.s
        end
    end
    assert( res:__is_valid() , "res")-- DEBUG
    return res
end
__mpz_meta.__shl = mpz.shl

--- right shifting operator `>>`
--- 
--- Actually shifts to the left if the shift amount is negative.
---
---@param self mpz operand to shift right
---@param s integer count of bit positions to shift right by
---
---@nodiscard
---@return mpz res
---
--- Postconditions:
--- - `res:__is_valid()`
function mpz.shr(self, s)
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
__mpz_meta.__shr = mpz.shr

---@private
---
--- implementation of addition
--- 
--- The sign of the returned `sum` equals the sign of the 1st summand `self`.
---
---@param self  mpz 1st summand
---@param other mpz 2nd summand
---
---@nodiscard
---@return mpz sum sum
---
--- Preconditions:
--- - `self:__is_valid_excl_sign()`
--- - `other:__is_valid_excl_sign()`
--- 
--- Postconditions:
--- - `sum:__is_valid_excl_sign()`
function mpz:__add_impl(other)
    local res = setmetatable({
        s = self.s
    }, __mpz_meta)
    if self.n < other.n then
        self, other = other, self
    end
    res.n = mpn.add_unbounded(res, 0, -- destination
                              self, 0, self.n, -- augend
                              other, 0, other.n, -- addend
                              0) -- right incoming carry
    assert( res:__is_valid() )-- DEBUG
    return res
end

---@private
---
--- implementation of subtraction
--- 
--- also sets the sign of the returend `diff`
---
---@param self  mpz subtrahend / 1st operand
---@param other mpz minuend    / 2nd operand
---
---@nodiscard
---@return mpz diff directed difference
---
--- Preconditions:
--- - `self:__is_valid_excl_sign()`
--- - `other:__is_valid_excl_sign()
--- 
--- Postconditions:
--- - `diff:__is_valid()`
function mpz:__sub_impl(other)
    local res = setmetatable({}, __mpz_meta)
    local n
    n, res.s = mpn.diff(res, 0, -- destination
                        self, 0, self.n, -- 1st source
                        other, 0, other.n)-- 2nd source
    
    -- TODO avoid that an Integer must be minimal
    -- minimize result
    n = n -1 -- calc last index
    while (n >= 0) and (res[n] <= 0) do
        res[n] = nil
        n = n -1
    end
    res.n = n +1
    
    assert( res:__is_valid() )-- DEBUG
    return res
end

--- addition operator `+`
---
---@param self  mpz|integer 1st summand
---@param other mpz|integer 2nd summand
---
---@nodiscard
---@return mpz sum sum
--- 
--- Postconditions:
--- - `sum:__is_valid()`
function mpz.add(self, other)
    self  = mpz.__ensure_is_mpz(self )
    other = mpz.__ensure_is_mpz(other)
    
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

--- subtraction operator `-`
---
---@param self  mpz|integer minuend    / 1st operand
---@param other mpz|integer subtrahend / 2nd operand
---
---@nodiscard
---@return mpz diff directed difference
--- 
--- Postconditions:
--- - `diff:__is_valid()`
function mpz.sub(self, other)
    self  = mpz.__ensure_is_mpz(self )
    other = mpz.__ensure_is_mpz(other)
    
    -- In the comments s and o are the absolute values of self and other.
    
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

--- multiplication operator `*`
---
---@param self  mpz|integer 1st factor
---@param other mpz|integer 2nd factor
---
---@nodiscard
---@return mpz prod product
---
--- Postconditions:
--- - `prod:__is_valid()`
function mpz.mul(self, other)
    self  = mpz.__ensure_is_mpz(self )
    other = mpz.__ensure_is_mpz(other)
    
    if (self.n < 1) or (other.n < 1) then
        return mpz.ZERO()
    end
    
    local prod = setmetatable({
        s = self.s ~= other.s ;
        -- prod.s == false / non-negative if
        --    1. self and other are negative     ( -a * -b == +(a * b) with a >= 1 and b >= 1 )
        -- or 2. self and other are non-negative ( +a * +b == +(a * b) with a >= 0 and b >= 0 )
        -- prod.s == true / negative if
        --    1. self is negative    , other is non-negative ( -a * +b == -(a * b) with a >= 1 and b >= 0 )
        -- or 2. self is non-negative, other is negative     ( +a * -b == -(a * b) with a >= 0 and b >= 1 )
    }, __mpz_meta)
    
    prod.n = mpn.mul(prod , 0, 
                     self , 0, self.n ,
                     other, 0, other.n)
    
    prod.n = mpn.minimize_at_left(prod, 0, prod.n)
    
    assert(prod:__is_valid())-- DEBUG
    return prod
end
__mpz_meta.__mul = mpz.mul

---@deprecated
--- divides the absolute values |self| / |other|
---
--- If the quotient is zero, then it also sets the sign.
--- 
--- In contrast to the Lua specification it rounds to zero (and not towards minus infinity)
---
---@param self  mpz dividend
---@param other mpz divisor
---
---@nodiscard
---@return mpz quot quotient
---
--- Preconditions:
--- - `self:__is_valid()`
--- - `other:__is_valid()`
---
--- Postconditions:
--- - if `self.n < 1`, then `res:__is_valid_()`,
---   else                 `res:__is_valid_excl_sign()`
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

--- floor division operator `//`
---
--- rounds the quotient **towards zero** !
---
---@param self  mpz|integer dividend / 1st operand
---@param other mpz|integer divisor  / 2nd operand
---
---@nodiscard
---@return mpz quot quotient rounded **towards zero**
---
--- Postconditions:
--- - `quot:__is_valid()`
function mpz.div(self, other)
    self = mpz.__ensure_is_mpz(self)
    other = mpz.__ensure_is_mpz(other)
    
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

--- integer square root
---
--- computes the greatest integer whose sqaure is less than or equals `self`
---
--- TODO
---
---@param self mpz
---
---@nodiscard
---@return mpz sqrt integer square root
---
--- Preconditions:
--- - `self:__is_valid()`
--- - `other:__is_valid()`
--- 
--- Postconditions:
--- - `res:__is_valid()`
--- - `res^2 <= self`
function mpz.sqrt(self)
    self = mpz.__ensure_is_mpz(self)
    
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

--- format as a string of decimal digits (0-9)
--- 
--- The minus character '-' is prefixed, if `self` is negative.
--- 
--- If `self` is zero, then the string `"0"` is returned.
---
---@param self mpz
---
---@nodiscard
---@return string dec_str
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

---@deprecated
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

--- format as a string of hexadecimal digits with letters in uppercase (0-F)
--- 
--- The minus character '-' is prefixed, if `self` is negative.
--- 
---@param self mpz
---
---@nodiscard
---@return string hex_str
function __mpz:hex()
    return mpz.__str_in_pow_of_2_radix(self, 4, 0xF, DIGITS_UPPERCASE)
end

--- format as a string of hexadecimal digits with letters in lowercase (0-f)
--- 
--- The minus character '-' is prefixed, if `self` is negative.
--- 
--- If `self` is zero, then the string `"0"` is returned.
---
---@param self mpz
---
---@nodiscard
---@return string hex_lowercase_str
function __mpz:hex_lowercase()
    return mpz.__str_in_pow_of_2_radix(self, 4, 0xF, DIGITS_LOWERCASE)
end

--- format as a string of octal digits (0-7)
--- 
--- The minus character '-' is prefixed, if `self` is negative.
--- 
--- If `self` is zero, then the string `"0"` is returned.
---
---@param self mpz
---
---@nodiscard
---@return string oct_str
function __mpz:oct()
    return mpz.__str_in_pow_of_2_radix(self, 3, 7, DIGITS_UPPERCASE)
end

return mpz
