#!/bin/bash
#
# runs after config.xml, used to clean up
#
set -e

# delete files left behind by deleted packages from config.xml
dpkg-query -f '${Package} ${Status}\n' -W 2>/dev/null \
    | awk '$4 == "config-files" {print $1}' \
    | xargs -r dpkg --purge

# stray sysv/systemd symlinks
find /etc/rc[0-6S].d /etc/systemd/system -xtype l -delete 2>/dev/null || true

# kdump-tools own debconf-generated stub, outside dpkg conffile
# tracking entirely and survives the cleaning above on its own.
rm -f /etc/default/kdump-tools

exit 0
