package Sesse::pr0n::Common;
use strict;
use warnings;

use Sesse::pr0n::Overload;
use Sesse::pr0n::QscaleProxy;
use Sesse::pr0n::Templates;

use Carp;
use Encode;
use DBI;
use DBD::Pg;
use Image::Magick;
use IO::String;
use POSIX;
use Digest::SHA;
use Digest::HMAC_SHA1;
use MIME::Base64;
use MIME::Types;
use LWP::Simple;
# use Image::Info;
use Image::ExifTool;
use HTML::Entities;
use URI::Escape;
use File::Basename;
use Crypt::Eksblowfish::Bcrypt;

BEGIN {
	use Exporter ();
	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

	use Sesse::pr0n::Config;
	eval {
		require Sesse::pr0n::Config_local;
	};

	$VERSION     = "v3.00-pre";
	@ISA         = qw(Exporter);
	@EXPORT      = qw(&error &dberror);
	%EXPORT_TAGS = qw();
	@EXPORT_OK   = qw(&error &dberror);

	our $dbh = DBI->connect("dbi:Pg:dbname=pr0n;host=" . $Sesse::pr0n::Config::db_host,
		$Sesse::pr0n::Config::db_username, $Sesse::pr0n::Config::db_password)
		or die "Couldn't connect to PostgreSQL database: " . DBI->errstr;
	our $mimetypes = new MIME::Types;
	
	print STDERR "Initializing pr0n $VERSION\n";
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

	my $res = Plack::Response->new($status);
	my $io = IO::String->new;
	
        $r->content_type('text/html; charset=utf-8');

	header($r, $io, $title);
	$io->print("    <p>Error: $err</p>\n");
	footer($r, $io);

	log_error($r, $err);
	log_error($r, "Stack trace follows: " . Carp::longmess());

	$io->setpos(0);
	$res->body($io);
	return $res;
}

sub dberror {
	my ($r,$err) = @_;
	return error($r, "$err (DB error: " . $dbh->errstr . ")");
}

sub header {
	my ($r, $io, $title) = @_;

	$r->content_type("text/html; charset=utf-8");

	# Fetch quote if we're itk-bilder.samfundet.no
	my $quote = "";
	if (Sesse::pr0n::Common::get_server_name($r) eq 'itk-bilder.samfundet.no') {
		$quote = LWP::Simple::get("http://itk.samfundet.no/include/quotes.cli.php");
		$quote = "Error: Could not fetch quotes." if (!defined($quote));
	}
	Sesse::pr0n::Templates::print_template($r, $io, "header", { title => $title, quotes => $quote });
}

sub footer {
	my ($r, $io) = @_;
	Sesse::pr0n::Templates::print_template($r, $io, "footer",
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
	my ($io, $title, $baseurl, $param, $defparam, $accesskey) = @_;
	my $str = "<a href=\"$baseurl" . get_query_string($param, $defparam) . "\"";
	if (defined($accesskey) && length($accesskey) == 1) {
		$str .= " accesskey=\"$accesskey\"";
	}
	$str .= ">$title</a>";
	$io->print($str);
}

sub get_dbh {
	# Check that we are alive
	if (!(defined($dbh) && $dbh->ping)) {
		# Try to reconnect
		print STDERR "Lost contact with PostgreSQL server, trying to reconnect...\n";
		unless ($dbh = DBI->connect("dbi:Pg:dbname=pr0n;host=" . $Sesse::pr0n::Config::db_host,
			$Sesse::pr0n::Config::db_username, $Sesse::pr0n::Config::db_password)) {
			$dbh = undef;
			die "Couldn't connect to PostgreSQL database";
		}
	}

	return $dbh;
}

sub get_disk_location {
	my ($r, $id) = @_;
        my $dir = POSIX::floor($id / 256);
	return $Sesse::pr0n::Config::image_base . "images/$dir/$id.jpg";
}

sub get_cache_location {
	my ($r, $id, $width, $height, $infobox, $dpr) = @_;
        my $dir = POSIX::floor($id / 256);

	if ($infobox) {
		if ($dpr == 1) {
			return $Sesse::pr0n::Config::image_base . "cache/$dir/$id-$width-$height-box.png";
		} else {
			return $Sesse::pr0n::Config::image_base . "cache/$dir/$id-$width-$height-box\@$dpr.png";
		}
	} else {
		return $Sesse::pr0n::Config::image_base . "cache/$dir/$id-$width-$height-nobox.jpg";
	}
}

sub ensure_disk_location_exists {
	my ($r, $id) = @_;
	my $dir = POSIX::floor($id / 256);

	my $img_dir = $Sesse::pr0n::Config::image_base . "/images/$dir/";
	if (! -d $img_dir) {
		log_info($r, "Need to create new image directory $img_dir");
		mkdir($img_dir) or die "Couldn't create new image directory $img_dir";
	}

	my $cache_dir = $Sesse::pr0n::Config::image_base . "/cache/$dir/";
	if (! -d $cache_dir) {
		log_info($r, "Need to create new cache directory $cache_dir");
		mkdir($cache_dir) or die "Couldn't create new image directory $cache_dir";
	}
}

sub get_mipmap_location {
	my ($r, $id, $width, $height) = @_;
        my $dir = POSIX::floor($id / 256);

	return $Sesse::pr0n::Config::image_base . "cache/$dir/$id-mipmap-$width-$height.jpg";
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
		
		# update the last_picture cache as well (this should of course be done
		# via a trigger, but this is less complicated :-) )
		$dbh->do('UPDATE last_picture_cache SET last_picture=GREATEST(last_picture, ?),last_update=CURRENT_TIMESTAMP WHERE (vhost,event)=(SELECT vhost,event FROM images WHERE id=?)',
			undef, $datetime, $id)
			or die "Couldn't update last_picture in SQL: $!";
	}
}

