var HELPS, _, chalk, cleanupHelp, commonOptionsHelp, configHelp, listHelp, minimist, print, printHelp, pullHelp, rootHelp, runHelp, stopEnvHelp, versionHelp;

_ = require('lodash');

chalk = require('chalk');

minimist = require('minimist');

print = console.warn;

commonOptionsHelp = function() {
  return print('  --help                         Show this help message');
};

rootHelp = function() {
  print((chalk.bold('Usage:')) + " galley COMMAND [arg...]");
  print('');
  print('A tool to manage dependencies among local Docker containers');
  print('');
  print(chalk.bold('Commands'));
  print('  help       Print help');
  print('  cleanup    Clean up docker images & containers to save disk space');
  print('  config     Set up your galley configuration');
  print('  pull       Download images for a service and its dependencies');
  print('  run        Execute a command inside of a service’s container');
  print('  stop-env   Stop all containers in an environment');
  print('  version    Show the Galley version information');
  print('');
  return print('Run "galley COMMAND --help" for more information on a command.');
};

listHelp = function() {
  print((chalk.bold('Usage:')) + " galley list");
  print('');
  print('Parses your Galleyfile and lists the available services and ');
  print('the environments for which they have defined behavior.');
  print('');
  print('Services that do not have environments listed behave the same way');
  print('under any given environment (e.g. same links, same ports).');
  return print('');
};

pullHelp = function() {
  print((chalk.bold('Usage:')) + " galley pull [OPTIONS] SERVICE[.ENV]");
  print('');
  print('Downloads the latest version of SERVICE’s image from the Docker registry, as well');
  print('as the latest versions of all of SERVICE’s dependencies.');
  print('');
  print('If ENV is provided, uses it as a key to look up dependencies in the Galleyfile.');
  print('');
  print((chalk.bold('Note:')) + " Does not affect existing containers, running or not.");
  print('When you run galley run, non-stateful services will be restarted to pick up new images.');
  print('');
  print("" + (chalk.bold('Options')));
  print('  -a, --add="SERVICE1,SERVICE2"  Includes the specified add-on service(s) as part of');
  print('                                 this SERVICE’s dependencies when downloading updates');
  return commonOptionsHelp();
};

cleanupHelp = function() {
  print((chalk.bold('Usage:')) + " galley cleanup [OPTIONS]");
  print('');
  print('Removes stopped containers (and their volumes) and cleans up dangling images to save');
  print('disk space.');
  print('');
  print('Containers are only stopped if their names match a service from the current Galleyfile');
  print('and that service is not “stateful.”');
  print('');
  print("" + (chalk.bold('Options')));
  print('  --unprotectAnonymous false     If true, then stopped containers that don’t match a');
  print('                                 Galleyfile service are still removed, along with their');
  print("                                 volumes. " + (chalk.bold('Use with caution.')));
  print('  --unprotectStateful false      If true, then “stateful” containers (such as MySQL) will be');
  print('                                 removed if they’re stopped.');
  return commonOptionsHelp();
};

configHelp = function() {
  print((chalk.bold('Usage:')) + " galley config COMMAND SETTING");
  print('');
  print('Sets up your ~/.galleycfg file');
  print('');
  print(chalk.bold('Command'));
  print(' set                             Used to set values for particular config settings ');
  print(chalk.bold('Settings'));
  return print(' rsync [false]                   Default behavior for source mapping with the rsync container');
};

