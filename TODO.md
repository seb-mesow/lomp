# TODO list

## High Priority

only a few items

- [x] ensure, that running and debugging tests in VS Code works
- [x] continuous integration (automated testing)
- [x] multiplication
- [x] division without remainder
- [x] document behavior of `mpn` algorithms regarding overwriting input ranges
      and to what memory/range the result is written
- [ ] rewrite most `mpn` algorithms to overwrite the memory/range of their inputs
      (favor in-place for combined assignments)
    - [ ] `mpn.rshift_few_bounded()`: read and write leftwards
    - [ ] `mpn.rshift_few_unbounded()`
    - [ ] `mpn.lshift_few_bounded()`: read and write rightwards
    - [ ] `mpn.rshift_few_unbounded()`
- [ ] division with remainder
- [ ] square root with Karatsuba Square Root Algorithm
- [ ] square
- [ ] convenient way to detect overflow (warning) at `mpn.try_to_lua_int` and `__mpz:to_lua_int()`
- [ ] radix conversion in dec, oct, hex
    - [ ] create `mpz` from string
    - [ ] format `mpz` as string
- [ ] write luarocks spec

## Medium Priority

most items

- [ ] `mpn.add_word_bounded()` and `mpn.add_word_unbounded()`, which adds a positive Lua integer `< RADIX`
- [ ] `mpn.sub_word()`, which subtracts a positive Lua integer `< RADIX`
- [ ] `mpn.mul_with_word()`, which multiplies with a positive Lua integer `< RADIX`
- [ ] combined assignments (`+=` `<<=` `*=` ...)
- [ ] *arbitrary* radix conversion from an *arbitrary* set/sequence of digits (e.g. for base64)
    - [ ] compile a string of digits to a sequence of digits (similar to compiling a regex pattern)
    - [ ] create `mpz` from string
    - [ ] format `mpz` as string
- [ ] build a fast release version with lmacro
- [ ] build an asserting debug version with lmacro (esp. for testing)
- [ ] more workflows:
    - preferably together with the automated test workflow
    - This requires multiple some kind of output variables.
    - [ ] workflow for build status
    - [ ] workflow for code coverage
    - [ ] badge with the build status
    - [ ] badge for code coverage
- [ ] upload to luarocks

## Low Priority

some items

- [ ] `mpn.add_mul_bounded()` and `mpn.add_mul_unbounded()`, which adds a product
- [ ] `mpn.sub_mul_bounded()` and `mpn.sub_mul_unbounded()`, which subtracts a product
- [ ] rename source files from `lomp-*.lua` to `lomp/*.lua`<br>
      `require("lomp-*")` --> `require("lomp.*")`
- [ ] adapt automated test workflow
    - [ ] should work on push to any branch
    - [ ] rewrite writing to and loading env vars from cache as a bash script
        - [ ] `git update-index --chmod=+x <script name>` or the like
- [ ] increment/decrement (`++` `--`)
    - [ ] pre/post increment/decrement
- [ ] bitwise operators (`&` `|` `~` `XOR`)
- [ ] `mpn.minimize_at_right()`
- [ ] more workflows:
    - preferably together with the automated test workflow
    - This require multiple some kind of output variables.
    - [ ] workflow for static analysis/checking
    - [ ] badge with static analysis/checking result
- [ ] better specify/document exceptions
- [ ] make `mpz.__ensure_is_mpz()` public
- [ ] `mpz.diff()` for undirected difference/distance
- [ ] `mpz.copy_sign()`

## Ideas

- [ ] badge with the version number
- [ ] badge with the license
- [ ] implement square root with Newton's Method (see imath C library)
- [ ] implement square root with adapted Algorithm D
- [ ] profile different implementations for square root
- [ ] `mpn` algorithm for computing fractional limbs of the inverse square root
- [ ] floating point module `mpf`
