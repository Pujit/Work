#!/bin/bash

. /usr/local/bin/setora-11g

echo 'getting file list'

ls /A/GM/GMCornerstone/1.0.0.0/data/depot/workarea/gmha/catalog/in/*.* | cut -d "/" -f12 > /A/GM/GMCornerstone/1.0.0.0/data/depot/workarea/gmha/catalog/intm/holden_feed_list.txt

echo 'Feed list created'

chmod 777 /A/GM/GMCornerstone/1.0.0.0/data/depot/workarea/gmha/catalog/intm/holden_feed_list.txt
echo 'all permission given'

ecode=$?
echo "Exit Status of Load $ecode"

exit $ecode