// Generated by ReScript, PLEASE EDIT WITH CARE
'use strict';

var Nodefs = require("node:fs");
var Unzipper = require("unzipper");

var Unzipper$1 = {};

function run(src, dest) {
  return new Promise((function (resolve, param) {
                var readStream = Nodefs.createReadStream(src);
                readStream.once("close", resolve);
                readStream.pipe(Unzipper.Extract({
                          path: dest
                        }));
              }));
}

exports.Unzipper = Unzipper$1;
exports.run = run;
/* node:fs Not a pure module */
