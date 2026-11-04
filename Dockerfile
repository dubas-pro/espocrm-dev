# Development image: PHP and Apache like the production one (the official `espocrm` image is based on
# php:*-apache too), plus Xdebug and the tools the build needs (Composer, Node.js, git).

ARG PHP_VERSION=8.5
ARG NODE_VERSION=26

FROM node:${NODE_VERSION}-trixie-slim AS node

FROM php:${PHP_VERSION}-apache-trixie

COPY --from=ghcr.io/mlocati/php-extension-installer:2 /usr/bin/install-php-extensions /usr/local/bin/
COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules

RUN set -eux; \
    ln --symbolic ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm; \
    ln --symbolic ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx; \
    # Building EspoCRM runs `grunt internal` (node build --all).
    npm install --global --no-fund --no-update-notifier grunt-cli@1; \
    npm cache clean --force; \
    \
    apt-get update; \
    apt-get install --yes --no-install-recommends git unzip; \
    rm --recursive --force /var/lib/apt/lists/*; \
    \
    # Those of production that EspoCRM uses, and Xdebug.
    install-php-extensions bcmath exif gd ldap opcache pcntl pdo_mysql zip xdebug; \
    \
    a2enmod rewrite; \
    \
    # docker-entrypoint.sh remaps www-data to the owner of the repository at start, so files created in
    # the mounted directory belong to them. This is the usual UID/GID of the first user on Linux, for
    # containers started as another user than root (`user: www-data`), which can't be remapped.
    groupmod --non-unique --gid 1000 www-data; \
    usermod --non-unique --uid 1000 --gid 1000 --home /var/www www-data; \
    # Mount points of the cache volumes (see docker-compose.yml): new volumes take over their owner.
    mkdir --parents /var/www/.cache/composer /var/www/.npm; \
    chown --recursive www-data:www-data /var/www

# EspoCRM is served from site/ (see Makefile, `node build --all`), with its own .htaccess files.
ENV APACHE_DOCUMENT_ROOT=/var/www/default/site

# Single quotes: ${APACHE_DOCUMENT_ROOT} is for Apache to expand, at start.
# hadolint ignore=SC2016
RUN set -eux; \
    sed --in-place --expression 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' \
        /etc/apache2/sites-available/*.conf /etc/apache2/conf-available/*.conf; \
    printf '<Directory ${APACHE_DOCUMENT_ROOT}>\n    AllowOverride All\n</Directory>\n' \
        > /etc/apache2/conf-available/espocrm.conf; \
    a2enconf espocrm

# Defaults; a project overrides them by mounting its own file as conf.d/99-custom.ini, read later.
COPY php.ini /usr/local/etc/php/conf.d/90-espocrm-dev.ini

ENV COMPOSER_CACHE_DIR=/var/www/.cache/composer \
    npm_config_cache=/var/www/.npm

COPY docker-entrypoint.sh /usr/local/bin/espocrm-dev-entrypoint

WORKDIR /var/www/default

# Setting ENTRYPOINT resets the CMD of the base image, so it is repeated here.
ENTRYPOINT ["espocrm-dev-entrypoint"]
CMD ["apache2-foreground"]
