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

	# Find the event and file name (nobox/ is for compatibility with legacy URLs).
	my ($event,$filename,$xres,$yres,$dpr);
	my $infobox = 0;
	if ($r->path_info =~ m#^/([a-zA-Z0-9-]+)/original/((?:no)?box/)?([a-zA-Z0-9._()-]+)$#) {
		$event = $1;
		$filename = $3;
		$infobox = 1 if (defined($2) && $2 eq 'box/');
	} elsif ($r->path_info =~ m#^/([a-zA-Z0-9-]+)/(\d+)x(\d+)(?:\@(\d+(?:\.\d+)?))?/((?:no)?box/)?([a-zA-Z0-9._()-]+)$#) {
		$event = $1;
		$filename = $6;
		$xres = $2;
		$yres = $3;
		$dpr = $4;
		$infobox = 1 if (defined($5) && $5 eq 'box/');
	} elsif ($r->path_info =~ m#^/([a-zA-Z0-9-]+)/((?:no)?box/)?([a-zA-Z0-9._()-]+)$#) {
		$event = $1;
		$filename = $3;
		$xres = -1;
		$yres = -1;
		$infobox = 1 if (defined($2) && $2 eq 'box/');
	}
	$dpr //= 1;

	my ($id, $dbwidth, $dbheight);
	#if ($event eq 'single' && $filename =~ /^(\d+)\.jpeg$/) {
	#	$id = $1;
	#} else {
	
	# Look it up in the database
	my $ref = $dbh->selectrow_hashref('SELECT id,width,height FROM images WHERE event=? AND vhost=? AND filename=?',
		undef, $event, Sesse::pr0n::Common::get_server_name($r), $filename);
	return error($r, "Could not find $event/$filename", 404, "File not found") unless (defined($ref));

	$id = $ref->{'id'};
	$dbwidth = $ref->{'width'};
	$dbheight = $ref->{'height'};

	# Scale if we need to do so
	my ($fname, $mime_type);
	if ($infobox) {
		($fname, $mime_type) = Sesse::pr0n::Common::ensure_infobox_cached($r, $filename, $id, $dbwidth, $dbheight, $dpr, $xres, $yres);
	} else {
		($fname, $mime_type) = Sesse::pr0n::Common::ensure_cached($r, $filename, $id, $dbwidth, $dbheight, $xres, $yres);
	}

	# Output the image to the user
	my $res = Plack::Response->new(200);

	if (!defined($mime_type)) {
		$mime_type = Sesse::pr0n::Common::get_mimetype_from_filename($filename);
	}
	$res->content_type($mime_type);
	
	my (undef, undef, undef, undef, undef, undef, undef, $size, undef, $mtime) = stat($fname)
                or return error($r, "stat of $fname: $!");
		
	$res->content_length($size);
	Sesse::pr0n::Common::set_last_modified($res, $mtime);

	# # If the client can use cache, by all means do so
	#if ((my $rc = $r->meets_conditions) != Apache2::Const::OK) {
	#	return $rc;
	#}

	$res->content(IO::File::WithPath->new($fname));
	return $res;
}

1;


