package Sesse::pr0n::Common;
use strict;
use warnings;

use Sesse::pr0n::Templates;
use Sesse::pr0n::Overload;

use Apache2::RequestRec (); # for $r->content_type
use Apache2::RequestIO ();  # for $r->print
use Apache2::Const -compile => ':common';
use Apache2::Log;
use ModPerl::Util;

use DBI;
use DBD::Pg;
use Image::Magick;
use POSIX;
use Digest::SHA1;
use MIME::Base64;
use MIME::Types;
use LWP::Simple;
# use Image::Info;
use Image::ExifTool;

BEGIN {
	use Exporter ();
	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

	use Sesse::pr0n::Config;
	eval {
		require Sesse::pr0n::Config_local;
	};

	$VERSION     = "v2.04";
	@ISA         = qw(Exporter);
	@EXPORT      = qw(&error &dberror);
	%EXPORT_TAGS = qw();
	@EXPORT_OK   = qw(&error &dberror);

	our $dbh = DBI->connect("dbi:Pg:dbname=pr0n;host=" . $Sesse::pr0n::Config::db_host,
		$Sesse::pr0n::Config::db_username, $Sesse::pr0n::Config::db_password)
		or die "Couldn't connect to PostgreSQL database: " . DBI->errstr;
	our $mimetypes = new MIME::Types;
	
	Apache2::ServerUtil->server->log_error("Initializing pr0n $VERSION");
}
END {
	our $dbh;
	$dbh->disconnect;
}

our ($dbh, $mimetypes);

sub error {
	my ($r,$err,$status,$title) = @_;

	if (!defined($status) || !defined($title)) {
		$status = 500;
		$title = "Internal server error";
	}
	
        $r->content_type('text/html; charset=utf-8');
	$r->status($status);

        header($r, $title);
	$r->print("    <p>Error: $err</p>\n");
        footer($r);

	$r->log->error($err);

	ModPerl::Util::exit();
}

sub dberror {
	my ($r,$err) = @_;
	error($r, "$err (DB error: " . $dbh->errstr . ")");
}

sub header {
	my ($r,$title) = @_;

	$r->content_type("text/html; charset=utf-8");

	# Fetch quote if we're itk-bilder.samfundet.no
	my $quote = "";
	if ($r->get_server_name eq 'itk-bilder.samfundet.no') {
		$quote = LWP::Simple::get("http://itk.samfundet.no/include/quotes.cli.php");
		$quote = "Error: Could not fetch quotes." if (!defined($quote));
	}
	Sesse::pr0n::Templates::print_template($r, "header", { title => $title, quotes => $quote });
}

sub footer {
	my ($r) = @_;
	Sesse::pr0n::Templates::print_template($r, "footer",
		{ version => $Sesse::pr0n::Common::VERSION });
}

sub scale_aspect {
	my ($width, $height, $thumbxres, $thumbyres) = @_;

	unless ($thumbxres >= $width &&
		$thumbyres >= $height) {
		my $sfh = $width / $thumbxres;
		my $sfv = $height / $thumbyres;
		if ($sfh > $sfv) {
			$width  /= $sfh;
			$height /= $sfh;
		} else {
			$width  /= $sfv;
			$height /= $sfv;
		}
		$width = POSIX::floor($width);
		$height = POSIX::floor($height);
	}

	return ($width, $height);
}

sub print_link {
	my ($r, $title, $baseurl, $param, $defparam) = @_;
	my $str = "<a href=\"$baseurl";
	my $first = 1;

	while (my ($key, $value) = each %$param) {
		next unless defined($value);
		next if (defined($defparam->{$key}) && $value == $defparam->{$key});
	
		$str .= ($first) ? "?" : '&amp;';
		$str .= "$key=$value";
		$first = 0;
	}
	
	$str .= "\">$title</a>";
	$r->print($str);
}

sub get_dbh {
	# Check that we are alive
	if (!(defined($dbh) && $dbh->ping)) {
		# Try to reconnect
		Apache2::ServerUtil->server->log_error("Lost contact with PostgreSQL server, trying to reconnect...");
		unless ($dbh = DBI->connect("dbi:Pg:dbname=pr0n;host=" . $Sesse::pr0n::Config::db_host,
			$Sesse::pr0n::Config::db_user, $Sesse::pr0n::Config::db_password)) {
			$dbh = undef;
			die "Couldn't connect to PostgreSQL database";
		}
	}

	return $dbh;
}

sub get_base {
	my $r = shift;
	return $r->dir_config('ImageBase');
}

