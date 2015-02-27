_ = require 'lodash'
chalk = require 'chalk'
minimist = require 'minimist'

# Uses stderr
print = console.warn

commonOptionsHelp = ->
  print '  --configDir=""                 Specify a directory to search for the Galleyfile'

rootHelp = ->
  print "#{chalk.bold 'Usage:'} galley COMMAND [arg...]"
  print ''
  print 'A tool to manage dependencies among local Docker containers'
  print ''
  print chalk.bold 'Commands'
  print '  help       Print help'
  print '  pull       Download images for a service and its dependencies'
  print '  run        Execute a command inside of a service’s container'
  print '  stop-env   Stop all containers in an environment'
  print '  version    Show the Galley version information'
  print ''
  print 'Run "galley COMMAND --help" for more information on a command.'

pullHelp = ->
  print "#{chalk.bold 'Usage:'} galley pull [OPTIONS] SERVICE[.ENV]"
  print ''
  print 'Downloads the latest version of SERVICE’s image from the Docker registry, as well'
  print 'as the latest versions of all of SERVICE’s dependencies.'
  print ''
  print 'If ENV is provided, uses it as a key to look up dependencies in the Galleyfile.'
  print ''
  print "#{chalk.bold 'Note:'} Does not affect existing containers, running or not. You must"
  print 'use Docker to remove containers created by "galley run" for those commands to create'
  print 'fresh containers with these updated images.'
  print ''
  print chalk.bold 'Options'
  print '  -a, --add="SERVICE1,SERVICE2"  Includes the specified add-on service(s) as part of'
  print '                                 this SERVICE’s dependencies when downloading updates'
  commonOptionsHelp()

cleanupHelp = ->
  print "#{chalk.bold 'Usage:'} galley cleanup [OPTIONS]"
  print ''
  print 'Removes stopped containers (and their volumes) and cleans up dangling images to save'
  print 'disk space.'
  print ''
  print 'Containers are only stopped if their names match a service from the current Galleyfile'
  print 'and that service is not “stateful.”'
  print ''
  print chalk.bold 'Options'
  print '  --unprotectAnonymous false     If true, then stopped containers that don’t match a'
  print '                                 Galleyfile service are still removed, along with their'
  print "                                 volumes. #{chalk.bold 'Use with caution.'}"
  print '  --unprotectStateful false      If true, then “stateful” containers (such as MySQL) will be'
  print '                                 removed if they’re stopped.'
  commonOptionsHelp()

runHelp = ->
  print "#{chalk.bold 'Usage:'} galley run [OPTIONS] SERVICE[.ENV] [COMMAND [ARG...]]"
  print ''
  print 'Ensures that SERVICE’s dependencies are started, then runs the service. The container'
  print 'is started in the foreground by default, with STDIN piped in to the container. Galley'
  print 'will remove the container on process exit and return the same status code the process did.'
  print ''
  print 'You can detach from the container with CTRL-P CTRL-Q, which will leave it running but'
  print 'exit Galley.'
  print ''
  print 'If no command is provided, Galley starts the container as a service. It is given the'
  print 'name “service.env” and any ports specified in this env are bound to the host.'
  print ''
  print 'If a command is specified, Galley does not bind ports automatically and gives the'
  print 'container a random name, so that it doesn’t conflict with any service versions of'
  print 'the container already running.'
  print ''
  print 'If run from a TTY, starts the container as a TTY as well. Otherwise, binds the'
  print 'container’s STDOUT and STDERR to the process’s STDOUT and STDERR.'
  print ''
  print 'If ENV is provided, uses it as a suffix for container names, and as a key to look up'
  print 'dependencies in the Galleyfile.'
  print ''
  print chalk.bold 'Options'
  print '  -a, --add="SERVICE1,SERVICE2"  Starts the specified add-on service(s) as part'
  print '                                 of this SERVICE’s dependencies'
  commonOptionsHelp()
  print '  -d, --detach=false             Starts the container in the background and does not'
  print '                                 automatically remove it on exit'
  print '  -e, --env=[]                   Set environment variables as “NAME=VALUE”'
  print '  --entrypoint=""                Override the image’s default ENTRYPOINT with another'
  print '                                 command. If specified as blank, will override the image'
  print '                                 to not use an entrypoint (Docker default).'
  print '  --recreate="stale"             Specify which linked containers should be re-created. Can'
  print '                                 be “all”, ”stale”, or ”missing-link”. (“stale” implies '
  print '                                 “missing-link”) The primary service container is always '
  print '                                 recreated. Containers for services marked “stateful” are '
  print '                                 never recreated unless --unprotectStateful is true.'
  print '  --repairSourceOwnership false  After the command exits, ensure that files in the'
  print '                                 service’s source directory inside of the container are'
  print '                                 not owned by root'
  print '  --restart false                Uses Docker’s RetryPolicy to restart the service’s'
  print '                                 process when it exits. Useful for cycling Rails apps'
  print '                                 without shutting down the container (which destroys links).'
  print '  --rsync false                  If true, rsyncs source directory in a volume container.'
  print '  --unprotectStateful false      If true, then “stateful” containers (such as MySQL) may be'
  print '                                 recreated by the --recreate rules.'
  print '  -u, --user=""                  Username or UID for the primary service’s container'
  print '  -v, --volume=""                Map a host directory in to a container'
  print '                                 Format: hostDir[:containerDir]'
  print '                                 If containerDir is not provided, uses the service’s default'
  print '                                 source directory as specified in the Galleyfile.'
  print '  -w, --workdir=""               Execute the command from within this directory'

stopEnvHelp = ->
  print "#{chalk.bold 'Usage:'} galley stop-env ENV"
  print ''
  print 'Stops all running containers that have the “.ENV” suffix.'

HELPS =
  '_': rootHelp
  'cleanup': cleanupHelp
  'pull': pullHelp
  'run': runHelp
  'stop-env': stopEnvHelp

printHelp = (args, helps) ->
  if _.isFunction helps
    helps()
  else
    command = args[0] or '_'
    args = args.slice 1

    if helps[command]?
      printHelp args, helps[command]
    else
      print "Error: Unrecognized argument: #{command}"
      printHelp args, helps['']
      process.exit 1

module.exports = (args, options, done) ->
  argv = minimist args

  if options.prefix[0] is 'help'
    # This is the case for: galley help service pull
    printHelp argv._, HELPS
  else
    # This case is for: galley service pull --help
    printHelp options.prefix, HELPS

  done?()
