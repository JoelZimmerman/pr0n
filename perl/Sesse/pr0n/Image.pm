package Sesse::pr0n::Image;
use strict;
use warnings;

use Sesse::pr0n::Common qw(error dberror);
use POSIX;

sub handler {
	my $r = shift;
	my $dbh = Sesse::pr0n::Common::get_dbh();

#	if ($r->connection->remote_ip() eq '80.212.251.227') {
#		die "Har du lest FAQen?";
#	}

	# Find the event and file name
	my ($event,$filename,$xres,$yres);
	my $infobox = 1;
	if ($r->uri =~ m#^/([a-zA-Z0-9-]+)/original/(nobox/)?([a-zA-Z0-9._-]+)$#) {
		$event = $1;
		$filename = $3;
	} elsif ($r->uri =~ m#^/([a-zA-Z0-9-]+)/(\d+)x(\d+)/(nobox/)?([a-zA-Z0-9._-]+)$#) {
		$event = $1;
		$filename = $5;
		$xres = $2;
		$yres = $3;
		$infobox = 0 if (defined($4));
	} elsif ($r->uri =~ m#^/([a-zA-Z0-9-]+)/(nobox/)?([a-zA-Z0-9._-]+)$#) {
		$event = $1;
		$filename = $3;
		$xres = -1;
		$yres = -1;
		$infobox = 0 if (defined($2));
	}

	my ($id, $dbwidth, $dbheight);
	#if ($event eq 'single' && $filename =~ /^(\d+)\.jpeg$/) {
	#	$id = $1;
	#} else {
	
	# Look it up in the database
	my $ref = $dbh->selectrow_hashref('SELECT id,width,height FROM images WHERE event=? AND vhost=? AND filename=?',
		undef, $event, $r->get_server_name, $filename);
	error($r, "Could not find $event/$filename", 404, "File not found") unless (defined($ref));

	$id = $ref->{'id'};
	$dbwidth = $ref->{'width'};
	$dbheight = $ref->{'height'};

	#}
		
	$dbwidth = -1 unless defined($dbwidth);
	$dbheight = -1 unless defined($dbheight);

	# Scale if we need to do so
	my ($fname,$thumbnail) = Sesse::pr0n::Common::ensure_cached($r, $filename, $id, $dbwidth, $dbheight, $infobox, $xres, $yres);

	# Output the image to the user
	my $mime_type;
	if ($thumbnail) {
		$mime_type = "image/jpeg";
	} else {
		$mime_type = Sesse::pr0n::Common::get_mimetype_from_filename($filename);
	}
	$r->content_type($mime_type);
	
	my (undef, undef, undef, undef, undef, undef, undef, $size, undef, $mtime) = stat($fname)
                or error($r, "stat of $fname: $!");
		
	$r->set_content_length($size);
	$r->set_last_modified($mtime);

	# If the client can use cache, by all means do so
	if ((my $rc = $r->meets_conditions) != Apache2::Const::OK) {
		return $rc;
	}

	$r->sendfile($fname);

	return Apache2::Const::OK;
}

1;


