[![Build Status](https://travis-ci.com/m-mullins/compiler.svg?branch=native-modules-0.19.1)](https://travis-ci.com/m-mullins/compiler)
===============

# Elm compiler + JS modules 
This build adds javascript modules to the elm compiler

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

# Original elm docs: 

Install the [Elm Platform + Mod](https://github.com/elm-lang/elm-platform) via [`npm`](https://www.npmjs.com).

## Installing

Run this to get the binaries:

```
$ npm install -g elm-mods
```

## Installing behind a proxy server

If you are behind a proxy server, set the environment variable "HTTPS_PROXY".

```
$ export HTTPS_PROXY=$YourProxyServer$
$ npm install -g elm-mods
```

Or on Windows:

```
$ set HTTPS_PROXY=$YourProxyServer$
$ npm install -g elm-mods
```

## Troubleshooting

1. [Troubleshooting npm](https://github.com/npm/npm/wiki/Troubleshooting)
2. On Debian/Ubuntu systems, you may have to install the nodejs-legacy package: `apt-get install nodejs-legacy`.
3. If the installer says that it cannot find any usable binaries for your operating system and architecture, check the [Build from Source](https://github.com/elm-lang/elm-platform/blob/master/README.md#build-from-source) documentation.

## Getting Started

Once everything has installed successfully, head over to the [Get Started](http://elm-lang.org/Get-Started.elm) page!
