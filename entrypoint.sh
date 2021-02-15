#!/bin/sh

# Import Joplin configuration from JSON, if present in /secrets volume
# readonly JOPLIN_CONFIG_JSON="/secrets/joplin-config.json"
if [ -f $JOPLIN_CONFIG_JSON ]; then
    echo "Importing Joplin configuration from $JOPLIN_CONFIG_JSON"
    echo "  ... after forcing api.port=41184"
    jq '."api.port" = 41184' <$JOPLIN_CONFIG_JSON | gosu node joplin config --import || exit
else
    echo "$JOPLIN_CONFIG_JSON does not exist; using default Joplin config"
fi

# https://joplinapp.org/terminal/#synchronisation
echo "Starting \"joplin sync\" cron job..."
cron

# Start nginx reverse proxy
service nginx start
echo "nginx reverse proxy 0.0.0.0:80 => localhost:41184 (Joplin Clipper server)"

exec gosu node "$@"
