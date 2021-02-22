# backup-web
Backup websites based on WordPress and Drupal

```
backup-web.sh [OPTIONS] - Dump web application and its database information

This script autodetect database configuration for:
  Drupal 6.x/7.x/8.x
  WordPress 3.x/4.x/5.x

 OPTIONS:
    -n NAME         Dump name. This dump name is appended to all dump files
    -s SOURCE       Web application source path
    -d DESTINATION  Destination path
    -h              This help text
    -v              Print version number
    -c              Calculate application and database size before dump

 OUTPUT:
    DESTINATION/NAME.DATE.www.tar.gz
    DESTINATION/NAME.DATE.mysql.dcl.sql
    DESTINATION/NAME.DATE.mysql.ddl.sql
    DESTINATION/NAME.DATE.mysql.dml.sql
   
 EXAMPLES:
    backup-web.sh -n wordpress -s /var/www/html/wordpress -d /tmp/dump
    backup-web.sh -h
    backup-web.sh -v
 ```
