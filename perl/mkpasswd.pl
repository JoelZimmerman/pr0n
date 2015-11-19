#! /usr/bin/perl


use lib qw(.);
use Term::ReadKey;
use strict;
use warnings;

use Sesse::pr0n::Config;
eval {
	require Sesse::pr0n::Config_local;
};
use Sesse::pr0n::Common;

Term::ReadKey::ReadMode(2);
print STDERR "Enter password: ";
chomp (my $pass = <STDIN>);
print STDERR "\n";
Term::ReadKey::ReadMode(0);

my $salt = Sesse::pr0n::Common::get_pseudorandom_bytes(16);  # Doesn't need to be cryptographically secur.
my $hash = "\$2a\$07\$" . Crypt::Eksblowfish::Bcrypt::en_base64($salt);
print Crypt::Eksblowfish::Bcrypt::bcrypt($pass, $hash), "\n";

