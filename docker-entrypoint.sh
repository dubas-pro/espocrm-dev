#!/usr/bin/env bash

# Remaps www-data to the owner of the repository mounted at /var/www/default, so files created in it
# belong to them, then hands off to the entrypoint of the base image: as root for Apache (which
# starts as root and then switches to www-data itself), as www-data for any other command.

set -o errexit -o nounset -o pipefail

readonly repository=/var/www/default

# Started as another user than root (`user: www-data`): nothing can be changed, run the command as is.
if [[ "$(id --user)" -ne 0 ]]; then
    exec docker-php-entrypoint "$@"
fi

uid="$(stat --format=%u "${repository}")"
gid="$(stat --format=%g "${repository}")"

# Owned by root: nothing mounted, or a host (such as Docker Desktop) that shows files as root's.
# www-data is never made root, so it keeps its UID.
# Not usermod: it also gives the new UID the files of the home directory (/var/www), so those of the
# repository, on the host too, and goes through all of them at every start.
if [[ "${uid}" -ne 0 ]]; then
    sed --in-place --expression "s/^www-data:\([^:]*\):[0-9]*:[0-9]*:/www-data:\1:${uid}:${gid}:/" /etc/passwd
    sed --in-place --expression "s/^www-data:\([^:]*\):[0-9]*:/www-data:\1:${gid}:/" /etc/group
fi

# The home directory and the cache volumes in it (except the repository): only what isn't owned by
# www-data yet, as the volumes keep the owner of the previous start.
find /var/www -path "${repository}" -prune -o \
    \( -not -user www-data -o -not -group www-data \) \
    -exec chown --no-dereference www-data:www-data {} +

# Options only are those of apache2-foreground, for docker-php-entrypoint.
if [[ "${1:-}" == apache2-foreground || "${1:-}" == -* ]]; then
    exec docker-php-entrypoint "$@"
fi

# HOME and USER stay root's otherwise.
export HOME=/var/www USER=www-data
exec setpriv --reuid=www-data --regid=www-data --init-groups docker-php-entrypoint "$@"
