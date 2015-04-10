## Overview

Galley is a command-line tool for orchestrating Docker containers in local development and test environments. Galley
automatically starts a container’s dependencies and connects it to them with Links and VolumesFrom mappings. Use
Galley to start up a web server that connects to a database. Then use it to start up a web server, its database, an 
intermediate data service, its database, some queues, worker processes, and the monitoring server they all connect 
to.

### What makes Galley different?

Galley was built to match our development process: multiple teams sharing a dozen or more services across a
variety of source code repositories. What is under active development by one team might just be a dependency to
another, so Galley gives engineers the flexibility to start the service or services they’re working with using
local source changes, while using the Docker repository’s pre-built images for any depenencies.

Galley keeps service dependencies in a central “Galleyfile” configuration so that you can always start up any 
service in your system, along with any necessary transitive dependencies.

### Features

 - Run Docker containers, linking them to their dependencies
 - Runtime control over whether to mount local source code into containers
 - Custom environments to easily run development and test containers side-by-side in isolation
 - “Addons” to define optional dependencies or configuration for services
 - Automatically re-uses running containers to support developing on multiple services simultaneously
 - Prevents “stateful” containers like databases from being wiped through recreates
 - JavaScript-based configuration allows for higher-order service definitions

Galley also has special support for running under a VM, such as when using boot2docker on Mac OS X:

 - Built-in `rsync` support for massively-improved disk performance when mapping in source code
 - Port forwarding to let other machines or mobile devices connect to containers in the VM

And, for continuous integration machines:

 - A `--repairSourceOwnership` flag keeps the container from generating files that only root can delete
 - Cleanup command to free up disk space from unused images


## Galley concepts

Before using Galley, you define a set of **services** in a central **Galleyfile**. These definitions specify what
Docker options to use to create a container for that service (image, links, volumes, *&tc.*).

When you use `galley run <service>.<env>`, you provide a **primary service** that you want to interact with, and the
**environment** to run it in. Environments are used in service definitions to vary the configuration, for example to
specify different dependencies between “dev” and “test” modes.

Environments can also have a namespace, such as `.dev.1` or `test.cucumber`. If a service does not have a
configuration for a namespaced environment, one for the base environment is used instead.

## Getting started

After you’ve installed Galley, you’ll need to write a Galleyfile. A Galleyfile is a JavaScript (or CoffeeScript)
module that exports a configuration hash that defines your services and their dependencies.

Galley expects the Galleyfile to be in a common location, rather than in a specific service’s repository.

```coffeescript
# Example Galleyfile for a small Rails app.
module.exports =

  CONFIG:
    registry: 'docker.example.biz'

  'config-files': {}

  'beanstalk':
    ports:
      'dev': ['11300:11300']

  'www-mysql':
    image: 'mysql'
    stateful: true

  'www':
    env:
      RAILS_ENV:
       'dev': 'development'
       'test': 'test'
    links:
      'dev': ['www-mysql:mysql', 'beanstalk']
      'test': ['www-mysql']
    ports:
      'dev': ['3000:3000']
    source: '/code/www'
    volumesFrom: ['config-files']
```

The above file defines a Rails “www” service that depends on a MySQL DB in test and both a MySQL DB and a beanstalk
queue in development. Additionally, it expects to have a “config-files” volume mounted in. The container’s source
code is kept in `/code/www`, so you can use `galley run -s .` to map local files over it.

Once you have a Galleyfile, point Galley at that file’s directory by running:
```
galley config set configDir /path/to/folder…
```

Test your new Galley setup with some commands:
```
  galley run www.dev                      # runs the container and its default command
  galley run -s . www.dev                 # maps the current host directory over /code/www
  galley run -s . www.test rake spec      # runs "rake spec" on a "test" environment container
```

## Command reference

### `run`

**Examples:**
```
# Starts the www service with its dev dependencies. The image’s default CMD is run.
galley run www.dev

# Maps the current directory in as the “source” directory, uses test dependencies, and runs “rake spec”.
galley run -s . www.test rake spec
```

Starts up the given service, using the environment both to name containers and to affect the service configuration.
Dependencies, either `links` or `volumesFrom`, will be started up first and recursively. Containers will be named
“<service>.<env>”. STDOUT, STDERR, and STDIN are piped from the terminal to the container.

