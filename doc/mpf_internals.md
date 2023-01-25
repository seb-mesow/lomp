# Floating-Point Numbers

**This is only a first sketch!**

The addition algorithm loops in low-high order over the augend and addend.

The subtraction algorithm loops in low-high order over the subtrahend and minuend.

The multiplication algorithm loops in low-high order over the multiplicand and the multiplier.

The division algorithm loops in high-low order over the dividend to retrieve the quotient limbs in high-low order.
If this "quotient loop" is terminated before the least significant limb of the dividend,
then the quotient has a "lower precision".
If the "quotient loop" loops further beyond the least significant limb of the dividend,
then "fractional limbs" of the quotient are calculated. Thus the quotient has a "higher precision".
The division algorithm loops in low-high order over the divisor in the subtraction step.
The representation of floating-point numbers should support fast multiplication and division,
while the multiplication and division algorithms must be shared with the integers resp. natural integers

The representation of a floating-point number should be unique.

The precision of the result must be specified for every concrete elementary floating-point operation.
Although a default precision is and can be defined. 

Floating-Point Numbers are represented by
- size of mantissa:
    - equals<br>
```
       precision in bits
ceil( ------------------- )
            WIDTH
```
- mantissa:
    - a 
- exponent:
- sign:
    - true for negative numbers
    - false for non-negative numbers, thus including zero