sub check_access {
	my $r = shift;
	
	#return qw(sesse Sesse);

	my $auth = $r->header('authorization');
	if (!defined($auth)) {
		return undef;
	} 
	if ($auth =~ /^Basic ([a-zA-Z0-9+\/]+=*)$/) {
		return check_basic_auth($r, $1);
	}	
	return undef;
}

sub generate_401 {
	my ($r) = @_;
	my $res = Plack::Response->new(401);
	$res->content_type('text/plain; charset=utf-8');
	$res->status(401);
	$res->header('WWW-Authenticate' => 'Basic realm="pr0n.sesse.net"');

	$res->body("Need authorization\n");
	return $res;
}

sub check_basic_auth {
	my ($r, $auth) = @_;	

	my ($raw_user, $pass) = split /:/, MIME::Base64::decode_base64($auth);
	my ($user, $takenby) = extract_takenby($raw_user);

	my $ref = $dbh->selectrow_hashref('SELECT sha1password,cryptpassword FROM users WHERE username=? AND vhost=?',
		undef, $user, Sesse::pr0n::Common::get_server_name($r));
	my ($sha1_matches, $bcrypt_matches) = (0, 0);
	if (defined($ref) && defined($ref->{'sha1password'})) {
		$sha1_matches = (Digest::SHA::sha1_base64($pass) eq $ref->{'sha1password'});
	}
	if (defined($ref) && defined($ref->{'cryptpassword'})) {
		$bcrypt_matches = (Crypt::Eksblowfish::Bcrypt::bcrypt($pass, $ref->{'cryptpassword'}) eq $ref->{'cryptpassword'});
	}

	if (!defined($ref) || (!$sha1_matches && !$bcrypt_matches)) {
		$r->content_type('text/plain; charset=utf-8');
		log_warn($r, "Authentication failed for $user/$takenby");
		return undef;
	}
	log_info($r, "Authentication succeeded for $user/$takenby");

	# Make sure we can use bcrypt authentication in the future with this password.
	# Also remove old-style SHA1 password when we migrate.
	if (!$bcrypt_matches) {
		my $salt = get_pseudorandom_bytes(16);  # Doesn't need to be cryptographically secur.
		my $hash = "\$2a\$07\$" . Crypt::Eksblowfish::Bcrypt::en_base64($salt);
		my $cryptpassword = Crypt::Eksblowfish::Bcrypt::bcrypt($pass, $hash);
		$dbh->do('UPDATE users SET sha1password=NULL,cryptpassword=? WHERE username=? AND vhost=?',
			undef, $cryptpassword, $user, Sesse::pr0n::Common::get_server_name($r))
			or die "Couldn't update: " . $dbh->errstr;
		log_info($r, "Updated bcrypt hash for $user");
	}

	return ($user, $takenby);
}

