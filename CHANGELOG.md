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
