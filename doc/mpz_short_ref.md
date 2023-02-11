# Short Reference of the `mpz` class

This class provides big **integers**.

The API follows the following guidelines:
- If it is known, that at least one operand is a `mpz`, then the operators (metamethods) can be used.<br>
  exception: For the comparison operators *both* operands must be `mpz`'s.
- If it is possible, that *both/all* operands can be Lua integers, then the functions from the `mpz` table must be used.
- (As of January 2023 operator-like member methods of each `mpz` are reserved for compound assignments like `+=`, `<<=`.)

Because as of January 2023 no method/functions change a `mpz` in-place,
all `mpz`'s can be considered as immutable.

(Do not forget to prefix each declaration or first assignment of a variable with `local`,
if you do not need a variable that can be accessed from everywhere.)

### loading the module
```lua
local mpz = require("lomp-mpz")
```

### construct
```lua
my_mpz = mpz.new(lua_int)
my_mpz = mpz.new(other_mpz) -- copy constructor, equals mpz.copy(mpz_or_lua_int)
```

### convert to Lua integer
```lua
my_lua_int = my_mpz:to_lua_int()
my_lua_int = mpz.to_lua_int(mpz_or_lua_int)
```
- only returns a Lua integer if `my_mpz` is `<= math.maxinteger` and `>= math.mininteger`<br>
  else an exception is raised and returns `nil`.

### compare two integers
#### operators
Only works when **both** operands are `mpz`'s !
```lua
my_mpz_a <  my_mpz_b
my_mpz_a <= my_mpz_b
my_mpz_a == my_mpz_b
my_mpz_a >= my_mpz_b
my_mpz_a >  my_mpz_b
```
#### operator-like
also works if one or both operands are Lua integers
```lua
mpz.less         (mpz_or_lua_int_a, mpz_or_lua_int_b)
mpz.less_equal   (mpz_or_lua_int_a, mpz_or_lua_int_b)
mpz.equal        (mpz_or_lua_int_a, mpz_or_lua_int_b)
mpz.greater_equal(mpz_or_lua_int_a, mpz_or_lua_int_b)
mpz.greater      (mpz_or_lua_int_a, mpz_or_lua_int_b)
```
#### for sorting or other
also works if one or both operands are Lua integers
```lua
cmp_res = mpz.cmp(mpz_or_lua_int_a, mpz_or_lua_int_b)
```
- returns a negative Lua integer if the 1st operand is less    than the 2nd operand
- returns the Lua integer zero   if the 1st operand equals          the 2nd operand
- returns a positive Lua integer if the 1st operand is greater than the 2nd operand

### unary operations
#### copy
```lua
copy_mpz = my_mpz:copy()
copy_mpz = mpz.copy(mpz_or_lua_int) -- equals mpz.new(mpz_or_lua_int)
```
- This creates a deep copy.

#### absolute value
```lua
abs_of_my_mpz = mpz.abs(mpz_or_lua_int)
```

#### negate
```lua
neg_of_my_mpz = - my_mpz
neg_of_my_mpz = mpz.neg(mpz_or_lua_int)
```

### common operations
#### add two integers
```lua
sum_mpz = mpz_or_lua_int_a + mpz_or_lua_int_b -- At least one operand must be a mpz!
sum_mpz = mpz.add(mpz_or_lua_int_a, mpz_or_lua_int_b)
```

#### subtract one integer from another
```lua
diff_mpz = my_mpz_a - my_mpz_b -- At least one operand must be a mpz!
diff_mpz = mpz.sub(mpz_or_lua_int_a, mpz_or_lua_int_b)
```
- This computes the "directed difference" which can be negative.

#### multiply two integers
```lua 
prod_mpz = mpz_or_lua_int_a * mpz_or_lua_int_b -- At least one operand must be a mpz!
prod_mpz = mpz.mul(mpz_or_lua_int_a, mpz_or_lua_int_b)
```

#### floor division
```lua
quot_mpz = mpz_or_lua_int_a // mpz_or_lua_int_b -- At least one operand must be a mpz!
quot_mpz = mpz.div(mpz_or_lua_int_a, mpz_or_lua_int_b)
```
- The divisor (second operand) must not be zero.<br>
  Else an exception is raised and `nil` is returned.
- **rounds towards zero** (thus truncates resp. floors the absolute value)<br>
  This is in contrast to the Lua specification, that floor division rounds towards minus infinity (strictly floors).
- returns no remainder

#### square
```lua
sqr_mpz = my_mpz^2 -- Note: The 2 as the 2nd operand must be a Lua integer!
sqr_mpz = mpz.sqr(mpz_or_lua_int)
```

#### integer square root
computes the greatest integer whose square is less than or equals the operand*
```lua
sqrt_mpz = mpz.sqrt(mpz_or_lua_int)
```
\* If the operand is negative,
   then returns the negative of the integer square root of the absolute value of the operand

#### power
The 2nd operand must be a Lua integer!
```lua
pow_mpz = my_mpz^lua_int
pow_mpz = mpz.pow(mpz_or_lua_int, lua_int)
```

### bitwise operations
The 2nd operand must be a Lua integer!
#### shift left
```lua
left_shifted_mpz = my_mpz << lua_int
left_shifted_mpz = mpz.shl(mpz_or_lua_int, lua_int)
```
- preserves the sign
  Thus performs an *arithmetic* left shift.
- Thus effectively multiplies by a power of two.

#### shift right
The 2nd operand must be a Lua integer!
```lua
right_shifted_mpz = my_mpz >> lua_int
right_shifted_mpz = mpz.shr(mpz_or_lua_int, lua_int)
```
- preserves the sign (unless all 1 bits are shifted out)
  Thus performs an *arithmetic* right shift.
- Thus effectively divides by a power of two and rounds towards zero.

### radix conversion
This means creating a string of digits in a certain radix (positional notation).

- The string is prefixed with a minus character (`-`) if the `mpz` is negative.
- The string is `0` if the `mpz` is zero.
- The digits are not grouped.
- No padding digits are prefixed.

#### octal
```lua
oct_str = my_mpz:oct()
oct_str = mpz.oct(mpz_or_lua_int)
```
#### decimal
```lua
dec_str = my_mpz:dec()
dec_str = mpz.dec(mpz_or_lua_int)
```
#### hexadecimal with uppercase letters
```lua
hex_str = my_mpz:hex()
hex_str = mpz.hex(mpz_or_lua_int)
```
#### hexadecimal with lowercase letters
```lua
hex_lc_str = my_mpz:hex_lowercase()
hex_lc_str = mpz.hex_lowercase(mpz_or_lua_int)
```

### create a formatted string for debugging
```lua
debug_str_of_mpz = my_mpz:debug_str()
debug_str_of_mpz = tostring(my_mpz)
```
- returns a string which denotes the *individual limbs* in hexadecimal digits