sub get_pseudorandom_bytes {
	my $num_left = shift;
	my $bytes = "";
	open my $randfh, "<", "/dev/urandom"
		or die "/dev/urandom: $!";
	binmode $randfh;
	while ($num_left > 0) {
		my $tmp;
		if (sysread($randfh, $tmp, $num_left) == -1) {
			die "sysread(/dev/urandom): $!";
		}
		$bytes .= $tmp;
		$num_left -= length($bytes);
	}
	close $randfh;
	return $bytes;
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
# the smallest mipmap larger than the largest of them, as well as the original image
# dimensions.
sub make_mipmap {
	my ($r, $filename, $id, $dbwidth, $dbheight, @res) = @_;
	my ($img, $mmimg, $width, $height);
	
	my $physical_fname = get_disk_location($r, $id);

	# If we don't know the size, we'll need to read it in anyway
	if (!defined($dbwidth) || !defined($dbheight)) {
		$img = read_original_image($r, $filename, $id, $dbwidth, $dbheight);
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
					$img = Sesse::pr0n::QscaleProxy->new;
					$img->Read($last_good_mmlocation);
				} else {
					$img = read_original_image($r, $filename, $id, $dbwidth, $dbheight);
				}
			}
			my $cimg;
			if ($last) {
				$cimg = $img;
			} else {
				$cimg = $img->Clone();
			}
			log_info($r, "Making mipmap for $id: " . $mmres->[0] . " x " . $mmres->[1]);
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
			$img = Sesse::pr0n::QscaleProxy->new;
			my $err = $img->Read($mmlocation);
		}
	}

	if (!defined($img)) {
		$img = read_original_image($r, $filename, $id, $dbwidth, $dbheight);
		$width = $img->Get('columns');
		$height = $img->Get('rows');
	}
	return ($img, $width, $height);
}