sub get_disk_location {
	my ($r, $id) = @_;
        my $dir = POSIX::floor($id / 256);
	return get_base($r) . "images/$dir/$id.jpg";
}

sub get_cache_location {
	my ($r, $id, $width, $height, $infobox) = @_;
        my $dir = POSIX::floor($id / 256);

	if ($infobox) {
		return get_base($r) . "cache/$dir/$id-$width-$height.jpg";
	} else {
		return get_base($r) . "cache/$dir/$id-$width-$height-nobox.jpg";
	}
}

sub update_width_height {
	my ($r, $id, $width, $height) = @_;

	# Also find the date taken if appropriate (from the EXIF tag etc.)
	my $info = Image::ExifTool::ImageInfo(get_disk_location($r, $id));
	my $datetime = undef;

	if (defined($info->{'DateTimeOriginal'})) {
		# Parse the date and time over to ISO format
		if ($info->{'DateTimeOriginal'} =~ /^(\d{4}):(\d\d):(\d\d) (\d\d):(\d\d):(\d\d)$/ && $1 > 1990) {
			$datetime = "$1-$2-$3 $4:$5:$6";
		}
	}

	$dbh->do('UPDATE images SET width=?, height=?, date=? WHERE id=?',
		 undef, $width, $height, $datetime, $id)
		or die "Couldn't update width/height in SQL: $!";

	# update the last_picture cache as well (this should of course be done
	# via a trigger, but this is less complicated :-) )
	$dbh->do('UPDATE events SET last_picture=(SELECT COALESCE(MAX(date),\'1970-01-01 00:00:00\') FROM images WHERE event=events.id) WHERE id=(SELECT event FROM images WHERE id=?)',
		undef, $id)
		or die "Couldn't update last_picture in SQL: $!";
}

sub check_access {
	my $r = shift;

	my $auth = $r->headers_in->{'authorization'};
	if (!defined($auth) || $auth !~ m#^Basic ([a-zA-Z0-9+/]+=*)$#) {
		$r->content_type('text/plain; charset=utf-8');
		$r->status(401);
		$r->headers_out->{'www-authenticate'} = 'Basic realm="pr0n.sesse.net"';
		$r->print("Need authorization\n");
		return undef;
	}
	
	#return qw(sesse Sesse);

	my ($user, $pass) = split /:/, MIME::Base64::decode_base64($1);
	# WinXP is stupid :-)
	if ($user =~ /^.*\\(.*)$/) {
		$user = $1;
	}

	my $takenby;
	if ($user =~ /^([a-zA-Z0-9^_-]+)\@([a-zA-Z0-9^_-]+)$/) {
		$user = $1;
		$takenby = $2;
	} else {
		($takenby = $user) =~ s/^([a-zA-Z])/uc($1)/e;
	}
	
	my $oldpass = $pass;
	$pass = Digest::SHA1::sha1_base64($pass);
	my $ref = $dbh->selectrow_hashref('SELECT count(*) AS auth FROM users WHERE username=? AND sha1password=? AND vhost=?',
		undef, $user, $pass, $r->get_server_name);
	if ($ref->{'auth'} != 1) {
		$r->content_type('text/plain; charset=utf-8');
		warn "No user exists, only $auth";
		$r->status(401);
		$r->headers_out->{'www-authenticate'} = 'Basic realm="pr0n.sesse.net"';
		$r->print("Authorization failed");
		$r->log->warn("Authentication failed for $user/$takenby");
		return undef;
	}

	$r->log->info("Authentication succeeded for $user/$takenby");

	return ($user, $takenby);
}
	
sub stat_image {
	my ($r, $event, $filename) = (@_);
	my $ref = $dbh->selectrow_hashref(
		'SELECT id FROM images WHERE event=? AND filename=?',
		undef, $event, $filename);
	if (!defined($ref)) {
		return (undef, undef, undef);
	}
	return stat_image_from_id($r, $ref->{'id'});
}

sub stat_image_from_id {
	my ($r, $id) = @_;

	my $fname = get_disk_location($r, $id);
	my (undef, undef, undef, undef, undef, undef, undef, $size, undef, $mtime) = stat($fname)
		or return (undef, undef, undef);

	return ($fname, $size, $mtime);
}

