[![Build Status](https://travis-ci.com/Tieske/ncache.lua.svg?branch=master)](https://travis-ci.com/Tieske/ncache.lua)
[![Coverage Status](https://coveralls.io/repos/github/Tieske/ncache.lua/badge.svg?branch=master)](https://coveralls.io/github/Tieske/ncache.lua?branch=master)

Ncache
======

Cache with key normalization (or many-to-1 cache).

The normalized keys will also be cached, so keys will be normalized only once.
Hence the use case is when normalization of the key is a relatively expensive
operation.


Installation
============

Install through LuaRocks (`luarocks install ncache`) or from source, see the
[github repo](https://github.com/Tieske/ncache.lua).

Documentation
=============

The docs are [available online](https://tieske.github.io/ncache.lua/), or can
be generated using [Ldoc](http://stevedonovan.github.io/ldoc/). Just run
`"ldoc ."` from the repo.

In the `examples` folder there are two examples (included in the tests) that
implement an IP/hostname cache and a SemVer based cache.

Tests
=====

Tests are in the `spec` folder and can be executed using the
[busted test framework](http://olivine-labs.github.io/busted/). Just run
`"busted"` from the repo.

Besides that `luacheck` is configured for linting, just run `"luacheck ."` from
the repo. And if LuaCov is installed, the Busted test-run will result in a
coverage report (file `"luacov.report.out"`).

The tests require some additional modules to be installed (only for the
tests, not for the module itself):

- busted (test framework itself)
- luacheck (linter)
- luacov (optional)
- luasocket (for the ipcache example)
- version (for the vcache example)


Copyright and License
=====================

```
Copyright 2019 Thijs Schreijer.

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

History
=======

0.1 15-Aug-2019

- Initial version
