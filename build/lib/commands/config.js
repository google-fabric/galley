var RSVP, _, chalk, fs, help, homeDir, minimist, newConfigHashItem, path, setConfigOption;

path = require('path');

fs = require('fs');

homeDir = require('home-dir');

minimist = require('minimist');

RSVP = require('rsvp');

chalk = require('chalk');

_ = require('lodash');

help = require('./help');

newConfigHashItem = function(option, value) {
  var exists, optionsHash;
  optionsHash = {};
  switch (option) {
    case 'configDir':
      exists = fs.existsSync(path.resolve(value));
      if (!exists) {
        process.stdout.write(chalk.yellow("Warning: "));
        process.stdout.write(value + " does not exist\n");
      }
      optionsHash[option] = value;
      break;
    default:
      optionsHash[option] = JSON.parse(value);
  }
  return optionsHash;
};

setConfigOption = function(option, value) {
  return new RSVP.Promise(function(resolve, reject) {
    var existingGalleycfgHash, exists, galleycfg, galleycfgHash, galleycfgPath;
    galleycfgPath = path.resolve(homeDir(), '.galleycfg');
    existingGalleycfgHash = {};
    exists = fs.existsSync(galleycfgPath);
    if (exists) {
      process.stdout.write('Updating ~/.galleycfg\n');
      galleycfg = fs.readFileSync(galleycfgPath);
      existingGalleycfgHash = JSON.parse(galleycfg.toString());
    } else {
      process.stdout.write('Creating ~/.galleycfg\n');
    }
    galleycfgHash = _.merge(existingGalleycfgHash, newConfigHashItem(option, value));
    return fs.writeFile(galleycfgPath, JSON.stringify(galleycfgHash, false, 2), function(err) {
      if (err) {
        reject(err);
      }
      return resolve();
    });
  });
};

module.exports = function(args, options, done) {
  var argv, configPromise, option, value;
  argv = minimist(args, {
    boolean: ['help']
  });
  if (argv._.length !== 3 || argv.help) {
    return help(args, options, done);
  }
  configPromise = RSVP.resolve();
  if (argv['_'][0] === 'set') {
    option = argv['_'][1];
    value = argv['_'][2];
    configPromise = configPromise.then(function() {
      return setConfigOption(option, value);
    });
  }
  return configPromise.then(function() {
    process.stdout.write(chalk.green('done!\n'));
    return typeof done === "function" ? done() : void 0;
  })["catch"](function(err) {
    process.stdout.write(chalk.red(err));
    process.stdout.write(chalk.red(err.stack));
    process.stdout.write(chalk.red('\nAborting.\n'));
    return process.exit(1);
  });
};