sub ensure_cached {
	my ($r, $filename, $id, $dbwidth, $dbheight, $infobox, $xres, $yres, @otherres) = @_;

	my $fname = get_disk_location($r, $id);
	unless (defined($xres) && ($xres < $dbheight || $yres < $dbwidth || $dbwidth == -1 || $dbheight == -1 || $xres == -1)) {
		return ($fname, 0);
	}

	my $cachename = get_cache_location($r, $id, $xres, $yres, $infobox);
	if (! -r $cachename or (-M $cachename > -M $fname)) {
		# If we are in overload mode (aka Slashdot mode), refuse to generate
		# new thumbnails.
		if (Sesse::pr0n::Overload::is_in_overload($r)) {
			$r->log->warn("In overload mode, not scaling $id to $xres x $yres");
			error($r, 'System is in overload mode, not doing any scaling');
		}
	
		# Need to generate the cache; read in the image
		my $magick = new Image::Magick;
		my $info = Image::ExifTool::ImageInfo($fname);

		# NEF files aren't autodetected
		$fname = "NEF:$fname" if ($filename =~ /\.nef$/i);
		$r->log->warn("Generating $fname for $filename");
		
		my $err = $magick->Read($fname);
		if ($err) {
			$r->log->warn("$fname: $err");
			$err =~ /(\d+)/;
			if ($1 >= 400) {
				undef $magick;
				error($r, "$fname: $err");
			}
		}

		# If we use ->[0] unconditionally, text rendering (!) seems to crash
		my $img = (scalar @$magick > 1) ? $magick->[0] : $magick;

		my $width = $img->Get('columns');
		my $height = $img->Get('rows');

		# Update the SQL database if it doesn't contain the required info
		if ($dbwidth == -1 || $dbheight == -1) {
			$r->log->info("Updating width/height for $id: $width x $height");
			update_width_height($r, $id, $width, $height);
		}
			
		# We always want RGB JPEGs
		if ($img->Get('Colorspace') eq "CMYK") {
			$img->Set(colorspace=>'RGB');
		}

		while (defined($xres) && defined($yres)) {
			my ($nxres, $nyres) = (shift @otherres, shift @otherres);
			my $cachename = get_cache_location($r, $id, $xres, $yres, $infobox);
			
			my $cimg;
			if (defined($nxres) && defined($nyres)) {
				# we have more resolutions to scale, so don't throw
				# the image away
				$cimg = $img->Clone();
			} else {
				$cimg = $img;
			}
		
			my ($nwidth, $nheight) = scale_aspect($width, $height, $xres, $yres);

			# Use lanczos (sharper) for heavy scaling, mitchell (faster) otherwise
			my $filter = 'Mitchell';
			my $quality = 90;

			if ($width / $nwidth > 8.0 || $height / $nheight > 8.0) {
				$filter = 'Lanczos';
				$quality = 80;
			}

			if ($xres != -1) {
				$cimg->Resize(width=>$nwidth, height=>$nheight, filter=>$filter);
			}

			if (($nwidth >= 800 || $nheight >= 600 || $xres == -1) && $infobox == 1) {
				make_infobox($cimg, $info, $r);
			}

			# Strip EXIF tags etc.
			$cimg->Strip();

			$err = $cimg->write(filename=>$cachename, quality=>$quality);

			undef $cimg;

			($xres, $yres) = ($nxres, $nyres);

			$r->log->info("New cache: $nwidth x $nheight for $id.jpg");
		}
		
		undef $magick;
		undef $img;
		if ($err) {
			$r->log->warn("$fname: $err");
			$err =~ /(\d+)/;
			if ($1 >= 400) {
				@$magick = ();
				error($r, "$fname: $err");
			}
		}
	}
	return ($cachename, 1);
}

sub get_mimetype_from_filename {
	my $filename = shift;
	my MIME::Type $type = $mimetypes->mimeTypeOf($filename);
	$type = "image/jpeg" if (!defined($type));
	return $type;
}

