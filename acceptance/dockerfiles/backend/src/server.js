var http = require('http');
var fs = require('fs');

// Server that returns contents of a local file (public/index.html), the
// contents of a "config" file from /config/config.json (mapped in by
// "volumesFrom"), and the output of another HTTP request to the "database"
// container.

http.createServer(function (req, res) {
  http.get({host: 'db', port: '8080', path: '/data.json'}, function(dbres) {
    dbres.on('data', function(d) {
      try {
        var index = fs.readFileSync('public/index.html').toString();
        var config = fs.readFileSync('/config/config.json').toString();

        json = {
          index: index,
          config: JSON.parse(config),
          database: JSON.parse(d.toString()),
        }

        res.writeHead(200, {'Content-Type': 'application/json'});
        res.end(JSON.stringify(json, null, 2));
      } catch(e) {
        res.writeHead(500, {'Content-Type': 'application/json'});
        res.end(JSON.stringify({error: e.toString()}))
      }
    });
  }).on('error', function(e) {
    res.writeHead(500, {'Content-Type': 'application/json'});
    res.end(JSON.stringify({error: e.toString()}))
  });
}).listen(9615);
