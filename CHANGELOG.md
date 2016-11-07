### Next Release
#### Bug fixes
#### Features

### v1.2.2 (2016-11-07):
#### Features
 - Fix additional errors with watch logic

### v1.2.1 (2016-11-07):
#### Features
 - Fix a bug with the new watch ignore logic not creating a proper regex.

### v1.2.0 (2016-11-03):
#### Features
 - Files in `.dockerignore` will be ignored by the rsync container.
   This should improve performance in projects with many files that would be ignored (e.g. `node_modules`).

### v1.1.2 (2016-09-23):
#### Bug fixes
- Fix a bug that prevented some errors from getting logged.

### v1.1.1 (2016-06-27):
#### Bug fixes
- Fix a bug that prevented starting services that aliased links.

### v1.1.0 (2016-06-24):
#### Bug fixes
 - Fix recreation logic for missing links on Docker >= 1.10 (#40)

### v1.0.3 (2016-05-12):
#### Bug fixes
 - Updates dependencies for Node 6 compatibility
 - Fixes crash when pulling containers with Docker 1.11

### v1.0.2 (2016-01-27):
#### Features
 - "/udp" can now be used when specifying port mappings

#### Bug fixes
 - Deleting the primary service container at the end of a run now removes its
   volumes as well

### v1.0.1 (2016-01-14):
#### Features
 - Using a custom command reports the auto-generated container name
 - The `--as-service` flag on a custom command will maintain the service’s
   default container name and port bindings
 - `stop-env` can now take any number of environments

#### Bug fixes
 - Galleyfile port bindings now work regardless of what ports are `EXPOSE`d in
   the Dockerfile
 - DockerHub credentials are now used for pulls to the default Docker registry

### v1.0.0 (2015-10-20):

Initial release!
