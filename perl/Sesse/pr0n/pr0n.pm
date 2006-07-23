use Sesse::pr0n::Common;
use Sesse::pr0n::Listing;
use Sesse::pr0n::Index;
use Sesse::pr0n::Image;
use Sesse::pr0n::Rotate;
use Sesse::pr0n::Select;
use Sesse::pr0n::WebDAV;
use Sesse::pr0n::NewEvent;

package Sesse::pr0n::pr0n;
use strict;	
use warnings;

sub handler {
	my $r = shift;

	my $uri = $r->uri;
	if ($uri eq '/') {
		return Sesse::pr0n::Listing::handler($r);
	} elsif ($uri eq '/robots.txt' ||
		 $uri eq '/pr0n.css' ||
		 $uri eq '/skoyen.css' ||
		 $uri eq '/blah.png' ||
		 $uri eq '/faq.html' ||
		 $uri =~ m#^/usage/([a-zA-Z0-9_.]+)$#) {
		$uri =~ s#^/##;
		$r->content_type(Sesse::pr0n::Common::get_mimetype_from_filename($uri));
		$r->sendfile(Sesse::pr0n::Common::get_base($r) . $uri);
		return Apache2::Const::OK;
	} elsif ($uri eq '/newevent.html') {
		$r->content_type('text/html; charset=utf-8');
		$r->sendfile(Sesse::pr0n::Common::get_base($r) . "newevent.html");
		return Apache2::Const::OK;
	} elsif ($uri =~ m#^/webdav#) {
		return Sesse::pr0n::WebDAV::handler($r);
	} elsif ($uri =~ m#^/usage/([a-zA-Z0-9.-]+)$#) {
		$r->sendfile(Sesse::pr0n::Common::get_base($r) . "usage/$1");
		return Apache2::Const::OK;
	} elsif ($uri =~ m#^/rotate$#) {
		return Sesse::pr0n::Rotate::handler($r);
	} elsif ($uri =~ m#^/select$#) {
		return Sesse::pr0n::Select::handler($r);
	} elsif ($uri =~ m#^/newevent$#) {
		return Sesse::pr0n::NewEvent::handler($r);
	} elsif ($uri =~ m#^/[a-zA-Z0-9-]+/?$#) {
		return Sesse::pr0n::Index::handler($r);
	} elsif ($uri =~ m#^/[a-zA-Z0-9-]+/(\d+x\d+/)?(nobox/)?[a-zA-Z0-9._-]+$#) {
		return Sesse::pr0n::Image::handler($r);
	}

	$r->status(404);
	Sesse::pr0n::Common::header($r, "404 File Not Found");
	$r->print("     <p>The file you requested was not found.</p>");
	Sesse::pr0n::Common::footer($r);
	return Apache2::Const::OK;
}

1;


