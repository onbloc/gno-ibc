#!/bin/sh
cd /output
mkdir -p release
for f in modules/*; do
    ln -sf "../modules/$(basename "$f")" release/
done
for f in plugins/*; do
    ln -sf "../plugins/$(basename "$f")" release/
done
exec ./voyager start -c /config/voyager-config.gno-union.jsonc
