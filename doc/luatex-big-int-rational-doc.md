# Short Reference of the `mpz` class

Construct a mpz:
```lua
my_Integer = Integer.new(lua_integer)
```

convert to Lua integer
```lua
my_int = Integer.to_lua_integer(my_Integer)
my_int = my_Integer:to_lua_integer()
```
works only if my_Integer is <= math.maxinteger and >= math.mininteger<br>
else raises an error

create a formatted string for debugging
```lua
my_string = tostring(my_Integer)
my_string = Integer.debug_string(my_Integer)
my_string = my_Integer:debug_string()
```
returns a string which contains each limb in hexadecimal

create a deep copy
```lua
copy_Integer = Integer.copy(my_Integer)
copy_Integer = my_Integer:copy()
```

compare
```lua
Integer.less         (integer_a, integer_b)
Integer.less_equal   (integer_a, integer_b)
Integer.equal        (integer_a, integer_b)
Integer.greater_equal(integer_a, integer_b)
Integer.greater      (integer_a, integer_b)
```
- Both operands must be a Lua integer or an Integer.
- currently the operators are not implemented for some reason.

Absolute Value:
    abs_Integer = Integer.abs(my_Integer)
    abs_Integer = my_Integer:abs()

Negation:
    neg_Integer = - my_Integer
    neg_Integer = Integer.neg(my_Integer)
    neg_Integer = my_Integer:neg()

Addition:
    sum_Integer = lua_integer_a + my_Integer_b   
    sum_Integer = my_Integer_a  + lua_integer_b  
    sum_Integer = my_Integer_a  + my_Integer_b
    sum_Integer = Integer.add(lua_integer_a, my_Integer_b)
    sum_Integer = Integer.add(my_Integer_a , lua_integer )
    sum_Integer = Integer.add(my_Integer_a , my_Integer_b)

Subtraction:
    diff_Integer = lua_integer_a - my_Integer_b   
    diff_Integer = my_Integer_a  - lua_integer_b  
    diff_Integer = my_Integer_a  - my_Integer_b
    diff_Integer = Integer.sub(lua_integer_a, my_Integer_b)
    diff_Integer = Integer.sub(my_Integer_a , lua_integer )
    diff_Integer = Integer.sub(my_Integer_a , my_Integer_b)

Multiplication:
    prod_Integer = lua_integer_a * my_Integer_b   
    prod_Integer = my_Integer_a  * lua_integer_b  
    prod_Integer = my_Integer_a  * my_Integer_b
    prod_Integer = Integer.mul(lua_integer_a, my_Integer_b)
    prod_Integer = Integer.mul(my_Integer_a , lua_integer )
    prod_Integer = Integer.mul(my_Integer_a , my_Integer_b)

Floor Division:
    quotient_Integer = lua_integer_a // my_Integer_b   
    quotient_Integer = my_Integer_a  // lua_integer_b  
    quotient_Integer = my_Integer_a  // my_Integer_b
    quotient_Integer = Integer.div(lua_integer_a, my_Integer_b)
    quotient_Integer = Integer.div(my_Integer_a , lua_integer )
    quotient_Integer = Integer.div(my_Integer_a , my_Integer_b)
    - The divisor (second operand) must not be zero.
    - rounds TOWARDS ZERO (thus truncates resp. floors the absolute value)
      This is in contrast to the Lua reference, which specifies,
      that floor division rounds towards minus infinity (strictly floors).
    - returns NO remainder

Square:
    square_Integer = my_Integer^2
    square_Integer = Integer.square(my_Integer)
    square_Integer = my_Integer:square()

Square Root:
    sqrt_Integer = Integer.sqrt(my_Integer)
    sqrt_Integer = my_Integer:sqrt()
    
Radix Conversion:
    octal_str       = my_Integer:oct()
    octal_str       = Integer.oct(my_Integer)
    decimal_str     = my_Integer:dec()
    decimal_str     = Integer.dec(my_Integer)
    hexadecimal_uppercase_str = my_Integer:hex()
    hexadecimal_uppercase_str = Integer.hex(my_Integer)
    hexadecimal_lowercase_str = my_Integer:hex_lowercase()
    hexadecimal_lowercase_str = Integer.hex_lowercase(my_Integer)
    - If the Integer is non-negative, then no sign is prepended.
    - If the Integer is negative, then "-" is prepended.
    - If the Integer is zero, then "0" is returned.
    - No grouping or padding takes place.
