package Sesse::pr0n::Common;
use strict;
use warnings;

use Sesse::pr0n::Overload;
use Sesse::pr0n::QscaleProxy;
use Sesse::pr0n::Templates;

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
use Digest::MD5;
use Digest::SHA1;
use Digest::HMAC_SHA1;
use MIME::Base64;
use MIME::Types;
use LWP::Simple;
# use Image::Info;
use Image::ExifTool;
use HTML::Entities;
use URI::Escape;
use File::Basename;

BEGIN {
	use Exporter ();
	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

	use Sesse::pr0n::Config;
	eval {
		require Sesse::pr0n::Config_local;
	};

	$VERSION     = "v2.70";
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

	if ($infobox eq 'both') {
		return get_base($r) . "cache/$dir/$id-$width-$height.jpg";
	} elsif ($infobox eq 'nobox') {
		return get_base($r) . "cache/$dir/$id-$width-$height-nobox.jpg";
	} else {
		return get_base($r) . "cache/$dir/$id-$width-$height-box.png";
	}
}

sub get_mipmap_location {
	my ($r, $id, $width, $height) = @_;
        my $dir = POSIX::floor($id / 256);

	return get_base($r) . "cache/$dir/$id-mipmap-$width-$height.jpg";
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
	
	#return qw(sesse Sesse);

	my $auth = $r->headers_in->{'authorization'};
	if (!defined($auth)) {
		output_401($r);
		return undef;
	} 
	if ($auth =~ /^Basic ([a-zA-Z0-9+\/]+=*)$/) {
		return check_basic_auth($r, $1);
	}	
	if ($auth =~ /^Digest (.*)$/) {
		return check_digest_auth($r, $1);
	}
	output_401($r);
	return undef;
}

