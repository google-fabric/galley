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
