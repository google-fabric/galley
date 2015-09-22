var RSVP, ServiceHelpers, _, chalk, help, listServices;

_ = require('lodash');

chalk = require('chalk');

RSVP = require('rsvp');

help = require('./help');

ServiceHelpers = require('../lib/service_helpers');

listServices = function(services) {
  var alphabetizedKeys, i, key, len;
  alphabetizedKeys = _.keys(services);
  alphabetizedKeys.sort();
  for (i = 0, len = alphabetizedKeys.length; i < len; i++) {
    key = alphabetizedKeys[i];
    process.stdout.write(chalk.blue(key));
    if (services[key].length > 0) {
      process.stdout.write(" (" + (services[key].join(', ')) + ")");
    }
    process.stdout.write('\n');
  }
  return RSVP.resolve();
};

module.exports = function(args, commandOptions, done) {
  var services;
  services = ServiceHelpers.listServicesWithEnvs(commandOptions.config);
  return listServices(services).then(function() {
    return typeof done === "function" ? done() : void 0;
  })["catch"](function(e) {
    console.error((e != null ? e.stack : void 0) || 'Aborting. ');
    return process.exit(-1);
  });
};
