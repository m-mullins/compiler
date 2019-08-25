# The Elm Compiler + JS Modules
[![Build Status](https://travis-ci.com/m-mullins/compiler.svg?branch=native-modules-0.19.1)](https://travis-ci.com/m-mullins/compiler)
* This feature branch adds JS modules for any elm _applications_ or package

## Install

* Use the npm package `elm-mods`
* Or grab the binaries from: https://github.com/m-mullins/compiler/releases

## Example

1. `elm init`
1. Create src/Main.elm
```
module Main exposing(..)

import Html exposing (..)
import Elm.Kernel.JS

log : String -> String
log = Elm.Kernel.JS.log

main = text <| log <| "HelloWorld"
```
1. Create src/Elm/Kernel/JS.js _note:_ the first comment is required (it can be empty)
```
/*

*/

function _JS_log(s) {
    console.log(s);
    return s;
}
```
1. This show now compile `elm make src/Main.elm`
1. Open the `index.html` and "HelloWorld" should be printed to the console
1 The best place to see more js module examples is the [elm/core](https://github.com/elm/core/tree/1.0.2/src/Elm/Kernel) library.
