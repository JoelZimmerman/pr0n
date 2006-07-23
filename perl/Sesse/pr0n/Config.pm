# 
# Copy this file to Config-local.pm and change the values there to
# suit your own needs.
#
# Note that most configuration is done in your vhost; this isn't,
# because it's persistent between sessions and we don't have access
# to the Apache configuration data then.
#
package Sesse::pr0n::Config;
use strict;
use warnings;

our $db_host = '127.0.0.1';
our $db_username = 'pr0n';
our $db_password = '';

1;
