# The Elm Compiler + JS Modules
[![Build Status](https://travis-ci.com/m-mullins/compiler.svg?branch=native-modules-0.19.1)](https://travis-ci.com/m-mullins/compiler)
* This feature branch reintroduces JS modules for any elm _application_ or package

## Install

* Use the npm package `elm-mods`
* Or grab the binaries from: https://github.com/m-mullins/compiler/releases
* :warn: I pulled the package and binaries because I jumped the gun on the actual 0.19.1 elm release
* To build manually install stack: https://docs.haskellstack.org/en/stable/README/#how-to-install then:
```
git clone ..
stack build

# The binary is then in:
echo $(stack path --local-install-root)/bin/elm[.exe]
```

## Example

- `elm init`
- Create a Javascript module, `src/Elm/Kernel/JS.js`
- _Important notes:_
    - Javascript modules must be in a `Elm/Kernel/` folder
```
// Nothing crazy here, the JS.log function logs the string and returns it
function _JS_log(s) {
    console.log(s);
    return s;
}
```
- Create an Elm module to call our javascript, `src/Main.elm`
```
module Main exposing(..)

import Html exposing (..)
import Elm.Kernel.JS

log : String -> String
log = Elm.Kernel.JS.log

main = text <| log <| "HelloWorld"
```
- Compile `elm make src/Main.elm`
- Open `index.html`
    - "HelloWorld" should be printed to the console and on the page
- More js module examples are here [elm/core](https://github.com/elm/core/tree/1.0.2/src/Elm/Kernel) library.