sub output_401 {
	my ($r, %options) = @_;
	$r->content_type('text/plain; charset=utf-8');
	$r->status(401);
	$r->headers_out->{'www-authenticate'} = 'Basic realm="pr0n.sesse.net"';

	if ($options{'DigestAuth'} // 1) {
		# We make our nonce similar to the scheme of RFC2069 section 2.1.1,
		# with some changes: We don't care about client IP (these have a nasty
		# tendency to change from request to request when load-balancing
		# proxies etc. are being used), and we use HMAC instead of simple
		# hashing simply because that's a better signing method.
		#
		# NOTE: For some weird reason, Digest::HMAC_SHA1 doesn't like taking
		# the output from time directly (it gives a different response), so we
		# forcefully stringify the argument.
		my $ts = time;
		my $nonce = Digest::HMAC_SHA1->hmac_sha1_hex($ts . "", $Sesse::pr0n::Config::db_password);
		my $stale_nonce_text = "";
		$stale_nonce_text = ", stale=\"true\"" if ($options{'StaleNonce'} // 0);

		$r->headers_out->{'www-authenticate'} =
			"Digest realm=\"pr0n.sesse.net\", " .
			"nonce=\"$nonce\", " .
			"opaque=\"$ts\", " .
			"qop=\"auth\"" . $stale_nonce_text;  # FIXME: support auth-int
	}

	$r->print("Need authorization\n");
}

sub check_basic_auth {
	my ($r, $auth) = @_;	

	my ($raw_user, $pass) = split /:/, MIME::Base64::decode_base64($auth);
	my ($user, $takenby) = extract_takenby($raw_user);
	
	my $ref = $dbh->selectrow_hashref('SELECT sha1password,digest_ha1_hex FROM users WHERE username=? AND vhost=?',
		undef, $user, $r->get_server_name);
	if (!defined($ref) || $ref->{'sha1password'} ne Digest::SHA1::sha1_base64($pass)) {
		$r->content_type('text/plain; charset=utf-8');
		$r->log->warn("Authentication failed for $user/$takenby");
		output_401($r);
		return undef;
	}
	$r->log->info("Authentication succeeded for $user/$takenby");

	# Make sure we can use Digest authentication in the future with this password.
	my $ha1 = Digest::MD5::md5_hex($user . ':pr0n.sesse.net:' . $pass);
	if (!defined($ref->{'digest_ha1_hex'}) || $ref->{'digest_ha1_hex'} ne $ha1) {
		$dbh->do('UPDATE users SET digest_ha1_hex=? WHERE username=? AND vhost=?',
			undef, $ha1, $user, $r->get_server_name)
			or die "Couldn't update: " . $dbh->errstr;
		$r->log->info("Updated Digest auth hash for for $user");
	}

	return ($user, $takenby);
}

sub check_digest_auth {
	my ($r, $auth) = @_;	

	# We're a bit more liberal than RFC2069 in the parsing here, allowing
	# quoted strings everywhere.
	my %auth = ();
	while ($auth =~ s/^ ([a-zA-Z]+)                # key
	                 =                 
                         (                            
                           [^",]*                     # either something that doesn't contain comma or quotes
                         |
                           " ( [^"\\] | \\ . ) * "    # or a full quoted string
                         )
                         (?: (?: , \s* ) + | $ )      # delimiter(s), or end of string
                        //x) {
		my ($key, $value) = ($1, $2);
		if ($value =~ /^"(.*)"$/) {
			$value = $1;
			$value =~ s/\\(.)/$1/g;
		}
		$auth{$key} = $value;
	}
	unless (exists($auth{'username'}) &&
	        exists($auth{'uri'}) &&
	        exists($auth{'nonce'}) &&
	        exists($auth{'opaque'}) &&
	        exists($auth{'response'})) {
		output_401($r);
		return undef;
	}
	if ($r->uri ne $auth{'uri'}) {	
		output_401($r);
		return undef;
	}
	
	# Verify that the opaque data does indeed look like a timestamp, and that the nonce
	# is indeed a signed version of it.
	if ($auth{'opaque'} !~ /^\d+$/) {
		output_401($r);
		return undef;
	}
	my $compare_nonce = Digest::HMAC_SHA1->hmac_sha1_hex($auth{'opaque'}, $Sesse::pr0n::Config::db_password);
	if ($auth{'nonce'} ne $compare_nonce) {
		output_401($r);
		return undef;
	}

	# Now look up the user's HA1 from the database, and calculate HA2.	
	my ($user, $takenby) = extract_takenby($auth{'username'});
	my $ref = $dbh->selectrow_hashref('SELECT digest_ha1_hex FROM users WHERE username=? AND vhost=?',
		undef, $user, $r->get_server_name);
	if (!defined($ref)) {
		output_401($r);
		return undef;
	}
	if (!defined($ref->{'digest_ha1_hex'}) || $ref->{'digest_ha1_hex'} !~ /^[0-9a-f]{32}$/) {
		# A user that exists but has empty HA1 is a user that's not
		# ready for digest auth, so we hack it and resend 401,
		# only this time without digest auth.
		output_401($r, DigestAuth => 0);
		return undef;
	}
	my $ha1 = $ref->{'digest_ha1_hex'};
	my $ha2 = Digest::MD5::md5_hex($r->method . ':' . $auth{'uri'});
	my $response;
	if (exists($auth{'qop'}) && $auth{'qop'} eq 'auth') {
		unless (exists($auth{'nc'}) && exists($auth{'cnonce'})) {
			output_401($r);
			return undef;
		}	

		$response = $ha1;
		$response .= ':' . $auth{'nonce'};
		$response .= ':' . $auth{'nc'};
		$response .= ':' . $auth{'cnonce'};
		$response .= ':' . $auth{'qop'};
		$response .= ':' . $ha2;
	} else {
		$response = $ha1;
		$response .= ':' . $auth{'nonce'};
		$response .= ':' . $ha2;
	}
	if ($auth{'response'} ne Digest::MD5::md5_hex($response)) {	
		output_401($r);
		return undef;
	}

	# OK, everything is good, and there's only one thing we need to check: That the nonce
	# isn't too old. If it is, but everything else is ok, we tell the browser that and it
	# will re-encrypt with the new nonce.
	my $timediff = time - $auth{'opaque'};
	if ($timediff < 0 || $timediff > 300) {
		output_401($r, StaleNonce => 1);
		return undef;
	}

	return ($user, $takenby);
}