runHelp = function() {
  print((chalk.bold('Usage:')) + " galley run [OPTIONS] SERVICE[.ENV] [COMMAND [ARG...]]");
  print('');
  print('Ensures that SERVICE’s dependencies are started, then runs the service. The container');
  print('is started in the foreground by default, with STDIN piped in to the container. Galley');
  print('will remove the container on process exit and return the same status code the process did.');
  print('');
  print('You can detach from the container with CTRL-P CTRL-Q, which will leave it running but');
  print('exit Galley.');
  print('');
  print('If no command is provided, Galley starts the container as a service. It is given the');
  print('name “service.env” and any ports specified in this env are bound to the host.');
  print('');
  print('If a command is specified, Galley does not bind ports automatically and gives the');
  print('container a random name, so that it doesn’t conflict with any service versions of');
  print('the container already running.');
  print('');
  print('If run from a TTY, starts the container as a TTY as well. Otherwise, binds the');
  print('container’s STDOUT and STDERR to the process’s STDOUT and STDERR.');
  print('');
  print('The provided ENV is used as a suffix for container names, and as a key to look up');
  print('dependencies in the Galleyfile.');
  print('');
  print(chalk.bold('Options'));
  print('  -a, --add="SERVICE1,SERVICE2"  Starts the specified add-on service(s) as part');
  print('                                 of this SERVICE’s dependencies');
  commonOptionsHelp();
  print('  -d, --detach=false             Starts the container in the background and does not');
  print('                                 automatically remove it on exit');
  print('  -e, --env=[]                   Set environment variables as “NAME=VALUE”');
  print('  --entrypoint=""                Override the image’s default ENTRYPOINT with another');
  print('                                 command. If specified as blank, will override the image');
  print('                                 to not use an entrypoint (Docker default).');
  print('  --publish-all, -P=true         Binds the primary service’s ports per the “ports”');
  print('                                 Galleyfile configuration. The default for this is false');
  print('                                 if a command is specified. Use this flag to override in');
  print('                                 that circumstance.');
  print('  --recreate="stale"             Specify which linked containers should be re-created. Can');
  print('                                 be “all”, ”stale”, or ”missing-link”. (“stale” implies ');
  print('                                 “missing-link”) The primary service container is always ');
  print('                                 recreated. Containers for services marked “stateful” are ');
  print('                                 never recreated unless --unprotectStateful is true.');
  print('  --repairSourceOwnership false  After the command exits, ensure that files in the');
  print('                                 service’s source directory inside of the container are');
  print('                                 not owned by root');
  print('  --restart=false                Uses Docker’s restart policy to restart the service’s');
  print('                                 process when it exits. Useful for cycling Rails apps');
  print('                                 without shutting down the container (which destroys links).');
  print('  --rsync=false                  If true, starts up the “rsync” container from the');
  print('                                 Galleyfile and uses it to sync the source directory from');
  print('                                 the host to the container. Note: files are only synched');
  print('                                 from outside the container to inside the container, not');
  print('                                 the reverse.');
  print('  -s, --source=""                Provide a directory to volume mount over the services’s');
  print('                                 “source” directory.');
  print('  --unprotectStateful=false      If true, then “stateful” containers (such as MySQL) may be');
  print('                                 recreated by the --recreate rules.');
  print('  -u, --user=""                  Username or UID for the primary service’s container');
  print('  -v, --volume=""                Map a host directory in to a container');
  print('                                 Format: hostDir[:containerDir]');
  print('  --volumes-from=[]              List of containers whose volumes should be mapped in to');
  print('                                 the primary service');
  print('  -w, --workdir=""               Execute the command from within this directory inside the');
  return print('                                 container');
};

stopEnvHelp = function() {
  print((chalk.bold('Usage:')) + " galley stop-env ENV");
  print('');
  return print('Stops all running containers that have the “.ENV” suffix.');
};

versionHelp = function() {
  print((chalk.bold('Usage:')) + " galley version");
  print('');
  return print('Provides the currently running version of galley');
};

HELPS = {
  '_': rootHelp,
  'cleanup': cleanupHelp,
  'config': configHelp,
  'pull': pullHelp,
  'list': listHelp,
  'run': runHelp,
  'stop-env': stopEnvHelp,
  'version': versionHelp
};

printHelp = function(args, helps) {
  var command;
  if (_.isFunction(helps)) {
    return helps();
  } else {
    command = args[0] || '_';
    args = args.slice(1);
    if (helps[command] != null) {
      return printHelp(args, helps[command]);
    } else {
      print("Error: Unrecognized argument: " + command);
      printHelp(args, helps['']);
      return process.exit(1);
    }
  }
};

module.exports = function(args, options, done) {
  var argv;
  argv = minimist(args);
  if (options.prefix[0] === 'help') {
    printHelp(argv._, HELPS);
  } else {
    printHelp(options.prefix, HELPS);
  }
  return typeof done === "function" ? done() : void 0;
};
