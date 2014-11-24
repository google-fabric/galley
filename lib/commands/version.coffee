module.exports = (options, done) ->
  cliPackage = require '../../../package'
  console.log "galley version #{cliPackage.version}"

  done?()
