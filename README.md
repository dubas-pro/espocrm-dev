# espocrm-dev

An unofficial Docker image for developing EspoCRM extensions: PHP and Apache like the official
`espocrm` production image, plus Xdebug, Composer and Node.js. Files it creates in your repository
belong to you.

It's made for the official extension workflow: a repository created from
[espocrm/ext-template](https://github.com/espocrm/ext-template), which builds an EspoCRM instance in
`site/`. The image doesn't replace that workflow; it runs it.

## Quick start

Add a `docker-compose.yml` to the root of your extension's repository:

```yaml
services:
  app:
    image: ghcr.io/dubas-pro/espocrm-dev:php8.5-node26
    ports:
      - 8080:80
    volumes:
      - .:/var/www/default
    # For Xdebug (needed on Linux).
    extra_hosts:
      - host.docker.internal:host-gateway
```

Then:

```sh
docker compose up --detach                        # serves site/ at http://localhost:8080
docker compose run --rm app composer install      # or npm ci, grunt, php, …
docker compose exec --user www-data app php …     # in the running container
```

To debug, start your IDE's Xdebug listener on port **9003**, then add `?XDEBUG_TRIGGER=1` to the
URL (or use a browser extension), or pass `--env XDEBUG_TRIGGER=1` to a command.

## With ext-template

Follow the [ext-template README](https://github.com/espocrm/ext-template#readme), and run its
commands in the container:

```sh
docker compose run --rm app php init.php          # once, in a new repository
docker compose run --rm app npm ci
docker compose run --rm app npm run all           # builds EspoCRM in site/, with your extension
docker compose run --rm app npm run sync          # after each change in src/
```

In its `config.json`:

- `install.siteUrl`: `http://localhost:8080`, or the port you mapped.
- `install.defaultOwner` and `install.defaultGroup`: keep the default, `www-data`, the user that
  Apache and the commands run as.
- `database`: the image has no database server. With the `db` service of the
  [full example](#full-example), which creates the database:

  ```json
  "database": {
      "host": "db",
      "port": null,
      "charset": "utf8mb4",
      "dbname": "espocrm",
      "user": "root",
      "password": "",
      "platform": "Mysql"
  }
  ```

## Tags

`php<PHP>-node<Node.js>`, such as `php8.4-node22`, for `linux/amd64` and `linux/arm64`:

- **PHP** 8.3, 8.4, 8.5: the versions the current EspoCRM supports.
- **Node.js** 22, 24, 26: the LTS lines.
- **`latest`** is `php8.5-node26`.

The images are rebuilt weekly for the security fixes of their base images. Each build is also
tagged with its date (UTC), such as `php8.4-node22-20261103`, to pin it or go back to it. When a
version reaches its end of life, its tags stop getting updates.

Each image comes with an SBOM and the provenance of its build, such as:
`docker buildx imagetools inspect ghcr.io/dubas-pro/espocrm-dev:latest --format '{{json .SBOM}}'`.

## What's in the image

- PHP with Apache (`php:<version>-apache-trixie`) and `mod_rewrite`, serving
  `/var/www/default/site` with `AllowOverride All` for EspoCRM's `.htaccess` files.
- The PHP extensions of production that EspoCRM uses (`bcmath`, `exif`, `gd`, `ldap`, `opcache`,
  `pcntl`, `pdo_mysql`, `zip`), plus Xdebug.
- Composer 2, Node.js with npm, grunt-cli, git and unzip.
- [PHP settings](php.ini): Xdebug on trigger, connecting to `host.docker.internal:9003`, and the
  limits of production. To override them, mount your own file as
  `/usr/local/etc/php/conf.d/99-custom.ini`.
- Cache directories for Composer (`/var/www/.cache/composer`) and npm (`/var/www/.npm`). Mount
  volumes there to keep the caches between containers.

## File ownership

At start, the entrypoint gives `www-data` the UID and GID of the owner of `/var/www/default`.
Apache runs as that `www-data`, and so does any other command, so you don't need `--user`.

- **Don't set `user: www-data`** (or `--user www-data` on `run`): remapping needs the container to
  start as root. Started as `www-data`, it keeps the image default, 1000:1000. In a running
  container, `exec --user www-data` is fine, as it has already been remapped.
- **Root shell:** `docker compose exec app bash`, as `exec` skips the entrypoint.
- **Rootless Docker** isn't supported: there the repository looks owned by root in the container,
  so `www-data` isn't remapped, and the files it creates get a subordinate UID on the host.

## Full example

With a database, cache volumes, the EspoCRM daemon for jobs, and the versions set from the
environment:

```yaml
volumes:
  db-data: {}
  composer-cache: {}
  npm-cache: {}

services:
  db:
    image: mariadb:lts
    environment:
      # For development only: root without a password, as in ext-template's defaults.
      MARIADB_ALLOW_EMPTY_ROOT_PASSWORD: 1
      MARIADB_DATABASE: espocrm
    volumes:
      - db-data:/var/lib/mysql
    healthcheck:
      test: [CMD, healthcheck.sh, --connect, --innodb_initialized]
      interval: 5s

  app:
    image: &image ghcr.io/dubas-pro/espocrm-dev:php${PHP_VERSION:-8.5}-node${NODE_VERSION:-26}
    depends_on:
      db:
        condition: service_healthy
    ports:
      - ${HTTPD_PORT:-8080}:80
    volumes: &volumes
      - .:/var/www/default
      # Optional: your own PHP settings, over the defaults of the image.
      # - ./php.ini:/usr/local/etc/php/conf.d/99-custom.ini:ro
      - composer-cache:/var/www/.cache/composer
      - npm-cache:/var/www/.npm
    extra_hosts: &extra-hosts
      - host.docker.internal:host-gateway

  daemon:
    image: *image
    # Restarted until site/ is built.
    restart: unless-stopped
    stop_grace_period: 1s
    working_dir: /var/www/default/site
    command: [php, daemon.php]
    volumes: *volumes
    extra_hosts: *extra-hosts
```

## Maintenance

Build locally (the defaults are the versions of `latest`):

```sh
docker build --build-arg PHP_VERSION=8.4 --build-arg NODE_VERSION=24 --tag espocrm-dev .
```

The versions are the matrix of [.github/workflows/build.yml](.github/workflows/build.yml):

- **New version:** Renovate opens a pull request that bumps the defaults in the
  [Dockerfile](Dockerfile). In it, also add the version to the matrix, move `latest`, and update
  [Tags](#tags).
- **End of life:** 90 days before it (according to [endoflife.date](https://endoflife.date)),
  [a weekly check](.github/workflows/eol-check.yml) opens an issue to drop the version.

## Disclaimer

This is an unofficial project, not associated with EspoCRM or Letrium Ltd. EspoCRM is a trademark of
Letrium Ltd, used here only to name the software that the image is for. Its use doesn't imply any
sponsorship, endorsement or affiliation.
