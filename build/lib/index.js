var _, chalk, commands, fs, homeDir, loadGlobalOptionsSync, minimist, path, printHelp, run, runCommand;

path = require('path');

fs = require('fs');

_ = require('lodash');

chalk = require('chalk');

homeDir = require('home-dir');

minimist = require('minimist');

commands = {
  pull: require('./commands/pull'),
  'stop-env': require('./commands/stop_env'),
  cleanup: require('./commands/cleanup'),
  run: require('./commands/run'),
  list: require('./commands/list'),
  help: require('./commands/help'),
  version: require('./commands/version'),
  config: require('./commands/config')
};

loadGlobalOptionsSync = function() {
  var globalConfigPath;
  globalConfigPath = path.resolve(homeDir(), '.galleycfg');
  if (fs.existsSync(globalConfigPath)) {
    return JSON.parse(fs.readFileSync(globalConfigPath, {
      encoding: 'utf-8'
    }));
  } else {
    return {};
  }
};

printHelp = function(prefix) {
  return commands.help([], {
    prefix: prefix
  });
};

runCommand = function(prefix, args, commands, opts) {
  var argv, command, commandOpts, err, error;
  argv = minimist(args, {
    boolean: ['help']
  });
  if (argv['help']) {
    return printHelp(argv._);
  } else if (!args.length) {
    printHelp([]);
    return process.exit(1);
  } else if ((command = commands[args[0]]) != null) {
    try {
      commandOpts = _.merge({}, opts, {
        prefix: [args[0]]
      });
      return command(args.slice(1), commandOpts, function(statusCode) {
        if (statusCode == null) {
          statusCode = 0;
        }
        return process.exit(statusCode);
      });
    } catch (error) {
      err = error;
      if (typeof err === 'string') {
        process.stdout.write(chalk.red(err));
      } else {
        process.stdout.write(err != null ? err.stack : void 0);
      }
      process.stdout.write(chalk.red('\nAborting\n'));
      return process.exit(-1);
    }
  } else {
    console.log("Error: Command not found: " + args[0]);
    printHelp([]);
    return process.exit(1);
  }
};

run = function(galleyfilePath, argv) {
  var args, opts, sigHandler;
  sigHandler = function() {
    return process.exit(0);
  };
  process.once('SIGTERM', sigHandler);
  process.once('SIGINT', sigHandler);
  opts = {
    config: require(galleyfilePath),
    globalOptions: loadGlobalOptionsSync()
  };
  args = process.argv.slice(2);
  return runCommand([], args, commands, opts);
};

module.exports = run;
