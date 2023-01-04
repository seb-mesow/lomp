# Short Reference of the `mpz` class

This class provides big **integers**.

Its API is kept to a minimum.

If you handle only `mpz`'s, then (with the exception of comparision) you should only use the defined operators and class functions (`my_mpz:method()`).

If you handle `mpz`'s *and* Lua integers, then you must use the functions of the `mpz` module table<br>
(`my_mpz.function(mpz_or_lua_int_a, mpz_or_lua_int_b)`).

Because currently no method/functions change an `mpz` in place,
all `mpz`'s can be considered as immutable.

Unary functions (e.g. `abs()` always return a deep copy of its operand.

(Do not forget to prefix each declaration or first assignment of a variable with `local`,
if you do not need a variable that can be accessed from everywhere.)

### loading the module
```lua
local mpz = require("lomp-mpz")
```

### construct
```lua
my_mpz = mpz.new(lua_int)
```

### convert to Lua integer
```lua
my_lua_int = my_mpz:to_lua_int()
```
- only returns a Lua integer if `my_mpz` is `<= math.maxinteger` and `>= math.mininteger`<br>
  else an exception is raised and returns `nil`.

### compare two integers
#### operator-like
```lua
mpz.less         (mpz_or_lua_int_a, mpz_or_lua_int_b)
mpz.less_equal   (mpz_or_lua_int_a, mpz_or_lua_int_b)
mpz.equal        (mpz_or_lua_int_a, mpz_or_lua_int_b)
mpz.greater_equal(mpz_or_lua_int_a, mpz_or_lua_int_b)
mpz.greater      (mpz_or_lua_int_a, mpz_or_lua_int_b)
```
Currently the operators (metamethods) are not implemented, to ensure that the functions of the `mpz` module are called.
#### for sorting or other
```lua
cmp_res = mpz.cmp(mpz_or_lua_int_a, mpz_or_lua_int_b)
```
- returns a negative integer if the 1st operand is less than the 2nd operand
- returns the integer zero if the 1st operand equals the 2nd operand
- returns a positive integer if the 1st operand is greater than the 2nd operand

### unary operations
#### copy
```lua
copy_mpz = my_mpz:copy()
```
- This creates a deep copy.

#### absolute value
```lua
abs_of_my_mpz = my_mpz:abs()
```

#### negate
```lua
neg_of_my_mpz = - my_mpz
```

### common operations
#### add two integers
```lua
sum_mpz = my_mpz_a + my_mpz_b   
sum_mpz = mpz.add(mpz_or_lua_int_a, mpz_or_lua_int_b)
```

#### subtract one integer from another
```lua
diff_mpz = my_mpz_a  - my_mpz_b
diff_mpz = mpz.sub(mpz_or_lua_int_a, mpz_or_lua_int_b)
```
- This computes the "directed difference" which can be negative.

#### multiply two integers
```lua 
prod_mpz = my_mpz_a * my_mpz_b
prod_mpz = mpz.mul(mpz_or_lua_int_a, mpz_or_lua_int_b)
```

#### floor division
```lua
quot_mpz = my_mpz_a // my_mpz_b   
quot_mpz = mpz.div(mpz_or_lua_int_a , mpz_or_lua_int_b)
```
- The divisor (second operand) must not be zero.<br>
  Else an exception is raised and `nil` is returned.
- **rounds towards zero** (thus truncates resp. floors the absolute value)<br>
  This is in contrast to the Lua specification, that floor division rounds towards minus infinity (strictly floors).
- returns no remainder

#### square
```lua
sqr_mpz = my_mpz^2
sqr_mpz = my_mpz:sqr()
```

#### square root
```lua
sqrt_mpz = my_mpz:sqrt()
```
- returns the negative of the square root of the absolute value of the `mpz` if the `mpz` is negative

### bitwise operations
#### shift left
```lua
left_shifted_mpz = my_mpz << lua_int
```
- preserves the sign
  Thus performs an *arithmetic* left shift.
- Thus effectively multiplies by a power of two.

#### shift right
```lua
right_shifted_mpz = my_mpz >> lua_int
```
- preserves the sign (unless all 1 bits are shifted out.)
  Thus performs an *arithmetic* right shift.
- Thus effectively divides by a power of two and rounds towards zero.

### radix conversion
This means creating a string of digits in a certain radix (positional notation).

- The string is prefixed with a minus character (`-`) if the `mpz` is negative.
- The strings is `0` if the `mpz` is zero.
- The digits are not grouped.
- No padding digits are prefixed.

#### octal
```lua
oct_str = my_mpz:oct()
```
#### decimal
```lua
dec_str = my_mpz:dec()
```
#### hexadecimal with uppercase letters
```lua
hex_uc_str = my_mpz:hex()
```
#### hexadecimal with lowercase letters
```lua
hex_lc_str = my_mpz:hex_lowercase()
```

### create a formatted string for debugging
```lua
debug_str_of_mpz = my_mpz:debug_str()
debug_str_of_mpz = tostring(my_mpz)
```
- returns a string which denotates each limb in hexadecimal digits
