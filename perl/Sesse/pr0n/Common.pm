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

use Carp;
use Encode;
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
use HTML::Entities;
use URI::Escape;

BEGIN {
	use Exporter ();
	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

	use Sesse::pr0n::Config;
	eval {
		require Sesse::pr0n::Config_local;
	};

	$VERSION     = "v2.53";
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
	$r->log->error("Stack trace follows: " . Carp::longmess());

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
	Sesse::pr0n::Templates::print_template($r, "header", { title => $title, quotes => Encode::decode_utf8($quote) });
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

sub get_query_string {
	my ($param, $defparam) = @_;
	my $first = 1;
	my $str = "";

	while (my ($key, $value) = each %$param) {
		next unless defined($value);
		next if (defined($defparam->{$key}) && $value == $defparam->{$key});

		$value = pretty_escape($value);
	
		$str .= ($first) ? "?" : ';';
		$str .= "$key=$value";
		$first = 0;
	}
	return $str;
}

# This is not perfect (it can't handle "_ " right, for one), but it will do for now
sub weird_space_encode {
	my $val = shift;
	if ($val =~ /_/) {
		return "_" x (length($val) * 2);
	} else {
		return "_" x (length($val) * 2 - 1);
	}
}

sub weird_space_unencode {
	my $val = shift;
	if (length($val) % 2 == 0) {
		return "_" x (length($val) / 2);
	} else {
		return " " x ((length($val) + 1) / 2);
	}
}
		
sub pretty_escape {
	my $value = shift;

	$value =~ s/(([_ ])\2*)/weird_space_encode($1)/ge;
	$value = URI::Escape::uri_escape($value);
	$value =~ s/%2F/\//g;

	return $value;
}

sub pretty_unescape {
	my $value = shift;

	# URI unescaping is already done for us
	$value =~ s/(_+)/weird_space_unencode($1)/ge;

	return $value;
}

sub print_link {
	my ($r, $title, $baseurl, $param, $defparam, $accesskey) = @_;
	my $str = "<a href=\"$baseurl" . get_query_string($param, $defparam) . "\"";
	if (defined($accesskey) && length($accesskey) == 1) {
		$str .= " accesskey=\"$accesskey\"";
	}
	$str .= ">$title</a>";
	$r->print($str);
}

sub get_dbh {
	# Check that we are alive
	if (!(defined($dbh) && $dbh->ping)) {
		# Try to reconnect
		Apache2::ServerUtil->server->log_error("Lost contact with PostgreSQL server, trying to reconnect...");
		unless ($dbh = DBI->connect("dbi:Pg:dbname=pr0n;host=" . $Sesse::pr0n::Config::db_host,
			$Sesse::pr0n::Config::db_username, $Sesse::pr0n::Config::db_password)) {
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

sub update_image_info {
	my ($r, $id, $width, $height) = @_;

	# Also find the date taken if appropriate (from the EXIF tag etc.)
	my $exiftool = Image::ExifTool->new;
	$exiftool->ExtractInfo(get_disk_location($r, $id));
	my $info = $exiftool->GetInfo();
	my $datetime = undef;
			
	if (defined($info->{'DateTimeOriginal'})) {
		# Parse the date and time over to ISO format
		if ($info->{'DateTimeOriginal'} =~ /^(\d{4}):(\d\d):(\d\d) (\d\d):(\d\d):(\d\d)(?:\+\d\d:\d\d)?$/ && $1 > 1990) {
			$datetime = "$1-$2-$3 $4:$5:$6";
		}
	}

	{
		local $dbh->{AutoCommit} = 0;

		# EXIF information
		$dbh->do('DELETE FROM exif_info WHERE image=?',
			undef, $id)
			or die "Couldn't delete old EXIF information in SQL: $!";

		my $q = $dbh->prepare('INSERT INTO exif_info (image,key,value) VALUES (?,?,?)')
			or die "Couldn't prepare inserting EXIF information: $!";

		for my $key (keys %$info) {
			next if ref $info->{$key};
			$q->execute($id, $key, guess_charset($info->{$key}))
				or die "Couldn't insert EXIF information in database: $!";
		}

		# Model/Lens
		my $model = $exiftool->GetValue('Model', 'PrintConv');
		my $lens = $exiftool->GetValue('Lens', 'PrintConv');
		$lens = $exiftool->GetValue('LensSpec', 'PrintConv') if (!defined($lens));

		$model =~ s/^\s*//;
		$model =~ s/\s*$//;
		$model = undef if (length($model) == 0);

		$lens =~ s/^\s*//;
		$lens =~ s/\s*$//;
		$lens = undef if (length($lens) == 0);
		
		# Now update the main table with the information we've got
		$dbh->do('UPDATE images SET width=?, height=?, date=?, model=?, lens=? WHERE id=?',
			 undef, $width, $height, $datetime, $model, $lens, $id)
			or die "Couldn't update width/height in SQL: $!";
		
		# Tags
		my @tags = $exiftool->GetValue('Keywords', 'ValueConv');
		$dbh->do('DELETE FROM tags WHERE image=?',
			undef, $id)
			or die "Couldn't delete old tag information in SQL: $!";

		$q = $dbh->prepare('INSERT INTO tags (image,tag) VALUES (?,?)')
			or die "Couldn't prepare inserting tag information: $!";


		for my $tag (@tags) {
			$q->execute($id, guess_charset($tag))
				or die "Couldn't insert tag information in database: $!";
		}

		# update the last_picture cache as well (this should of course be done
		# via a trigger, but this is less complicated :-) )
		$dbh->do('UPDATE last_picture_cache SET last_picture=GREATEST(last_picture, ?) WHERE (vhost,event)=(SELECT vhost,event FROM images WHERE id=?)',
			undef, $datetime, $id)
			or die "Couldn't update last_picture in SQL: $!";
	}
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
	unless (defined($xres) && (!defined($dbwidth) || !defined($dbheight) || $xres < $dbheight || $yres < $dbwidth || $xres == -1)) {
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
		my $err;

		# ImageMagick can handle NEF files, but it does it by calling dcraw as a delegate.
		# The delegate support is rather broken and causes very odd stuff to happen when
		# more than one thread does this at the same time. Thus, we simply do it ourselves.
		if ($filename =~ /\.nef$/i) {
			# this would suffice if ImageMagick gets to fix their handling
			# $fname = "NEF:$fname";
			
			open DCRAW, "-|", "dcraw", "-w", "-c", $fname
				or error("dcraw: $!");
			$err = $magick->Read(file => \*DCRAW);
			close(DCRAW);
		} else {
			$err = $magick->Read($fname);
		}
		
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
		if (!defined($dbwidth) || !defined($dbheight)) {
			$r->log->info("Updating width/height for $id: $width x $height");
			update_image_info($r, $id, $width, $height);
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
			my $sf = undef;

			if ($width / $nwidth > 8.0 || $height / $nheight > 8.0) {
				$filter = 'Lanczos';
				$quality = 85;
				$sf = "1x1";
			}

			if ($xres != -1) {
				$cimg->Resize(width=>$nwidth, height=>$nheight, filter=>$filter);
			}

			if (($nwidth >= 800 || $nheight >= 600 || $xres == -1) && $infobox == 1) {
				make_infobox($cimg, $info, $r);
			}

			# Strip EXIF tags etc.
			$cimg->Strip();

			{
				my %parms = (
					filename => $cachename,
					quality => $quality
				);
				if (($nwidth >= 640 && $nheight >= 480) ||
				    ($nwidth >= 480 && $nheight >= 640)) {
				    	$parms{'interlace'} = 'Plane';
				}
				if (defined($sf)) {
					$parms{'sampling-factor'} = $sf;
				}
				$err = $cimg->write(%parms);
			}

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

	# The infobox is of the form
	# "Time - date - focal length, shutter time, aperture, sensitivity, exposure bias - flash",
	# possibly with some parts omitted -- the middle part is known as the "classic
	# fields"; note the comma separation. Every field has an associated "bold flag"
	# in the second part.
	
	my $shutter_priority = (defined($info->{'ExposureProgram'}) &&
		$info->{'ExposureProgram'} =~ /shutter\b.*\bpriority/i);
	my $aperture_priority = (defined($info->{'ExposureProgram'}) &&
		$info->{'ExposureProgram'} =~ /aperture\b.*\bpriority/i);

	my @classic_fields = ();
	if (defined($info->{'FocalLength'}) && $info->{'FocalLength'} =~ /^(\d+)(?:\.\d+)?(?:mm)?$/) {
		push @classic_fields, [ $1 . "mm", 0 ];
	} elsif (defined($info->{'FocalLength'}) && $info->{'FocalLength'} =~ /^(\d+)\/(\d+)$/) {
		push @classic_fields, [ (sprintf "%.1fmm", ($1/$2)), 0 ];
	}

	if (defined($info->{'ExposureTime'}) && $info->{'ExposureTime'} =~ /^(\d+)\/(\d+)$/) {
		my ($a, $b) = ($1, $2);
		my $gcd = gcd($a, $b);
		push @classic_fields, [ $a/$gcd . "/" . $b/$gcd . "s", $shutter_priority ];
	} elsif (defined($info->{'ExposureTime'}) && $info->{'ExposureTime'} =~ /^(\d+)$/) {
		push @classic_fields, [ $1 . "s", $shutter_priority ];
	}

	if (defined($info->{'FNumber'}) && $info->{'FNumber'} =~ /^(\d+)\/(\d+)$/) {
		my $f = $1/$2;
		if ($f >= 10) {
			push @classic_fields, [ (sprintf "f/%.0f", $f), $aperture_priority ];
		} else {
			push @classic_fields, [ (sprintf "f/%.1f", $f), $aperture_priority ];
		}
	} elsif (defined($info->{'FNumber'}) && $info->{'FNumber'} =~ /^(\d+)\.(\d+)$/) {
		my $f = $info->{'FNumber'};
		if ($f >= 10) {
			push @classic_fields, [ (sprintf "f/%.0f", $f), $aperture_priority ];
		} else {
			push @classic_fields, [ (sprintf "f/%.1f", $f), $aperture_priority ];
		}
	}

#	Apache2::ServerUtil->server->log_error(join(':', keys %$info));

	my $iso = undef;
	if (defined($info->{'NikonD1-ISOSetting'})) {
		$iso = $info->{'NikonD1-ISOSetting'};
	} elsif (defined($info->{'ISO'})) {
		$iso = $info->{'ISO'};
	} elsif (defined($info->{'ISOSetting'})) {
		$iso = $info->{'ISOSetting'};
	}
	if (defined($iso) && $iso =~ /(\d+)/) {
		push @classic_fields, [ $1 . " ISO", 0 ];
	}

	if (defined($info->{'ExposureBiasValue'}) && $info->{'ExposureBiasValue'} ne "0") {
		push @classic_fields, [ $info->{'ExposureBiasValue'} . " EV", 0 ];
	} elsif (defined($info->{'ExposureCompensation'}) && $info->{'ExposureCompensation'} != 0) {
		push @classic_fields, [ $info->{'ExposureCompensation'} . " EV", 0 ];
	}

	# Now piece together the rest
	my @parts = ();
	
	if (defined($info->{'DateTimeOriginal'}) &&
	    $info->{'DateTimeOriginal'} =~ /^(\d{4}):(\d\d):(\d\d) (\d\d):(\d\d):(\d\d)$/
	    && $1 >= 1990) {
		push @parts, [ "$1-$2-$3 $4:$5", 0 ];
	}

	if (defined($info->{'Model'})) {
		my $model = $info->{'Model'}; 
		$model =~ s/^\s+//;
		$model =~ s/\s+$//;

		push @parts, [ ' - ', 0 ] if (scalar @parts > 0);
		push @parts, [ $model, 0 ];
	}
	
	# classic fields
	if (scalar @classic_fields > 0) {
		push @parts, [ ' - ', 0 ] if (scalar @parts > 0);

		my $first_elem = 1;
		for my $field (@classic_fields) {
			push @parts, [ ', ', 0 ] if (!$first_elem);
			$first_elem = 0;
			push @parts, $field;
		}
	}

	if (defined($info->{'Flash'})) {
		if ($info->{'Flash'} =~ /did not fire/i ||
		    $info->{'Flash'} =~ /no flash/i ||
		    $info->{'Flash'} =~ /not fired/i ||
		    $info->{'Flash'} =~ /Off/)  {
			push @parts, [ ' - ', 0 ] if (scalar @parts > 0);
			push @parts, [ "No flash", 0 ];
		} elsif ($info->{'Flash'} =~ /fired/i ||
		         $info->{'Flash'} =~ /On/) {
			push @parts, [ ' - ', 0 ] if (scalar @parts > 0);
			push @parts, [ "Flash", 0 ];
		} else {
			push @parts, [ ' - ', 0 ] if (scalar @parts > 0);
			push @parts, [ $info->{'Flash'}, 0 ];
		}
	}

	return if (scalar @parts == 0);

	# Find the required width
	my $th = 0;
	my $tw = 0;

	for my $part (@parts) {
		my $font;
		if ($part->[1]) {
			$font = '/usr/share/fonts/truetype/msttcorefonts/Arial_Bold.ttf';
		} else {
			$font = '/usr/share/fonts/truetype/msttcorefonts/Arial.ttf';
		}

		my (undef, undef, $h, undef, $w) = ($img->QueryFontMetrics(text=>$part->[0], font=>$font, pointsize=>12));

		$tw += $w;
		$th = $h if ($h > $th);
	}

	return if ($tw > $img->Get('columns'));

	my $x = 0;
	my $y = $img->Get('rows') - 24;

	# Hit exact DCT blocks
	$y -= ($y % 8);

	my $points = sprintf "%u,%u %u,%u", $x, $y, ($img->Get('columns') - 1), ($img->Get('rows') - 1);
	my $lpoints = sprintf "%u,%u %u,%u", $x, $y, ($img->Get('columns') - 1), $y;
	$img->Draw(primitive=>'rectangle', stroke=>'white', fill=>'white', points=>$points);
	$img->Draw(primitive=>'line', stroke=>'black', points=>$lpoints);

	# Start writing out the text
	$x = ($img->Get('columns') - $tw) / 2;

	my $room = ($img->Get('rows') - 1 - $y - $th);
	$y = ($img->Get('rows') - 1) - $room/2;
	
	for my $part (@parts) {
		my $font;
		if ($part->[1]) {
			$font = '/usr/share/fonts/truetype/msttcorefonts/Arial_Bold.ttf';
		} else {
			$font = '/usr/share/fonts/truetype/msttcorefonts/Arial.ttf';
		}
		$img->Annotate(text=>$part->[0], font=>$font, pointsize=>12, x=>int($x), y=>int($y));
		$x += ($img->QueryFontMetrics(text=>$part->[0], font=>$font, pointsize=>12))[4];
	}
}

sub gcd {
	my ($a, $b) = @_;
	return $a if ($b == 0);
	return gcd($b, $a % $b);
}

sub add_new_event {
	my ($dbh, $id, $date, $desc, $vhost) = @_;
	my @errors = ();

	if (!defined($id) || $id =~ /^\s*$/ || $id !~ /^([a-zA-Z0-9-]+)$/) {
		push @errors, "Manglende eller ugyldig ID.";
	}
	if (!defined($date) || $date =~ /^\s*$/ || $date =~ /[<>&]/ || length($date) > 100) {
		push @errors, "Manglende eller ugyldig dato.";
	}
	if (!defined($desc) || $desc =~ /^\s*$/ || $desc =~ /[<>&]/ || length($desc) > 100) {
		push @errors, "Manglende eller ugyldig beskrivelse.";
	}
	
	if (scalar @errors > 0) {
		return @errors;
	}
		
	$dbh->do("INSERT INTO events (event,date,name,vhost) VALUES (?,?,?,?)",
		undef, $id, $date, $desc, $vhost)
		or return ("Kunne ikke sette inn ny hendelse" . $dbh->errstr);
	$dbh->do("INSERT INTO last_picture_cache (vhost,event,last_picture) VALUES (?,?,NULL)",
		undef, $vhost, $id)
		or return ("Kunne ikke sette inn ny cache-rad" . $dbh->errstr);

	return ();
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

1;


