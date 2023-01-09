# TODO list

## High Priority

only a few items

- [x] ensure, that running and debugging tests in VS Code works
- [x] continous integration (automated testing)
- [ ] multiplication
- [ ] division
- [ ] square root with Karabusta? Square Root Algorithm
- [ ] square
- [ ] radix conversion in dec, oct, hex
    - [ ] create `mpz` from string
    - [ ] format `mpz` as string
- [ ] write luarocks spec
- [ ] badge with the licence

## Medium Priority

most items

- [ ] `mpn.add_word_bounded()` and `mpn.add_word_unbounded()`, which adds a positive Lua integer `< RADIX`
- [ ] `mpn.sub_word()`, which subtracts a positive Lua integer `< RADIX`
- [ ] combined assignments (`+=` `<<=` `*=` ...)
- [ ] arbitrary radix conversion from an arbitrary set/sequence of digits (e.g. for base64)
    - [ ] complie a string of digits to a sequence of digits (similar to compiling a regex pattern)
    - [ ] create `mpz` from string
    - [ ] format `mpz` as string
- [ ] build a fast release version with lmacro
- [ ] build an asserting debug version with lmacro (esp. for testing)
- [ ] more workflows:
    - preferably together with the automated test workflow
    - This require multiple some kind of output variables.
    - [ ] workflow for build status
    - [ ] workflow for code coverage
    - [ ] badge with the build status
    - [ ] badge for code coverage
- [ ] upload to luarocks

## Low Priority

some items

- [ ] implement square root with Newton's Method (see imath C library)
- [ ] profile implementations with Karabusta`Sqaure Root and Newton's Method
- [ ] rename source files from `lomp-*.lua` to `lomp/*.lua`<br>
      `require("lomp-*")` --> `require("lomp.*")`
- [ ] adapt automated test workflow
    - [ ] should work on push to any branch
    - [ ] rewrite writing to and loading env vars from cache as a bash script
        - [ ] `git update-index --chmod=+x <script name>` or the like
- [ ] increment/decrement (`++` `--`)
    - [ ] pre/post increment/decrement
- [ ] bitwise operators (`&` `|` `~` `XOR` `<==>` `==>`)
- [ ] more workflows:
    - preferably together with the automated test workflow
    - This require multiple some kind of output variables.
    - [ ] workflow for static analysis/checking
    - [ ] badge with static analysis/checking result
- [ ] better specifiy/document exceptions

## Ideas

- [ ] badge with the version number
- [ ] floating point module `mpf`
