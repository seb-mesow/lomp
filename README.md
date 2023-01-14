# lomp
 *Lua-only library for arbitrary-precision arithmetic*

![status of automated tests](https://github.com/seb-mesow/lomp/actions/workflows/automated_tests.yml/badge.svg)

**Currently this repository is in alpha status!**

This repository provides the module `mpz` – written only in Lua - for computing with integers "larger than normal". It was created to be used for simple computer graphics, but also can be used for other tasks. It was created for applications, which do not allow or disadvice linking to binary modules[^1].

- [Short Reference of the `mpz` module](doc/mpz_short_ref.md)

The version 1.0 depends on Lua version 5.3 .
It should also work for later Lua versions.

Because the module is written in Lua and only use simple algorithms it is neither very fast nor efficient. Thus it is *not recommeded* to use this module for:
- cryptography 
- number theory
- astronomy
- fast computer graphics
- fast computer vision

[^1]: especially for LuaTeX with the `--shell-escape` option.
