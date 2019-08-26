module Main exposing(..)

import Html exposing (..)
import Elm.Kernel.JS

log : String -> String
log = Elm.Kernel.JS.log

main = text <| log <| "HelloWorld"
