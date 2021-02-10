#!/bin/sh

# Import Joplin configuration from JSON, if present in /secrets volume
# readonly JOPLIN_CONFIG_JSON="/secrets/joplin-config.json"
if [ -f $JOPLIN_CONFIG_JSON ]; then
    echo "Importing Joplin configuration from $JOPLIN_CONFIG_JSON"
    joplin config --import-file $JOPLIN_CONFIG_JSON || exit
    joplin sync || exit
else
    echo "$JOPLIN_CONFIG_JSON does not exist; using default Joplin config"
fi

exec "$@"