sub read_original_image {
	my ($r, $filename, $id, $dbwidth, $dbheight) = @_;

	my $physical_fname = get_disk_location($r, $id);

	# Read in the original image
	my $magick;
	if ($filename =~ /\.jpeg$/i || $filename =~ /\.jpg$/i) {
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
		log_warn($r, "$physical_fname: $err");
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

	return $img;
}

sub ensure_cached {
	my ($r, $filename, $id, $dbwidth, $dbheight, $infobox, $dpr, $xres, $yres, @otherres) = @_;

	my ($new_dbwidth, $new_dbheight);

	my $fname = get_disk_location($r, $id);
	if (!$infobox) {
		unless (defined($xres) && (!defined($dbwidth) || !defined($dbheight) || $xres < $dbwidth || $yres < $dbheight || $xres == -1)) {
			return ($fname, undef);
		}
	}

	my $cachename = get_cache_location($r, $id, $xres, $yres, $infobox, $dpr);
	my $err;
	if (! -r $cachename or (-M $cachename > -M $fname)) {
		# If we are in overload mode (aka Slashdot mode), refuse to generate
		# new thumbnails.
		if (Sesse::pr0n::Overload::is_in_overload($r)) {
			log_warn($r, "In overload mode, not scaling $id to $xres x $yres");
			error($r, 'System is in overload mode, not doing any scaling');
		}

		# If we're being asked for the box, make a new image with it.
		# We don't care about @otherres since each of these images are
		# already pretty cheap to generate, but we need the exact width so we can make
		# one in the right size.
		if ($infobox) {
			my ($img, $width, $height);

			# This is slow, but should fortunately almost never happen, so don't bother
			# special-casing it.
			if (!defined($dbwidth) || !defined($dbheight)) {
				$img = read_original_image($r, $filename, $id, $dbwidth, $dbheight, 0);
				$new_dbwidth = $width = $img->Get('columns');
				$new_dbheight = $height = $img->Get('rows');
				@$img = ();
			} else {
				$img = Image::Magick->new;
				$width = $dbwidth;
				$height = $dbheight;
			}
			
			if (defined($xres) && defined($yres)) {
				($width, $height) = scale_aspect($width, $height, $xres, $yres);
			}
			$height = 24 * $dpr;
			$img->Set(size=>($width . "x" . $height));
			$img->Read('xc:white');
				
			my $info = Image::ExifTool::ImageInfo($fname);
			if (make_infobox($img, $info, $r, $dpr)) {
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
			log_info($r, "New infobox cache: $width x $height for $id.jpg");
			
			return ($cachename, 'image/png');
		}

		my $img;
		($img, $new_dbwidth, $new_dbheight) = make_mipmap($r, $filename, $id, $dbwidth, $dbheight, $xres, $yres, @otherres);

		while (defined($xres) && defined($yres)) {
			my ($nxres, $nyres) = (shift @otherres, shift @otherres);
			my $cachename = get_cache_location($r, $id, $xres, $yres, $infobox, $dpr);
			
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

			my $filter = 'Lanczos';
			my $quality = 87;
			my $sf = "1x1";

			if ($xres != -1) {
				$cimg->Resize(width=>$nwidth, height=>$nheight, filter=>$filter, 'sampling-factor'=>$sf);
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

			log_info($r, "New cache: $nwidth x $nheight for $id.jpg");
		}
		
		undef $img;
		if ($err) {
			log_warn($r, "$fname: $err");
			$err =~ /(\d+)/;
			if ($1 >= 400) {
				#@$magick = ();
				error($r, "$fname: $err");
			}
		}
	}
	
	# Update the SQL database if it doesn't contain the required info
	if (!defined($dbwidth) && defined($new_dbwidth)) {
		log_info($r, "Updating width/height for $id: $new_dbwidth x $new_dbheight");
		update_image_info($r, $id, $new_dbwidth, $new_dbheight);
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
	my ($img, $info, $r, $dpr) = @_;

	# The infobox is of the form
	# "Time - date - focal length, shutter time, aperture, sensitivity, exposure bias - flash",
	# possibly with some parts omitted -- the middle part is known as the "classic
	# fields"; note the comma separation. Every field has an associated "bold flag"
	# in the second part.
	
	my $manual_shutter = (defined($info->{'ExposureProgram'}) &&
		$info->{'ExposureProgram'} =~ /shutter\b.*\bpriority/i);
	my $manual_aperture = (defined($info->{'ExposureProgram'}) &&
		$info->{'ExposureProgram'} =~ /aperture\b.*\bpriority/i);
	if ($info->{'ExposureProgram'} =~ /manual/i) {
		$manual_shutter = 1;
		$manual_aperture = 1;
	}

	my @classic_fields = ();
	if (defined($info->{'FocalLength'}) && $info->{'FocalLength'} =~ /^(\d+)(?:\.\d+)?\s*(?:mm)?$/) {
		push @classic_fields, [ $1 . "mm", 0 ];
	} elsif (defined($info->{'FocalLength'}) && $info->{'FocalLength'} =~ /^(\d+)\/(\d+)$/) {
		push @classic_fields, [ (sprintf "%.1fmm", ($1/$2)), 0 ];
	}

	if (defined($info->{'ExposureTime'}) && $info->{'ExposureTime'} =~ /^(\d+)\/(\d+)$/) {
		my ($a, $b) = ($1, $2);
		my $gcd = gcd($a, $b);
		push @classic_fields, [ $a/$gcd . "/" . $b/$gcd . "s", $manual_shutter ];
	} elsif (defined($info->{'ExposureTime'}) && $info->{'ExposureTime'} =~ /^(\d+(?:\.\d+)?)$/) {
		push @classic_fields, [ $1 . "s", $manual_shutter ];
	}

	if (defined($info->{'FNumber'}) && $info->{'FNumber'} =~ /^(\d+)\/(\d+)$/) {
		my $f = $1/$2;
		if ($f >= 10) {
			push @classic_fields, [ (sprintf "f/%.0f", $f), $manual_aperture ];
		} else {
			push @classic_fields, [ (sprintf "f/%.1f", $f), $manual_aperture ];
		}
	} elsif (defined($info->{'FNumber'}) && $info->{'FNumber'} =~ /^(\d+)\.(\d+)$/) {
		my $f = $info->{'FNumber'};
		if ($f >= 10) {
			push @classic_fields, [ (sprintf "f/%.0f", $f), $manual_aperture ];
		} else {
			push @classic_fields, [ (sprintf "f/%.1f", $f), $manual_aperture ];
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
	} elsif (defined($info->{'ExposureCompensation'}) && $info->{'ExposureCompensation'} ne "0") {
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

		my (undef, undef, $h, undef, $w) = ($img->QueryFontMetrics(text=>$part->[0], font=>$font, pointsize=>12*$dpr));

		$tw += $w;
		$th = $h if ($h > $th);
	}

	return 0 if ($tw > $img->Get('columns'));

	my $x = 0;
	my $y = $img->Get('rows') - 24*$dpr;

	# Hit exact DCT blocks
	$y -= ($y % 8);

	my $points = sprintf "%u,%u %u,%u", $x, $y, ($img->Get('columns') - 1), ($img->Get('rows') - 1);
	my $lpoints = sprintf "%u,%u %u,%u", $x, $y, ($img->Get('columns') - 1), $y;
	$img->Draw(primitive=>'rectangle', stroke=>'white', fill=>'white', points=>$points);
	$img->Draw(primitive=>'line', stroke=>'black', strokewidth=>$dpr, points=>$lpoints);

	# Start writing out the text
	$x = ($img->Get('columns') - $tw) / 2;

	my $room = ($img->Get('rows') - $dpr - $y - $th);
	$y = ($img->Get('rows') - $dpr) - $room/2;
	
	for my $part (@parts) {
		my $font;
		if ($part->[1]) {
			$font = '/usr/share/fonts/truetype/msttcorefonts/Arial_Bold.ttf';
		} else {
			$font = '/usr/share/fonts/truetype/msttcorefonts/Arial.ttf';
		}
		$img->Annotate(text=>$part->[0], font=>$font, pointsize=>12*$dpr, x=>int($x), y=>int($y));
		$x += ($img->QueryFontMetrics(text=>$part->[0], font=>$font, pointsize=>12*$dpr))[4];
	}

	return 1;
}

sub gcd {
	my ($a, $b) = @_;
	return $a if ($b == 0);
	return gcd($b, $a % $b);
}

sub add_new_event {
	my ($r, $res, $dbh, $id, $date, $desc) = @_;
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
		
	my $vhost = Sesse::pr0n::Common::get_server_name($r);
	$dbh->do("INSERT INTO events (event,date,name,vhost) VALUES (?,?,?,?)",
		undef, $id, $date, $desc, $vhost)
		or return ("Kunne ikke sette inn ny hendelse" . $dbh->errstr);
	$dbh->do("INSERT INTO last_picture_cache (vhost,event,last_picture) VALUES (?,?,NULL)",
		undef, $vhost, $id)
		or return ("Kunne ikke sette inn ny cache-rad" . $dbh->errstr);
	purge_cache($r, $res, "/");

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
	my ($r, $res, @elements) = @_;
	return if (scalar @elements == 0);

	my @pe = ();
	for my $elem (@elements) {
		log_info($r, "Purging $elem");
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
	$res->header('X-Pr0n-Purge' => $regex);
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

	my $base = $Sesse::pr0n::Config::image_base . "cache/$dir";
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
			log_warn($r, "Couldn't find a purging URL for $fname");
		}
	}

	return @ret;
}

sub set_last_modified {
	my ($res, $mtime) = @_;

	my $str = POSIX::strftime("%a, %d %b %Y %H:%M:%S GMT", gmtime($mtime));
	$res->headers({ 'Last-Modified' => $str });
}

sub get_server_name {
	my $r = shift;
	my $host = $r->env->{'HTTP_HOST'};
	$host =~ s/:.*//;
	return $host;
}

sub log_info {
	my ($r, $msg) = @_;
	if (defined($r->logger)) {
		$r->logger->({ level => 'info', message => $msg });
	} else {
		print STDERR "[INFO] $msg\n";
	}
}

sub log_warn {
	my ($r, $msg) = @_;
	if (defined($r->logger)) {
		$r->logger->({ level => 'warn', message => $msg });
	} else {
		print STDERR "[WARN] $msg\n";
	}
}

sub log_error {
	my ($r, $msg) = @_;
	if (defined($r->logger)) {
		$r->logger->({ level => 'error', message => $msg });
	} else {
		print STDERR "[ERROR] $msg\n";
	}
}

1;


