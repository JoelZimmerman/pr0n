use Sesse::pr0n::Common;
use Sesse::pr0n::Listing;
use Sesse::pr0n::Index;
use Sesse::pr0n::Image;
use Sesse::pr0n::Rotate;
use Sesse::pr0n::Select;
use Sesse::pr0n::NewEvent;
use Sesse::pr0n::Upload;
use Sesse::pr0n::UploadForm;
use IO::File::WithPath;

package Sesse::pr0n::pr0n;
use strict;	
use warnings;

sub handler {
	my $r = shift;

	my $uri = $r->path_info;
	if ($uri eq '/') {
		return Sesse::pr0n::Listing::handler($r);
	} elsif ($uri eq '/robots.txt' ||
		 $uri eq '/pr0n.css' ||
		 $uri eq '/skoyen.css' ||
		 $uri eq '/faq.html' ||
		 $uri eq '/pr0n-fullscreen.css' ||
		 $uri eq '/pr0n-fullscreen-ie.css' ||
		 $uri eq '/pr0n-fullscreen.js' ||
		 $uri eq '/previous.png' ||
		 $uri eq '/next.png' ||
		 $uri eq '/close.png' ||
		 $uri eq '/options.png' ||
		 $uri =~ m#^/usage/([a-zA-Z0-9_.]+)$#) {
		$uri =~ s#^/##;
		my $fname = $Sesse::pr0n::Config::image_base . 'files/' . $uri;
		my (undef, undef, undef, undef, undef, undef, undef, $size, undef, $mtime) = stat($fname)
			or error($r, "stat of $fname: $!");

		my $res = Plack::Response->new(200);
		$res->content_type(Sesse::pr0n::Common::get_mimetype_from_filename($uri));
		$res->content_length($size);	
		Sesse::pr0n::Common::set_last_modified($res, $mtime);

		#if((my $rc = $r->meets_conditions) != Apache2::Const::OK) {
		#	return $rc;
		#}

		$res->content(IO::File::WithPath->new($Sesse::pr0n::Config::image_base . 'files/' . $uri));
		return $res;
	} elsif ($uri eq '/newevent.html') {
		my $res = Plack::Response->new(200);
		$res->content_type('text/html; charset=utf-8');
		$res->content(IO::File::WithPath->new($Sesse::pr0n::Config::image_base . 'files/newevent.html'));
		return $res;
	} elsif ($uri =~ m#^/usage/([a-zA-Z0-9.-]+)$#) {
		my $res = Plack::Response->new(200);
		$res->content(IO::File::WithPath->new($Sesse::pr0n::Config::image_base . "usage/$1"));
		return $res;
	} elsif ($uri =~ m#^/rotate$#) {
		return Sesse::pr0n::Rotate::handler($r);
	} elsif ($uri =~ m#^/select$#) {
		return Sesse::pr0n::Select::handler($r);
	} elsif ($uri =~ m#^/newevent$#) {
		return Sesse::pr0n::NewEvent::handler($r);
	} elsif ($uri =~ /^\/upload\// && ($r->method eq 'OPTIONS' || $r->method eq 'PUT')) {
		return Sesse::pr0n::Upload::handler($r);
	} elsif ($uri =~ /^\/upload\/[a-zA-Z0-9-]+\/?$/) {
		return Sesse::pr0n::UploadForm::handler($r);
	} elsif ($uri =~ /^\/[a-zA-Z0-9-]+\/?$/ ||
		 $uri =~ /^\/\+all\/?$/) {
		return Sesse::pr0n::Index::handler($r);
	} elsif ($uri =~ m#^/[a-zA-Z0-9-]+/
		           (\d+x\d+ ( \@\d+(\.\d+)? )? / | original/ )?
                           ((?:no)?box/)?
                           [a-zA-Z0-9._()-]+$#x) {
		return Sesse::pr0n::Image::handler($r);
	}

	my $res = Plack::Response->new(404);
	my $io = IO::String->new;
	Sesse::pr0n::Common::header($r, $io, "404 File Not Found");
	$io->print("     <p>The file you requested was not found.</p>");
	Sesse::pr0n::Common::footer($r, $io);
	$io->setpos(0);
	$res->body($io);
	return $res;
}

1;


