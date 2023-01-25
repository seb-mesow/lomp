# Implementation overview

This repositiory is divided into multiple modules.

It is inspired by the [GMP library](https://gmplib.org/).
Thus it shares its modularization and terminology

The algorithms are implemented in the `mpn` module.
('N' == natural numbers)<br>
The algorithms are implemented over *ranges* of *limbs*.<br>
A *word* is a non-negative Lua integer less than a huge radix (`RADIX`).<br>
A *range array* is a continous array of *words*.<br>
(An array is a Lua table with a continous sequence of integers as keys. The Lua Reference uses the term *sequence*.)<br>
We prefer to name a word which is a part of a range array a *limb*.<br>
A *range* is a triple of a range array, a *start index* and an *end index*.<br>
(The *addressable limbs* of a range array are those limbs at the integer indices from including the start index to excluding the end index.)

If the end index is less than or equals the start index, then the range is considered zero.<br>
(A range is also considered zero, if all it addressable limbs are zero.)

The `mpz` module implements the class of positive and negative integers
('Z' == integers)<br>
An `mpz` holds a *range*, where the start index is 0 and the end index is the count of limbs.
