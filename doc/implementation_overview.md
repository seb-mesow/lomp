# Implementation overview

This repositiory is divided into multiple modules.

It is inspired by the [GMP library](https://gmplib.org/).
Thus it shares its modularization and terminology

The algorithms are implemented in the `mpn` module.
('n' == natural numbers)
The algorithms are implemented over *ranges* of *limbs*.
A *limb* is an non-negative integer less than a huge radix.
Every limb which fits into one Lua integer.
A *range* is a triple of an continous array (a Lua table with integer indices) of these limbs, a *start index* and an *end index*.

The `mpz` module implements the class of positive and negative integers
('z' == integers)
An `mpz` holds a *range*, where the start index is 0 and the end index is the count of limbs.
