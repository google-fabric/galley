execute = (task, options, next) ->
  try
    unless execute.commands[task]
      throw new Error "Command '#{ task }' does not exist"

    execute.commands[task] options, next
  catch e
    console.log e

execute.commands =
  pull: require './commands/pull'
  'stop-env': require './commands/stop_env'
  cleanup: require './commands/cleanup'
  run: require './commands/run'

  help: require './commands/help'
  version: require './commands/version'
  config: require './commands/config'

module.exports = execute