When Galley exits it will remove the primary service container by default, but leave any dependencies running.

Galley will *always* recreate the container for the named (“primary”) service. For dependencies, Galley will look
for existing containers that match the “<service>.<env>” naming pattern, starting them if necessary. It will
delete and recreate them if:

 - their source image doesn’t match the current image for their image name (*e.g.* if an image was built or pulled
   since first starting the container)
 - their current `Links` don’t include everything in the current configuration (typically because a container they 
   depend upon has been recreated, but sometimes because an addon changes the configuration)

That being said, if a service is configured to be “stateful” in the Galleyfile, Galley will not recreate it. This is
useful for database services that you’d generally like to avoid wiping. The `--recreate` and 
`--unprotectStateful` command line options affect these behaviors; see `galley run --help` for more info.

Similar to with  `docker run`, you can provide a command and arguments after the service name to run those instead 
of the image’s default CMD. In this case, Galley will let Docker name the container randomly, to avoid naming 
conflicts with any other instances of that service that are running.

You can use the `-a` option to enable any “addons” configured for your services (primary or otherwise). Addons can
bring in additional dependencies or modify environment variables.

If you’ve configured a “source” directory for the primary service, you can use the `-s` option to map a local
directory to it. (This is more convienient than `-v` for the common case of always mapping to the same destination.)

Run also takes a number of parameters that are the equivalent to `docker run` parameters. See `galley run --help`
for a complete list.

### `stop-env`

**Examples:**
```
# Stops all dev containers
galley stop-env dev
```

Stops all containers whose names end in “.<env>”. Useful for freeing up memory in your VM or as a prelude to a
`galley cleanup` to wipe your slate.

### `pull`

**Examples:**
```
# Fetches the www image and its “test” environment transitive dependencies
galley pull www.test

# Fetches “dev” images, including dependencies added by the “beta” addon
galley pull -a beta www.dev
```

Pulls the latest image for the given primary service and any transitive dependencies that come from its
environment. Can take `-a` to include addons in the dependency tree.

Pull just updates the local Docker images, it doesn’t cause any changes to running containers. But, a follow-up
`galley run` can and will recreate any non-“stateful” containers for dependencies whose images have changed.

### `cleanup`

**Examples:**
```
galley cleanup
```

Removes any stopped containers that match Galley’s naming conventions, provided they are not for “stateful”
services. Removes their volumes as well. See `galley cleanup --help` for options that affect what’s removed.

Also deletes any dangling Docker images on the machine, to free up disk space.


## Galleyfile reference

A Galleyfile is a JavaScript or CoffeeScript module that exports a configuration hash. The keys for the hash are
the names of services in your system. Each service must have an entry, even if its value is just an empty hash.

Additionally, the special `CONFIG` key labels a hash of global configuration values.

### Global config

```coffeescript
# EXAMPLE
module.exports =
  GLOBAL:
    registry: 'docker.example.biz'
    rsync:
      image: 'docker.example.biz/rsync'
      module: 'root'
```

**registry:** The Docker registry to use when services have default image names.

**rsync:** The Docker image name and Rsync module name to use to make a container that runs an Rsync daemon. See
“rsync support” for more information.

### Service config

```coffeescript
# EXAMPLE
'www':
  addons:
    'beta':
      env:
        'USE_BETA_SERVICE': '1'
      links: ['beta', 'uploader']
  env:
    'HOST': 'localhost'
    'PROXY_FAYE':
      'test': '1'
  ports:
    'dev': ['3000:3000']
  links:
    'dev': ['mongo', 'beanstalk', 'data-service', 'redis']
    'test': ['mongo' ]
    'test.cucumber': ['mongo', 'beanstalk', 'data-service']
  source: '/code/www'
  volumesFrom: ['config-files']
```

**addons**: Hash of name to a hash of additional configuration values. Additional configuration can include
`links`, `ports`, `volumesFrom`, and `env`. When the addon is enabled via the `-a` flag to `run` or `pull`, array
values (`links`, `ports`, `volumesFrom`) are concatenated with the service’s base configuration (and any other addons). `env` values are merged, with addons taking precidence over the base values.

**binds**: Array of “Bind” strings to map host directories into the container. String format matches Docker: 
`"host_path:container_path"`

**command**: Command to override the default from the image. Can either be a string, which Docker will run with
`/bin/sh -c`, or an array of strings, which should be an executable and its arguments.

