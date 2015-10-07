var RSVP, ServiceHelpers, _, chalk, displayServicesAndEnvs, help, listServices;

_ = require('lodash');

chalk = require('chalk');

RSVP = require('rsvp');

help = require('./help');

ServiceHelpers = require('../lib/service_helpers');

displayServicesAndEnvs = function(services) {
  var alphabetizedKeys, i, key, len, results;
  alphabetizedKeys = _.keys(services);
  alphabetizedKeys.sort();
  results = [];
  for (i = 0, len = alphabetizedKeys.length; i < len; i++) {
    key = alphabetizedKeys[i];
    process.stdout.write(chalk.blue(key));
    if (services[key].length > 0) {
      process.stdout.write(" (" + (services[key].join(', ')) + ")");
    }
    results.push(process.stdout.write('\n'));
  }
  return results;
};

listServices = function(services, addons) {
  process.stdout.write('Available Addons:\n');
  displayServicesAndEnvs(addons);
  process.stdout.write('Available Services:\n');
  displayServicesAndEnvs(services);
  return RSVP.resolve();
};

module.exports = function(args, commandOptions, done) {
  var addons, services;
  services = ServiceHelpers.listServicesWithEnvs(commandOptions.config);
  addons = ServiceHelpers.listAddons(commandOptions.config);
  return listServices(services, addons).then(function() {
    return typeof done === "function" ? done() : void 0;
  })["catch"](function(e) {
    console.error((e != null ? e.stack : void 0) || 'Aborting. ');
    return process.exit(-1);
  });
};
