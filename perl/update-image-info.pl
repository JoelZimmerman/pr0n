#! /usr/bin/perl
use lib qw(.);
use DBI;
use POSIX;
use Image::ExifTool;
use Encode;
use strict;
use warnings;

use Sesse::pr0n::Config;
eval {
	require Sesse::pr0n::Config_local;
};
	
my $dbh = DBI->connect("dbi:Pg:dbname=pr0n;host=" . $Sesse::pr0n::Config::db_host,
	$Sesse::pr0n::Config::db_username, $Sesse::pr0n::Config::db_password)
	or die "Couldn't connect to PostgreSQL database: " . DBI->errstr;
$dbh->{RaiseError} = 1;

my $q = $dbh->prepare('SELECT id FROM images WHERE id NOT IN ( SELECT DISTINCT image FROM exif_info ) ORDER BY id');
$q->execute;

while (my $ref = $q->fetchrow_hashref) {
	my $id = $ref->{'id'};

	# Copied almost verbatim from Sesse::pr0n::Common::update_image_info
	my $info = Image::ExifTool::ImageInfo(get_disk_location($id));
	my $width = $info->{'ImageWidth'} || -1;
	my $height = $info->{'ImageHeight'} || -1;
	my $datetime = undef;
			
	if (defined($info->{'DateTimeOriginal'})) {
		# Parse the date and time over to ISO format
		if ($info->{'DateTimeOriginal'} =~ /^(\d{4}):(\d\d):(\d\d) (\d\d):(\d\d):(\d\d)(?:\+\d\d:\d\d)?$/ && $1 > 1990) {
			$datetime = "$1-$2-$3 $4:$5:$6";
		}
	}

	{
		local $dbh->{AutoCommit} = 0;

		$dbh->do('UPDATE images SET width=?, height=?, date=? WHERE id=?',
			 undef, $width, $height, $datetime, $id)
			or die "Couldn't update width/height in SQL: $!";

		$dbh->do('DELETE FROM exif_info WHERE image=?',
			undef, $id)
			or die "Couldn't delete old EXIF information in SQL: $!";

		my $q = $dbh->prepare('INSERT INTO exif_info (image,tag,value) VALUES (?,?,?)')
			or die "Couldn't prepare inserting EXIF information: $!";

		for my $key (keys %$info) {
			next if ref $info->{$key};
			$q->execute($id, $key, guess_charset($info->{$key}))
				or die "Couldn't insert EXIF information in database: $!";
		}

		# update the last_picture cache as well (this should of course be done
		# via a trigger, but this is less complicated :-) )
		$dbh->do('UPDATE last_picture_cache SET last_picture=GREATEST(last_picture, ?) WHERE event=(SELECT event FROM images WHERE id=?)',
			undef, $datetime, $id)
			or die "Couldn't update last_picture in SQL: $!";
	}

	print "Updated $id.\n";
}

sub get_disk_location {
	my ($id) = @_;
        my $dir = POSIX::floor($id / 256);
	return "/srv/pr0n.sesse.net/images/$dir/$id.jpg";
}

sub guess_charset {
	my $text = shift;
	my $decoded;

	eval {
		$decoded = Encode::decode("utf-8", $text, Encode::FB_CROAK);
	};
	if ($@) {
		$decoded = Encode::decode("iso8859-1", $text);
	}

	return $decoded;
}

