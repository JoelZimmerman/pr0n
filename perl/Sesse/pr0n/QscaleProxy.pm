# An object that looks a bit like an Image::Magick object, but has a lot fewer
# methods, and can use qscale behind-the-scenes instead if possible.

package Sesse::pr0n::QscaleProxy;
use strict;
use warnings;

use Image::Magick;

our $has_qscale;

BEGIN {
	$has_qscale = 0;
	eval {
		require qscale;
		$has_qscale = 1;
	};
	if ($@) {
		print STDERR "Could not load the qscale module ($@); continuing with ImageMagick only.\n";
	}
}

sub new {
	my $ref = {};

	if (!$has_qscale) {
		$ref->{'magick'} = Image::Magick->new;
	}

	bless $ref;
	return $ref;
}

sub DESTROY {
	my ($self) = @_;

	if (exists($self->{'qscale'})) {
		qscale::qscale_destroy($self->{'qscale'});
		delete $self->{'qscale'};
	}
}

sub Clone {
	my ($self) = @_;

	if (exists($self->{'magick'})) {
		return $self->{'magick'}->Clone();
	}

	my $clone = Sesse::pr0n::QscaleProxy->new;
	$clone->{'qscale'} = qscale::qscale_clone($self->{'qscale'});
	return $clone;
}

sub Get {
	my ($self, $arg) = @_;

	if (exists($self->{'magick'})) {
		return $self->{'magick'}->Get($arg);
	}

	if ($arg eq 'rows') {
		return $self->{'qscale'}->{'height'};
	} elsif ($arg eq 'columns') {
		return $self->{'qscale'}->{'width'};
	} else {
		die "Unknown attribute '$arg'";
	}
}

sub Read {
	my ($self, @args) = @_;

	if (exists($self->{'magick'})) {
		return $self->{'magick'}->Read(@args);
	}
	if (exists($self->{'qscale'})) {
		qscale::qscale_destroy($self->{'qscale'});
		delete $self->{'qscale'};
	}

	# Small hack
	if (scalar @args == 1) {
		@args = ( filename => $args[0] );
	}

	my %args = @args;
	my $qscale;
	if (exists($args{'filename'})) {
		$qscale = qscale::qscale_load_jpeg($args{'filename'});
	} elsif (exists($args{'file'})) {
		$qscale = qscale::qscale_load_jpeg_from_stdio($args{'file'});
	} else {
		die "Missing a file or file name to load JPEG from";
	}
	
	if (qscale::qscale_is_invalid($qscale)) {
		return "400 Image loading failed";
	}
	$self->{'qscale'} = $qscale;
	return 0;
}

# Note: sampling-factor is not an ImageMagick parameter; it's qscale specific.
sub Resize {
	my ($self, %args) = @_;

	if (exists($self->{'magick'})) {
		return $self->{'magick'}->Resize(%args);
	}

	if (!(exists($args{'width'}) &&
	      exists($args{'height'}) &&
	      exists($args{'filter'}) &&
	      exists($args{'sampling-factor'}))) {
	      	die "Need arguments width, height, filter and sampling-factor.";
	}

	my $samp_h0 = 2;
	my $samp_v0 = 2;
	if (defined($args{'sampling-factor'}) && $args{'sampling-factor'} =~ /^(\d)x(\d)$/) {
		$samp_h0 = $1;
		$samp_v0 = $2;
	}

	my $samp_h1 = 1;
	my $samp_v1 = 1;
	my $samp_h2 = 1;
	my $samp_v2 = 1;

	my $filter;
	if ($args{'filter'} eq 'Lanczos') {
		$filter = $qscale::LANCZOS;
	} elsif ($args{'filter'} eq 'Mitchell') {
		$filter = $qscale::MITCHELL;
	} else {
		die "Unknown filter " . $args{'filter'};
	}
		
	my $nqscale = qscale::qscale_scale($self->{'qscale'}, $args{'width'}, $args{'height'}, $samp_h0, $samp_v0, $samp_h1, $samp_v1, $samp_h2, $samp_v2, $filter);
	qscale::qscale_destroy($self->{'qscale'});
	$self->{'qscale'} = $nqscale;

	return 0;
}

sub Strip {
	my ($self) = @_;

	if (exists($self->{'magick'})) {
		$self->{'magick'}->Strip();
	}
}

sub write {
	my ($self, %args) = @_;

	if (exists($self->{'magick'})) {
		return $self->{'magick'}->write(%args);
	}

	# For some reason we seem to get conditions of some sort when using
	# qscale for this, but not when using ImageMagick. Thus, we put the
	# atomic-write code here and not elsewhere in pr0n.
	my $filename = $args{'filename'};
	my $quality = $args{'quality'};

	my $jpeg_mode;
	if (!defined($args{'interlace'})) {
		$jpeg_mode = $qscale::SEQUENTIAL;
	} elsif ($args{'interlace'} eq 'Plane') {
		$jpeg_mode = $qscale::PROGRESSIVE;
	} else {
		die "Unknown interlacing mode " . $args{'interlace'};
	}

	my $tmpname = $filename . "-tmp-$$-" . int(rand(100000));
	unlink($filename);
	my $ret = qscale::qscale_save_jpeg($self->{'qscale'}, $tmpname, $quality, $jpeg_mode);
	if ($ret == 0) {
		if (rename($tmpname, $filename)) {
			return 0;
		} else {
			return "400 Image renaming to from $tmpname to $filename failed: $!";
		}
	} else {
		return "400 Image saving to $tmpname failed";
	}
}

1;

