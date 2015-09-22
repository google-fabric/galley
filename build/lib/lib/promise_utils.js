var RSVP, promiseEach;

RSVP = require('rsvp');

promiseEach = function(list, cb) {
  var el, fn, i, len, loopPromise;
  loopPromise = RSVP.resolve();
  fn = function(el) {
    return loopPromise = loopPromise.then(function() {
      return cb(el);
    });
  };
  for (i = 0, len = list.length; i < len; i++) {
    el = list[i];
    fn(el);
  }
  return loopPromise;
};

module.exports = {
  promiseEach: promiseEach
};