sub make_infobox {
	my ($img, $info, $r) = @_;
	
	my @lines = ();
	my @classic_fields = ();
	
	if (defined($info->{'DateTimeOriginal'}) &&
	    $info->{'DateTimeOriginal'} =~ /^(\d{4}):(\d\d):(\d\d) (\d\d):(\d\d):(\d\d)$/
	    && $1 >= 1990) {
		push @lines, "$1-$2-$3 $4:$5";
	}

	push @lines, $info->{'Model'} if (defined($info->{'Model'}));
	
	# classic fields
	if (defined($info->{'FocalLength'}) && $info->{'FocalLength'} =~ /^(\d+)(?:\.\d+)?(?:mm)?$/) {
		push @classic_fields, ($1 . "mm");
	} elsif (defined($info->{'FocalLength'}) && $info->{'FocalLength'} =~ /^(\d+)\/(\d+)$/) {
		push @classic_fields, (sprintf "%.1fmm", ($1/$2));
	}
	if (defined($info->{'ExposureTime'}) && $info->{'ExposureTime'} =~ /^(\d+)\/(\d+)$/) {
		my ($a, $b) = ($1, $2);
		my $gcd = gcd($a, $b);
		push @classic_fields, ($a/$gcd . "/" . $b/$gcd . "s");
	}
	if (defined($info->{'FNumber'}) && $info->{'FNumber'} =~ /^(\d+)\/(\d+)$/) {
		my $f = $1/$2;
		if ($f >= 10) {
			push @classic_fields, (sprintf "f/%.0f", $f);
		} else {
			push @classic_fields, (sprintf "f/%.1f", $f);
		}
	} elsif (defined($info->{'FNumber'}) && $info->{'FNumber'} =~ /^(\d+)\.(\d+)$/) {
		my $f = $info->{'FNumber'};
		if ($f >= 10) {
			push @classic_fields, (sprintf "f/%.0f", $f);
		} else {
			push @classic_fields, (sprintf "f/%.1f", $f);
		}
	}

#	Apache2::ServerUtil->server->log_error(join(':', keys %$info));

	if (defined($info->{'NikonD1-ISOSetting'})) {
		push @classic_fields, $info->{'NikonD1-ISOSetting'}->[1] . " ISO";
	} elsif (defined($info->{'ISOSetting'})) {
		push @classic_fields, $info->{'ISOSetting'} . " ISO";
	}

	push @classic_fields, $info->{'ExposureBiasValue'} . " EV" if (defined($info->{'ExposureBiasValue'}) && $info->{'ExposureBiasValue'} != 0);
	
	if (scalar @classic_fields > 0) {
		push @lines, join(', ', @classic_fields);
	}

	if (defined($info->{'Flash'})) {
		if ($info->{'Flash'} =~ /did not fire/ || $info->{'Flash'} =~ /No Flash/) {
			push @lines, "No flash";
		} elsif ($info->{'Flash'} =~ /fired/) {
			push @lines, "Flash";
		} else {
			push @lines, $info->{'Flash'};
		}
	}

	return if (scalar @lines == 0);

	# OK, this sucks. Let's make something better :-)
	@lines = ( join(" - ", @lines) );

	# Find the required width
	my $th = 14 * (scalar @lines) + 6;
	my $tw = 1;

	for my $line (@lines) {
		my $this_w = ($img->QueryFontMetrics(text=>$line, font=>'/usr/share/fonts/truetype/msttcorefonts/Arial.ttf', pointsize=>12))[4];
		$tw = $this_w if ($this_w >= $tw);
	}

	$tw += 6;

	# Round up so we hit exact DCT blocks
	$tw += 8 - ($tw % 8) unless ($tw % 8 == 0);
	$th += 8 - ($th % 8) unless ($th % 8 == 0);
	
	return if ($tw > $img->Get('columns'));

#	my $x = $img->Get('columns') - 8 - $tw;
#	my $y = $img->Get('rows') - 8 - $th;
	my $x = 0;
	my $y = $img->Get('rows') - $th;
	$tw = $img->Get('columns');

	$x -= $x % 8;
	$y -= $y % 8;

	my $points = sprintf "%u,%u %u,%u", $x, $y, ($x+$tw-1), ($img->Get('rows') - 1);
	my $lpoints = sprintf "%u,%u %u,%u", $x, $y, ($x+$tw-1), $y;
#	$img->Draw(primitive=>'rectangle', stroke=>'black', fill=>'white', points=>$points);
	$img->Draw(primitive=>'rectangle', stroke=>'white', fill=>'white', points=>$points);
	$img->Draw(primitive=>'line', stroke=>'black', points=>$lpoints);

	my $i = -(scalar @lines - 1)/2.0;
	my $xc = $x + $tw / 2 - $img->Get('columns')/2;
	my $yc = ($y + $img->Get('rows'))/2 - $img->Get('rows')/2;
	#my $yc = ($y + $img->Get('rows'))/4;
	my $yi = $th / (scalar @lines);
	
	$lpoints = sprintf "%u,%u %u,%u", $x, $yc + $img->Get('rows')/2, ($x+$tw-1), $yc+$img->Get('rows')/2;

	for my $line (@lines) {
		$img->Annotate(text=>$line, font=>'/usr/share/fonts/truetype/msttcorefonts/Arial.ttf', pointsize=>12, gravity=>'Center',
		# $img->Annotate(text=>$line, font=>'Helvetica', pointsize=>12, gravity=>'Center',
			x=>int($xc), y=>int($yc + $i * $yi));
	
		$i = $i + 1;
	}
}

sub gcd {
	my ($a, $b) = @_;
	return $a if ($b == 0);
	return gcd($b, $a % $b);
}

1;


