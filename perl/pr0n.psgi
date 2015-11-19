#! /usr/bin/perl

use strict;
use warnings;
use lib qw(.);

use Plack::Request;
use Plack::Response;
use Sesse::pr0n::pr0n;

sub {
	my $env = shift;
	my $req = Plack::Request->new($env);
	my $res = Sesse::pr0n::pr0n::handler($req);
	return $res->finalize;
}