sub extract_takenby {
	my ($user) = shift;

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

# Takes in an image ID and a set of resolutions, and returns (generates if needed)
# the smallest mipmap larger than the largest of them.
sub make_mipmap {
	my ($r, $filename, $id, $dbwidth, $dbheight, $can_use_qscale, @res) = @_;
	my ($img, $mmimg, $width, $height);
	
	my $physical_fname = get_disk_location($r, $id);

	# If we don't know the size, we'll need to read it in anyway
	if (!defined($dbwidth) || !defined($dbheight)) {
		$img = read_original_image($r, $filename, $id, $dbwidth, $dbheight, $can_use_qscale);
		$width = $img->Get('columns');
		$height = $img->Get('rows');
	} else {
		$width = $dbwidth;
		$height = $dbheight;
	}

	# Generate the list of mipmaps
	my @mmlist = ();
	
	my $mmwidth = $width;
	my $mmheight = $height;

	while ($mmwidth > 1 || $mmheight > 1) {
		my $new_mmwidth = POSIX::floor($mmwidth / 2);		
		my $new_mmheight = POSIX::floor($mmheight / 2);		

		$new_mmwidth = 1 if ($new_mmwidth < 1);
		$new_mmheight = 1 if ($new_mmheight < 1);

		my $large_enough = 1;
		for my $i (0..($#res/2)) {
			my ($xres, $yres) = ($res[$i*2], $res[$i*2+1]);
			if ($xres == -1 || $xres > $new_mmwidth || $yres > $new_mmheight) {
				$large_enough = 0;
				last;
			}
		}
				
		last if (!$large_enough);

		$mmwidth = $new_mmwidth;
		$mmheight = $new_mmheight;

		push @mmlist, [ $mmwidth, $mmheight ];
	}
		
	# Ensure that all of them are OK
	my $last_good_mmlocation;
	for my $i (0..$#mmlist) {
		my $last = ($i == $#mmlist);
		my $mmres = $mmlist[$i];

		my $mmlocation = get_mipmap_location($r, $id, $mmres->[0], $mmres->[1]);
		if (! -r $mmlocation or (-M $mmlocation > -M $physical_fname)) {
			if (!defined($img)) {
				if (defined($last_good_mmlocation)) {
					if ($can_use_qscale) {
						$img = Sesse::pr0n::QscaleProxy->new;
					} else {
						$img = Image::Magick->new;
					}
					$img->Read($last_good_mmlocation);
				} else {
					$img = read_original_image($r, $filename, $id, $dbwidth, $dbheight, $can_use_qscale);
				}
			}
			my $cimg;
			if ($last) {
				$cimg = $img;
			} else {
				$cimg = $img->Clone();
			}
			$r->log->info("Making mipmap for $id: " . $mmres->[0] . " x " . $mmres->[1]);
			$cimg->Resize(width=>$mmres->[0], height=>$mmres->[1], filter=>'Lanczos', 'sampling-factor'=>'1x1');
			$cimg->Strip();
			my $err = $cimg->write(
				filename => $mmlocation,
				quality => 95,
				'sampling-factor' => '1x1'
			);
			$img = $cimg;
		} else {
			$last_good_mmlocation = $mmlocation;
		}
		if ($last && !defined($img)) {
			# OK, read in the smallest one
			if ($can_use_qscale) {
				$img = Sesse::pr0n::QscaleProxy->new;
			} else {
				$img = Image::Magick->new;
			}
			my $err = $img->Read($mmlocation);
		}
	}

	if (!defined($img)) {
		$img = read_original_image($r, $filename, $id, $dbwidth, $dbheight, $can_use_qscale);
	}
	return $img;
}

sub read_original_image {
	my ($r, $filename, $id, $dbwidth, $dbheight, $can_use_qscale) = @_;

	my $physical_fname = get_disk_location($r, $id);

	# Read in the original image
	my $magick;
	if ($can_use_qscale && ($filename =~ /\.jpeg$/i || $filename =~ /\.jpg$/i)) {
		$magick = Sesse::pr0n::QscaleProxy->new;
	} else {
		$magick = Image::Magick->new;
	}
	my $err;

	# ImageMagick can handle NEF files, but it does it by calling dcraw as a delegate.
	# The delegate support is rather broken and causes very odd stuff to happen when
	# more than one thread does this at the same time. Thus, we simply do it ourselves.
	if ($filename =~ /\.(nef|cr2)$/i) {
		# this would suffice if ImageMagick gets to fix their handling
		# $physical_fname = "NEF:$physical_fname";
		
		open DCRAW, "-|", "dcraw", "-w", "-c", $physical_fname
			or error("dcraw: $!");
		$err = $magick->Read(file => \*DCRAW);
		close(DCRAW);
	} else {
		# We always want YCbCr JPEGs. Setting this explicitly here instead of using
		# RGB is slightly faster (no colorspace conversion needed) and works equally
		# well for our uses, as long as we don't need to draw an information box,
		# which trickles several ImageMagick bugs related to colorspace handling.
		# (Ideally we'd be able to keep the image subsampled and
		# planar, but that would probably be difficult for ImageMagick to expose.)
		#if (!$infobox) {
		#	$magick->Set(colorspace=>'YCbCr');
		#}
		$err = $magick->Read($physical_fname);
	}
	
	if ($err) {
		$r->log->warn("$physical_fname: $err");
		$err =~ /(\d+)/;
		if ($1 >= 400) {
			undef $magick;
			error($r, "$physical_fname: $err");
		}
	}

	# If we use ->[0] unconditionally, text rendering (!) seems to crash
	my $img;
	if (ref($magick) !~ /Image::Magick/) {
		$img = $magick;
	} else {
		$img = (scalar @$magick > 1) ? $magick->[0] : $magick;
	}

	my $width = $img->Get('columns');
	my $height = $img->Get('rows');

	# Update the SQL database if it doesn't contain the required info
	if (!defined($dbwidth) || !defined($dbheight)) {
		$r->log->info("Updating width/height for $id: $width x $height");
		update_image_info($r, $id, $width, $height);
	}

	return $img;
}

sub ensure_cached {
	my ($r, $filename, $id, $dbwidth, $dbheight, $infobox, $xres, $yres, @otherres) = @_;

	my $fname = get_disk_location($r, $id);
	if ($infobox ne 'box') {
		unless (defined($xres) && (!defined($dbwidth) || !defined($dbheight) || $xres < $dbheight || $yres < $dbwidth || $xres == -1)) {
			return ($fname, undef);
		}
	}

	my $cachename = get_cache_location($r, $id, $xres, $yres, $infobox);
	my $err;
	if (! -r $cachename or (-M $cachename > -M $fname)) {
		# If we are in overload mode (aka Slashdot mode), refuse to generate
		# new thumbnails.
		if (Sesse::pr0n::Overload::is_in_overload($r)) {
			$r->log->warn("In overload mode, not scaling $id to $xres x $yres");
			error($r, 'System is in overload mode, not doing any scaling');
		}

		# If we're being asked for just the box, make a new image with just the box.
		# We don't care about @otherres since each of these images are
		# already pretty cheap to generate, but we need the exact width so we can make
		# one in the right size.
		if ($infobox eq 'box') {
			my ($img, $width, $height);

			# This is slow, but should fortunately almost never happen, so don't bother
			# special-casing it.
			if (!defined($dbwidth) || !defined($dbheight)) {
				$img = read_original_image($r, $filename, $id, $dbwidth, $dbheight, 0);
				$width = $img->Get('columns');
				$height = $img->Get('rows');
				@$img = ();
			} else {
				$img = Image::Magick->new;
				$width = $dbwidth;
				$height = $dbheight;
			}
			
			if (defined($xres) && defined($yres)) {
				($width, $height) = scale_aspect($width, $height, $xres, $yres);
			}
			$height = 24;
			$img->Set(size=>($width . "x" . $height));
			$img->Read('xc:white');
				
			my $info = Image::ExifTool::ImageInfo($fname);
			if (make_infobox($img, $info, $r)) {
				$img->Quantize(colors=>16, dither=>'False');

				# Since the image is grayscale, ImageMagick overrides us and writes this
				# as grayscale anyway, but at least we get rid of the alpha channel this
				# way.
				$img->Set(type=>'Palette');
			} else {
				# Not enough room for the text, make a tiny dummy transparent infobox
				@$img = ();
				$img->Set(size=>"1x1");
				$img->Read('null:');

				$width = 1;
				$height = 1;
			}
				
			$err = $img->write(filename => $cachename, quality => 90, depth => 8);
			$r->log->info("New infobox cache: $width x $height for $id.jpg");
			
			return ($cachename, 'image/png');
		}

		my $can_use_qscale = 0;
		if ($infobox eq 'nobox') {
			$can_use_qscale = 1;
		}

		my $img = make_mipmap($r, $filename, $id, $dbwidth, $dbheight, $can_use_qscale, $xres, $yres, @otherres);

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
		
			my $width = $img->Get('columns');
			my $height = $img->Get('rows');
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
				$cimg->Resize(width=>$nwidth, height=>$nheight, filter=>$filter, 'sampling-factor'=>$sf);
			}

			if (($nwidth >= 800 || $nheight >= 600 || $xres == -1) && $infobox ne 'nobox') {
				my $info = Image::ExifTool::ImageInfo($fname);
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
		
		undef $img;
		if ($err) {
			$r->log->warn("$fname: $err");
			$err =~ /(\d+)/;
			if ($1 >= 400) {
				#@$magick = ();
				error($r, "$fname: $err");
			}
		}
	}
	return ($cachename, 'image/jpeg');
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
	if (defined($info->{'FocalLength'}) && $info->{'FocalLength'} =~ /^(\d+)(?:\.\d+)?\s*(?:mm)?$/) {
		push @classic_fields, [ $1 . "mm", 0 ];
	} elsif (defined($info->{'FocalLength'}) && $info->{'FocalLength'} =~ /^(\d+)\/(\d+)$/) {
		push @classic_fields, [ (sprintf "%.1fmm", ($1/$2)), 0 ];
	}

	if (defined($info->{'ExposureTime'}) && $info->{'ExposureTime'} =~ /^(\d+)\/(\d+)$/) {
		my ($a, $b) = ($1, $2);
		my $gcd = gcd($a, $b);
		push @classic_fields, [ $a/$gcd . "/" . $b/$gcd . "s", $shutter_priority ];
	} elsif (defined($info->{'ExposureTime'}) && $info->{'ExposureTime'} =~ /^(\d+(?:\.\d+))$/) {
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

	return 0 if (scalar @parts == 0);

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

	return 0 if ($tw > $img->Get('columns'));

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

	return 1;
}

sub gcd {
	my ($a, $b) = @_;
	return $a if ($b == 0);
	return gcd($b, $a % $b);
}

sub add_new_event {
	my ($r, $dbh, $id, $date, $desc) = @_;
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
		
	my $vhost = $r->get_server_name;
	$dbh->do("INSERT INTO events (event,date,name,vhost) VALUES (?,?,?,?)",
		undef, $id, $date, $desc, $vhost)
		or return ("Kunne ikke sette inn ny hendelse" . $dbh->errstr);
	$dbh->do("INSERT INTO last_picture_cache (vhost,event,last_picture) VALUES (?,?,NULL)",
		undef, $vhost, $id)
		or return ("Kunne ikke sette inn ny cache-rad" . $dbh->errstr);
	purge_cache($r, "/");

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

# Depending on your front-end cache, you might want to get creative somehow here.
# This example assumes you have a front-end cache and it can translate an X-Pr0n-Purge
# regex tacked onto a request into something useful. The elements given in
# should not be regexes, though, as e.g. Squid will not be able to handle that.
sub purge_cache {
	my ($r, @elements) = @_;
	return if (scalar @elements == 0);

	my @pe = ();
	for my $elem (@elements) {
		$r->log->info("Purging $elem");
		(my $e = $elem) =~ s/[.+*|()]/\\$&/g;
		push @pe, $e;
	}

	my $regex = "^";
	if (scalar @pe == 1) {
		$regex .= $pe[0];
	} else {
		$regex .= "(" . join('|', @pe) . ")";
	}
	$regex .= "(\\?.*)?\$";
	$r->headers_out->{'X-Pr0n-Purge'} = $regex;

	$r->log->info($r->headers_out->{'X-Pr0n-Purge'});
}
				
# Find a list of all cache URLs for a given image, given what we have on disk.
sub get_all_cache_urls {
	my ($r, $dbh, $id) = @_;
        my $dir = POSIX::floor($id / 256);
	my @ret = ();

	my $q = $dbh->prepare('SELECT event, filename FROM images WHERE id=?')
		or die "Couldn't prepare: " . $dbh->errstr;
	$q->execute($id)
		or die "Couldn't find event and filename: " . $dbh->errstr;
	my $ref = $q->fetchrow_hashref;	
	my $event = $ref->{'event'};
	my $filename = $ref->{'filename'};
	$q->finish;

	my $base = get_base($r) . "cache/$dir";
	for my $file (<$base/$id-*>) {
		my $fname = File::Basename::basename($file);
		if ($fname =~ /^$id-mipmap-.*\.jpg$/) {
			# Mipmaps don't have an URL, ignore
		} elsif ($fname =~ /^$id--1--1\.jpg$/) {
			push @ret, "/$event/$filename";
		} elsif ($fname =~ /^$id-(\d+)-(\d+)\.jpg$/) {
			push @ret, "/$event/$1x$2/$filename";
		} elsif ($fname =~ /^$id-(\d+)-(\d+)-nobox\.jpg$/) {
			push @ret, "/$event/$1x$2/nobox/$filename";
		} elsif ($fname =~ /^$id--1--1-box\.png$/) {
			push @ret, "/$event/box/$filename";
		} elsif ($fname =~ /^$id-(\d+)-(\d+)-box\.png$/) {
			push @ret, "/$event/$1x$2/box/$filename";
		} else {
			$r->log->warn("Couldn't find a purging URL for $fname");
		}
	}

	return @ret;
}

1;


