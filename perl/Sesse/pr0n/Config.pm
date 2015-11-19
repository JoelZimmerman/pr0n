# 
# Copy this file to Config-local.pm and change the values there to
# suit your own needs.
#
package Sesse::pr0n::Config;
use strict;
use warnings;

our $db_host = '127.0.0.1';
our $db_username = 'pr0n';
our $db_password = '';

our $image_base = '/srv/pr0n.sesse.net/';
our $template_base = '/srv/pr0n.sesse.net/templates';
our $overload_mode = 0;
our $overload_enable_threshold = 100.0;
our $overload_disable_threshold = 30.0;

1;
