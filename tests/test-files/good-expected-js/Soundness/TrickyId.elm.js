Elm.Main = Elm.Main || {};
Elm.Main.make = function (_elm) {
   "use strict";
   _elm.Main = _elm.Main || {};
   if (_elm.Main.values) return _elm.Main.values;
   var _op = {};
   var myId = function (x) {    var y = x;return y;};
   return _elm.Main.values = {_op: _op,myId: myId};
};