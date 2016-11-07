![Galley](docs/images/galley-red.png)


[![Build Status](https://travis-ci.org/twitter-fabric/galley.svg?branch=master)](https://travis-ci.org/twitter-fabric/galley)

## Overview

Galley is a command-line tool for orchestrating [Docker](https://www.docker.com/) containers in development
and test environments. Galley automatically starts a container’s dependencies and connects them using Docker’s
`Links` and `VolumesFrom` mappings. Use Galley to start up a web server that connects to a database. Then, use it to
start up a web server, its database, an intermediate data service (and its database), some queues, worker processes, and
the monitoring server they all connect to.

**Latest version:** 1.2.1

- Fix a bug with the new watch ignore logic not creating a proper regex.

### What makes Galley different?

Galley was built to support [Fabric](http://fabric.io)’s internal development process: multiple teams
sharing a dozen or more services across a
variety of source code repositories. What is under active development by one team might just be a dependency to
another, so Galley gives engineers the flexibility to start the service or services they’re working with using
local source code, while getting pre-built images for any dependencies.

Galley keeps service dependencies in a central “Galleyfile” configuration so that you can always start up any
service in your system, along with any necessary transitive dependencies.

### Features

 - Run Docker containers, linking them to their dependencies
 - Dynamic mapping of local source code into containers
 - Custom environments to easily run isolated development and test containers side-by-side
 - “Addons” to define optional configuration for services
 - Automatic re-use of running containers to support developing multiple services simultaneously
 - Protected “stateful” containers (*e.g.* databases)
 - JavaScript-based configuration for higher-order service definitions

Galley also has special support for running under a VM, such as when using [docker-machine](https://docs.docker.com/machine/) on Mac OS X:

 - Built-in `rsync` support for massively-improved disk performance with VirtualBox for local source code.
 - Port forwarding to let other machines or mobile devices connect to containers in the VM

And, for continuous integration machines:

 - A `--repairSourceOwnership` flag keeps containers running as root from generating files that only root can delete
 - Cleanup command to free up disk space from unused images

### Bug Reports and Discussion

If you find something wrong with Galley, please let us know on the
[issues](https://github.com/twitter-fabric/galley/issues) page.

You can also chat with us or ask for help on the
[galley-discuss@googlegroups.com](https://groups.google.com/forum/#!forum/galley-discuss) mailing list.

## Galley concepts

To use Galley you define a set of **services** in a central **Galleyfile**. These definitions specify
Docker options for each service (image, links, volumes, *etc.*).

When you use `galley run <service>.<env>`, you provide a **primary service** that you want to interact with, and the
**environment** to run it in. Environments are used in service definitions to vary the configuration, for example to
specify different dependencies between “dev” and “test” modes.

Environments can also have a namespace, such as `.dev.1` or `test.cucumber`. If a service does not have a
configuration for a namespaced environment, the one for the base environment is used instead.

Not all services must have environment-specific configurations. For a service with no environment configuration, the
service's base environment configuration is used.

## Quick start

*Note that Galley requires node >= version 5 to run*

```console
$ npm install -g galley-cli
$ git clone https://github.com/twitter-fabric/galley-template.git
$ cd galley-template
$ galley run demo.dev
```

## Setting up Galley

### Installation

Galley is distributed as a command-line tool, `galley`, and a library. Install the command-line
tool globally from the [galley-cli NPM package](https://www.npmjs.com/package/galley-cli):

```console
$ npm install -g galley-cli
```

### Create a Galleyfile package

Galley keeps your system’s configuration in a central Galleyfile. This file must be in a directory with
an NPM package.json file that depends on the [galley NPM package](https://www.npmjs.com/package/galley).
You will typically symlink the Galleyfile into the local directory where you keep your repositories.

When you run the `galley` tool, it recursively walks up your directories until it finds a Galleyfile
or a symlink to one. It then uses the galley library depended on by that package to execute your
commands.

The easiest way to get started with a Galleyfile is to clone our template:

```console
$ git clone https://github.com/twitter-fabric/galley-template.git
```

You can also create an NPM package from scratch:

```console
$ npm init
$ npm install --save galley
$ npm shrinkwrap
```

### Writing a Galleyfile

A Galleyfile is a JavaScript module that exports a configuration hash that defines your services and
their dependencies.

Services are expected to share a common Galleyfile that defines the dependencies among
them. You should put your Galleyfile in a common place, and then symlink to it from a
parent directory for your services. The `galley` CLI tool will search for a Galleyfile recursively
from the directory it’s run in.

#### Example

The file below defines a Rails “www” service that depends on a MySQL DB in test and both a MySQL DB and a beanstalk
queue in development. Additionally, it expects to have a “config-files” volume mounted in. The container’s source
code is kept in `/code/www`, so you can use `galley run -s .` to map a local directory over it.

```javascript
// Example Galleyfile.js for a small Rails app.
module.exports = {
  CONFIG: {
    registry: 'docker.example.biz'
  },

  'config-files': {},
  'beanstalk': {},

  'www-mysql': {
    image: 'mysql',
    stateful: true
  },

  'www': {
    env: {
      RAILS_ENV: {
       'dev': 'development',
       'test': 'test'
      }
    },
    links: {
      'dev': ['www-mysql:mysql', 'beanstalk'],
      'test': ['www-mysql']
    },
    ports: {
      'dev': ['3000:3000']
    },
    source: '/code/www',
    volumesFrom: ['config-files']
  }
};
```

Then, from a common parent directory of your services' source directories:
```console
$ ln -s ../../path/to/Galleyfile.js .
```

### Running Galley

Once you’ve written a Galleyfile and symlinked it, try it out:

```bash
$ galley list
```
```
Galleyfile: /path/to/found/Galleyfile.js
  beanstalk
  config-files
  www [.dev, .test]
  www-mysql
```

## Command reference

### `run`

**Examples:**
```
# Starts the www service with its dev dependencies. Runs the image’s default CMD.
galley run www.dev

# Maps the current directory in as the “source” directory, uses test dependencies, and runs “rake spec”.
galley run -s . www.test rake spec
```

Starts up the given service, using the environment both to name containers and to affect the service configuration.
Dependencies, either `links` or `volumesFrom`, will be started up first and recursively. Containers will be named
`<service>.<env>`. STDOUT, STDERR, and STDIN are piped from the terminal to the container.

When Galley exits it will remove the primary service container by default, but leave any dependencies running.

Galley will *always* recreate the container for the named (“primary”) service. For dependencies, Galley will look
for existing containers that match the `<service>.<env>` naming pattern, starting them if necessary. It will
delete and recreate them if:

 - their source image doesn’t match the current image for their image name (*e.g.* if an image was built or pulled
   since first starting the container)
 - their current `Links` don’t include everything in the current configuration (typically because a container they
   depend upon has been recreated, but sometimes because an addon changes the configuration)

If a service is configured to be “stateful” in the Galleyfile, Galley will not recreate it.
This is useful for development database services that would get wiped if that happened, losing hard-won state. The
`--recreate` and  `--unprotectStateful` command line options affect these behaviors; see `galley run --help` for
more info.

Similar to `docker run`, you can provide a command and arguments after the service name to run those instead
of the image’s default CMD. In this case, Galley will let Docker name the container randomly, to avoid naming
conflicts with any other instances of that service that are running.

You can use the `-a` option to enable any “addons” configured for your services (primary or otherwise). Addons can
bring in additional dependencies or modify environment variables.

If you’ve configured a “source” directory for the primary service, then you can use the `-s` option to map a local
directory to it. (This is more convenient than `-v` for the common case of regularly mapping to the same
destination.)

Run also takes a number of parameters that are the equivalent to `docker run` parameters. See `galley run --help`
for a complete list.

### `list`

**Examples:**
```
galley list
```

Prints the name of each service in the Galleyfile, along with the environments it’s configured for and which
addons affect it.

### `stop-env`

**Examples:**
```
# Stops all dev containers
galley stop-env dev
```

Stops all containers whose names end in `.<env>`. Useful for freeing up memory in your VM or as a prelude to a
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

`galley pull` just updates the local Docker images, it doesn’t cause any changes to running containers. A follow-up
`galley run` will recreate any non-“stateful” containers for dependencies whose images have changed.

### `cleanup`

**Examples:**
```
galley cleanup
```

Removes any stopped containers that match Galley’s naming conventions, provided they are not for “stateful”
services. Removes their volumes as well. See `galley cleanup --help` for options that affect what’s removed.

Deletes any dangling Docker images on the machine, to free up disk space.

## Galleyfile reference

A Galleyfile is a JavaScript or CoffeeScript module that exports a configuration hash. The keys for the hash are
the names of services in your system. Each service must have an entry, even if its value is just an empty hash.

Additionally, the special `CONFIG` key labels a hash of global configuration values.

### Global config

```javascript
module.exports = {
  CONFIG: {
    registry: 'docker.example.biz',
    rsync: {
      image: 'docker.example.biz/rsync',
      module: 'root'
    }
  }
  …
};
```

**registry:** The Docker registry to use when services have default image names.

**rsync:** Custom Docker image name and Rsync module name to use to make a container that runs an Rsync daemon. See
[rsync support](#rsync-support) for more information.

### Service config

```javascript
'www': {
  env: {
    'HOST': 'localhost',
    'PROXY_FAYE': {
      'test': '1'
    }
  },
  ports: {
    'dev': ['3000:3000']
  },
  links: {
    'dev': ['mongo', 'beanstalk', 'data-service', 'redis'],
    'test': ['mongo'],
    'test.cucumber': ['mongo', 'beanstalk', 'data-service'],
  },
  source: '/code/www',
  volumesFrom: ['config-files']
}
```

**addons**: Hash of name to a hash of additional configuration values. Additional configuration can include
`links`, `ports`, `volumesFrom`, and `env`. When the addon is enabled via the `-a` flag to `run` or `pull`, array
values (`links`, `ports`, `volumesFrom`) are concatenated with the service’s base configuration (and any other addons). `env` values are merged, with addons taking precidence over the base values.

**binds**: Array of “Bind” strings to map host directories into the container. String format matches Docker:
`"host_path:container_path"`

**command**: Command to override the default from the image. Can either be a string, which Docker will run with
`/bin/sh -c`, or an array of strings, which should be an executable and its arguments.

**entrypoint**: Override the default entrypoint from the image. String path for an executable in the container.

**env**: Hash of environment variable names and their values to set in the container. If the values are themselves
hashes, they are assumed to be from Galley “env” to value.

```javascript
'my-app': {
  env: {
    // $HOST will always be "localhost" in the container
    'HOST': 'localhost',

    // "galley run my-app.dev" will set $RAILS_ENV to "development"
    // "galley run my-app.test" will set $RAILS_ENV to "test"
    // "galley run my-app.test.cucumber" will also set $RAILS_ENV to "test"
    // "galley run my-app.other" will not have $RAILS_ENV defined
    'RAILS_ENV': {
      'dev': 'development',
      'test': 'test'
    }
  }
}
```

**image**: Image name to generate the container from. Defaults to the service’s name from the default registry.

**links**: Array of links to make to other containers. Elements are either `"service_name"` or
`"service_name:alias"` (where “alias” is the hostname this container will see the service as). Alternately, the value
can be a hash of environment name to array of links.

```javascript
'data-service': {
  links: ['data-service-mysql:mysql']
},

'my-app': {
  links: {
    'dev': ['my-app-mysql:mysql', 'data-service'],
    'test': ['my-app-mysql:mysql']
  }
},

'data-service-mysql': {
  image: 'docker.example.biz/mysql'
},

'my-app-mysql': {
  image: 'docker.example.biz/mysql'
},
```

**ports**: Array of ports to publish when the service is run as the primary service. Array values are either
`"host_port:container_port"` or `"container_port"`. If a host port is ommitted, Docker will assign a random host
port to proxy in. Alternately, can be a hash of environment name to array of port values. Ports need not be
exposed by the Dockerfile.

**restart**: Boolean. If `true`, applies a Docker `RestartPolicy` of “always” to the container. Default is `false`.

**source**: String path to a source code directory inside the container. If `-s` is provided to `galley run`, Galley
will bind that directory to the source directory in the container.

**stateful**: Boolean. If `true`, Galley will not remove the container in `galley run` or `galley cleanup`, even if it
is stale or missing links. Can be overridden for a command by the `--unprotectStateful` flag. Default is `false`.

**user**: User to run the container as.

**volumesFrom**: Array of services whose containers should be volume-mounted into this service’s container.
Alternately, can be a hash of environment name to array of service names.

### Addons

```javascript
# EXAMPLE
module.exports = {
  …
  ADDONS: {
    'beta': {
      'www': {
        env: {
          'USE_BETA_SERVICE': '1'
        },
        links: ['beta', 'uploader']
      },
      'uploader': {
        env: {
          'USE_BETA_SERVICE': '1'
        }
      }
    }
  }
  …
};
```

Addons are extra configurations that can be applied from the command line. An addon can include
additional `links`, `ports`, `volumesFrom`, and `env` values that are merged with a service’s
base configuration. Addons are defined globally because they can affect multiple services.


### .galleycfg reference

Galley can write a .galleycfg JSON configuration file into `~` when you run `galley config`.
Currently, the only state read from the config file is the default value of the `--rsync` flag.

You can write to the .galleycfg file with:

`galley config set key value`


An example .galleycfg:

```
{
  "rsync": true
}
```


### Best practices

 - Mark any databases as “stateful” to keep them from being automatically recreated. This keeps your local
   development data from disappearing on you.
 - Use addons for optional dependencies that developers don’t need all the time.
 - Only publish ports from your “dev” environment so that they won’t conflict when you run “dev” and “test”
   simultaneously.
 - Use constants and loops in your Galleyfile if they’ll make your configuration clearer and easier to maintain.

### rsync support

Galley includes built-in support for using rsync to copy local source changes into a container. This provides
a significant speed boost over VirtualBox’s shared folders when working on Mac OS X with `docker-machine`.

To use it, just add `--rsync` to your `galley run` commands when you use `--source`.

You can turn on `--rsync` by default with:
```console
$ galley config set rsync true
```

rsync support requires that an rsync server container be run and volume-mapped in to your service’s
container. By default, Galley downloads and uses [galley/rsync](https://hub.docker.com/r/galley/rsync/),
but you can specify your own container in the `CONFIG` section of your Galleyfile.

**Caveat:** Galley’s rsyncing goes one way, from outside the container to inside it. Files changed or created
inside the container are not copied back out to the local disk. In the cases where you need to have a
bi-directional mapping, use `--rsync false` to temporarily disable rsync.

Also note that `--rsync` only affects the `--source` mapping, not any `--volume` mappings that you specify.

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

## Frequently Asked Questions

#### How is Galley different from Docker Compose?

There’s a lot of intersection between Galley and Docker Compose for doing development and testing.
Galley has been tuned to how we’ve been using containers, which we’ve been happy with but might
not work for you. You may want to try both and see which is a better fit for your team and your system.

Some things to highlight:

 * The Galleyfile configuration describes your entire system in one place to capture all of your
   dependencies. One team may be actively developing a service and need to run it with local changes,
   while another team could just need that service transitively and run it off of an image without
   ever cloning the source repo.

 * Docker Compose typically starts and stops several containers as a unit and merges their log
   output. Each Galley process focuses on a single container, starting up its dependencies only if
   they’re not already running. Galley processes share common containers within an enviroment, which
   is important for testing co-ordinated changes.

 * Galley does not do any container building on its own. (We’ve been using CI jobs for that.) Galley
   also provides no features around running containers in production.

Also take a look at `--rsync`, `--localhost`, and other little features we’ve added based on our
experience building Fabric with Galley.

(And please correct us if we’re mis-representing Docker Compose. We started building Galley before
it was released, and think a diversity of approaches is healthy for the ecosystem.)

#### Can I use CoffeeScript to write my Galleyfile?

Yes. That’s actually what we do on Fabric, because it makes the configuration file much more
readable while still giving us the opportunity to refactor the configuration as code. You’ll need
to depend on `coffee-script` in your Galleyfile package, and use this for your `Galleyfile.js`:

```javascript
require('coffee-script/register');
module.exports = require('./Galleyfile.coffee');
```

## Contributing

We welcome GitHub issues and pull requests. Please match the existing CoffeeScript style, conventions, and test
coverage.

First run `npm install` to fetch dependencies.

Galley uses `gulp` for building:
```
$ gulp watch        # watches the Galley directory for changes to compile
$ gulp compile      # compile galley before running tests (if you’re not running gulp watch)
$ gulp test         # runs mocha specs
$ gulp acceptance   # builds the acceptance images and runs some acceptance tests
```
