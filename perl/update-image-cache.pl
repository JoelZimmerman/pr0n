#! /usr/bin/perl

# A small hack to recalculate all existing thumbnails (including mipmaps
# if you so desire), for use when we change something in the scaling/encoding
# pipeline.  You may want to run it piece by piece if you don't want huge
# incremental backups, though.
# 
# Run as www-data, e.g. with "sudo -u www-data ./update-image-cache.pl".
# You can also give it arguments if you want to use multiple threads, with
# something like "update-image-cache.pl 0 4" to run as core 0 of four cores.
# Remember to adjust $threshold first in any case.

use lib qw(.);
use DBI;
use strict;
use warnings;

use Sesse::pr0n::Config;
eval {
	require Sesse::pr0n::Config_local;
};

# Hack :-)
package Apache2::ServerUtil;
sub server {
	return bless {};
}
sub log_error {
	print STDERR $_[1], "\n";
}

package FakeApacheReq;
sub dir_config {
	my $key = $_[1];
	my %config = (
		ImageBase => '../',
		OverloadMode => 'off',
		OverloadEnableThreshold => '100000.0',
	);
	return $config{$key};
}
sub log {
	return bless {};
}
sub info {
	print STDERR $_[1], "\n";
}
sub warn {
	print STDERR $_[1], "\n";
}
sub error {
	print STDERR $_[1], "\n";
}
package main;
use Sesse::pr0n::Common;

sub byres {
	my ($a, $b) = @_;
	if ($a == -1 && $b != -1) {
		return -1;
	}	
	if ($a != -1 && $b == -1) {
		return 1;
	}
	return ($a <=> $b);
}

sub sort_res {
	my (@res) = @_;
	my @sr = sort { ($a->[0] != $b->[0]) ? (byres($a->[0], $b->[0])) : (byres($a->[1], $b->[1])) } @res;
	my @ret = ();
	for my $r (@sr) {
		push @ret, @$r;
	}
	return @ret;
}
	
# Don't regenerate thumbnails that were made after this. Set this to approximately
# when you upgraded pr0n to the version with the new image processing code.
my $threshold = `date +%s -d '2009-10-24 11:30'`;
chomp $threshold;
my $regen_mipmaps = 0;
my $core_id = $ARGV[0] // 0;
my $num_cores = $ARGV[1] // 1;

my $dbh = DBI->connect("dbi:Pg:dbname=pr0n;host=" . $Sesse::pr0n::Config::db_host,
	$Sesse::pr0n::Config::db_username, $Sesse::pr0n::Config::db_password)
	or die "Couldn't connect to PostgreSQL database: " . DBI->errstr;
$dbh->{RaiseError} = 1;

my $r = bless {}, 'FakeApacheReq';

my $q = $dbh->prepare('SELECT id,filename,width,height FROM images WHERE id % ? = ? ORDER BY id DESC');
$q->execute($num_cores, $core_id);

while (my $ref = $q->fetchrow_hashref) {
	my $id = $ref->{'id'};
	my $dir = POSIX::floor($id / 256);

	my @files = glob("../cache/$dir/$id-*.jpg");
	if (!$regen_mipmaps) {
		@files = grep { !/mipmap/ } @files;
	}
	my @bothres = ();
	my @boxres = ();
	my @noboxres = ();
	my $any_old = 0;
	for my $c (@files) {
		my $mtime = (stat($c))[9];
		if ($mtime < $threshold) {
			$any_old = 1;
		}
		if ($c =~ /$id-(\d+)-(\d+)\.jpg/ || $c =~ /$id-(-1)-(-1)\.jpg/) {
			push @bothres, [$1, $2];
		} elsif ($c =~ /$id-(\d+)-(\d+)-nobox\.jpg/ || $c =~ /$id-(-1)-(-1)-nobox\.jpg/) {
			push @noboxres, [$1, $2];
		} elsif ($c =~ /$id-(\d+)-(\d+)-box\.png/ || $c =~ /$id-(-1)-(-1)-box\.png/) {
			push @boxres, [$1, $2];
		}
	}
	next unless $any_old;
	unlink (@files);
	if (scalar @bothres > 0) {
		Sesse::pr0n::Common::ensure_cached($r, $ref->{'filename'}, $id, $ref->{'width'}, $ref->{'height'}, 'both', sort_res(@bothres));
	}
	if (scalar @noboxres > 0) {
		Sesse::pr0n::Common::ensure_cached($r, $ref->{'filename'}, $id, $ref->{'width'}, $ref->{'height'}, 'nobox', sort_res(@noboxres));
	}
	if (scalar @boxres > 0) {
		Sesse::pr0n::Common::ensure_cached($r, $ref->{'filename'}, $id, $ref->{'width'}, $ref->{'height'}, 'box', sort_res(@boxres));
	}
	
	my @newfiles = glob("../cache/$dir/$id-*.jpg");
	my %a = map { $_ => 1 } @files;
	my %b = map { $_ => 1 } @newfiles;

	for my $f (@files) {
		if (!exists($b{$f})) {
			print STDERR "Garbage-collected $f\n";
		}
	}
}

