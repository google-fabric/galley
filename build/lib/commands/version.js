module.exports = function(options, done) {
  var cliPackage;
  cliPackage = require('../../../package');
  console.log("galley version " + cliPackage.version);
  return typeof done === "function" ? done() : void 0;
};
