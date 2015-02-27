RSVP = require 'rsvp'

# Iterates over a list, applying "cb" to each element in turn. Chains promises such that if a cb
# call returns a promise, the next iteration of the loop won't happen until that promise resolves.
#
# Explicitly being serial here. If you want parallel promise resolution, use RSVP.all.
#
# Returns a promise that resolves when the entire array has resolved.
promiseEach = (list, cb) ->
  loopPromise = RSVP.resolve()
  for el in list
    do (el) ->
      loopPromise = loopPromise.then -> cb(el)
  loopPromise

module.exports = {
  promiseEach
}
