# lomp
 *Lua-only library for arbitrary-precision arithmetic*

![status of automated tests](https://github.com/seb-mesow/lomp/actions/workflows/automated_tests.yml/badge.svg)

**Currently this repository is in alpha status!**

This repository provides the module `mpz` – written only in Lua - for computing with integers "larger than normal". It was created to be used for simple computer graphics, but also can be used for other tasks. It was created for applications, which forbid or disadvise linking to binary modules[^1].

- [Short Reference of the `mpz` module](doc/mpz_short_ref.md)

The version 1.0 depends on Lua version 5.3 .
But it should also work with later Lua versions.

Because the module is written in Lua and only uses the most efficient *basecase* algorithms it is neither very fast nor very efficient.
Thus this module is **recommended** for:
- simple computer graphics, geometry
- simple computer vision
- education
- prototypes, proofs of concepts
- any runtime, which forbids or disadvises binary Lua modules

Thus this module is **not recommended** for:
- fast computer graphics
- fast computer vision
- cryptography
- number theory
- astronomy

[^1]: especially for LuaTeX with the disadvised `--shell-escape` option.