**entrypoint**: Override the default entrypoint from the image. String that matches an executable in the container.

**env**: Hash of environment variable names and their values to set in the container. If the values are themselves
hashes, they are assumed to be from Galley “env” to value.

```
'my-app':
  env:
    # $HOST will always be "localhost" in the container
    'HOST': 'localhost'

    # "galley run my-app.dev" will set $RAILS_ENV to "development"
    # "galley run my-app.test" will set $RAILS_ENV to "test"
    # "galley run my-app.other" will not have $RAILS_ENV defined
    'RAILS_ENV':
      'dev': 'development'
      'test': 'test'
```

**image**: Image name to generate the container from. Defaults to the service’s name from the default registry.

**links**: Array of links to make to other containers. Elements are either `"service_name"` or
`"service_name:alias"` (where “alias” is the hostname this container will see the service as). Alternately, can be
a hash of environment name to array of links.

```
'data-service':
  links: ['data-service-mysql:mysql']

'my-app':
  links:
    'dev': ['my-app-mysql:mysql', 'data-service']
    'test: ['my-app-mysql:mysql']

'data-service-mysql':
  image: 'docker.example.biz/mysql'

'my-app-mysql':
  image: 'docker.example.biz/mysql'
```

**ports**: Array of ports to publish when the service is run as the primary service. Array values are either
`"container_port:host_port"` or `"container_port"`. If a host port is ommitted, Docker will assign a random host
port to proxy in. Alternately, can be a hash of environment name to array of port values.

**restart**: If true, applies a Docker `RestartPolicy` of “always” to the container. Default is false.

**source**: String path to a source code directory inside the container. If `-s` is provided to `galley run`, Galley
will bind that directory to the source directory in the container.

**stateful**: If true, Galley will not remove the container in `galley run` or `galley cleanup`, even if it is
stale or missing links. Can be overridden by the `--unprotectStateful` flag. Default is false.

**user**: User to run the container as.

**volumesFrom**: Array of services whose containers should be volume-mounted into this service’s container.
Alternately, can be a hash of environment name to array of service names.


## Additional Info

### Best practices

 - Mark any databases as “stateful” to keep them from being automatically recreated. This keeps your local
   development data from disappearing on you.
 - Use addons for optional dependencies that developers don’t need all the time.
 - Only publish ports from your “dev” environment so that they won’t conflict when you run “dev” and “test”
   simultaneously.
 - Use constants and loops in your Galleyfile if they’ll make your configuration clearer and easier to maintain.

### rsync support

### Docker defaults

Galley uses a handful of defaults when working with Docker containers that we’ve found are appropriate for
development and testing. You should be aware of these, especially if you have a lot of other Docker experience.
If these aren’t working out for you, let us know; we always want to learn about new use cases!

(In these cases, the “primary service” is the one specified on the command line.)

 - If Galley is being run in a TTY, the primary service’s container is, too (`docker run -t`)
 - The primary service container is always run with STDIN allocated (`docker run -i`)
 - The primary service container is always removed when Galley stops (`docker run --rm`)
 - Volumes are always removed when removing a container (`docker rm -v`)
 - Containers are started with an `/etc/hosts` entry that points their service name to 127.0.0.1


## Contributing

We welcome GitHub issues and pull requests. Please match the existing code’s style, conventions, and test coverage.

Galley uses `gulp` for building:
```
$ gulp              # watches the Galley directory for changes to compile
$ gulp test         # runs mocha specs
$ gulp acceptance   # builds the acceptance images and runs some acceptance tests
```



##### You might want to use galley when...
Galley is awesome for putting together an environment for doing your day-to-day development work. Galley helps you keep your test and development
environments isolated, while allowing you to effectively emulate production. It helps you manage running containers, providing shortcuts for starting, stopping, and removing just the containers you want. Never accidentally destroy your database again!

You might set up galley when:
 - You want to move your development environment from Vagrant to Docker
 - You want to run your integration tests locally, against a wide range of services, each with their own dependencies
 - You have many different applications, each with shared dependencies

## Installation

```
$ npm install -g 'git+ssh://git@github.com:crashlytics/galley#distribution'
```

## Tech Details
 - galley is written in coffeescript with node.js
 - built with gulp
 - tested with mocha


