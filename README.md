# The Elm Compiler + JS Modules
[![Build Status](https://travis-ci.com/m-mullins/compiler.svg?branch=native-modules-0.19.1)](https://travis-ci.com/m-mullins/compiler)
* This feature branch adds JS modules for any elm _applications_ or package

## Install

* Use the npm package `elm-mods`
* Or grab the binaries from: https://github.com/m-mullins/compiler/releases

## Example

- `elm init`
- Create `src/Main.elm`
```
module Main exposing(..)

import Html exposing (..)
import Elm.Kernel.JS

log : String -> String
log = Elm.Kernel.JS.log

main = text <| log <| "HelloWorld"
```
- Create `src/Elm/Kernel/JS.js`
- _note:_ the first comment is required (it can be empty)
```
/*

*/

function _JS_log(s) {
    console.log(s);
    return s;
}
```
- Compile `elm make src/Main.elm`
- Open `index.html`
    - "HelloWorld" should be printed to the console and on the page
- More js module examples are here [elm/core](https://github.com/elm/core/tree/1.0.2/src/Elm/Kernel) library.
