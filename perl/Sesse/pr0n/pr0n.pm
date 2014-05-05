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
	if ($uri eq '/' || $uri =~ /^\/\+tags\/?$/) {
		return Sesse::pr0n::Listing::handler($r);
	} elsif ($uri eq '/robots.txt' ||
		 $uri eq '/pr0n.css' ||
		 $uri eq '/skoyen.css' ||
		 $uri eq '/blah.png' ||
		 $uri eq '/faq.html' ||
		 $uri eq '/pr0n-fullscreen.css' ||
		 $uri eq '/pr0n-fullscreen-ie.css' ||
		 $uri eq '/pr0n-fullscreen.js' ||
		 $uri eq '/previous.png' ||
		 $uri eq '/next.png' ||
		 $uri eq '/close.png' ||
		 $uri eq '/wizard.js' ||
		 $uri eq '/wizard.css' ||
		 $uri eq '/pr0n.ico' ||
		 $uri =~ m#^/usage/([a-zA-Z0-9_.]+)$#) {
		$uri =~ s#^/##;
		my $fname = Sesse::pr0n::Common::get_base($r) . 'files/' . $uri;
		my (undef, undef, undef, undef, undef, undef, undef, $size, undef, $mtime) = stat($fname)
			or error($r, "stat of $fname: $!");

		$r->content_type(Sesse::pr0n::Common::get_mimetype_from_filename($uri));
		$r->set_content_length($size);	
		$r->set_last_modified($mtime);

		if((my $rc = $r->meets_conditions) != Apache2::Const::OK) {
			return $rc;
		}

		$r->sendfile(Sesse::pr0n::Common::get_base($r) . 'files/' . $uri);
		return Apache2::Const::OK;
	} elsif ($uri eq '/newevent.html') {
		$r->content_type('text/html; charset=utf-8');
		$r->sendfile(Sesse::pr0n::Common::get_base($r) . "files/newevent.html");
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
	} elsif ($uri =~ /^\/[a-zA-Z0-9-]+\/?$/ ||
		 $uri =~ /^\/\+all\/?$/ ||
		 $uri =~ /^\/\+tags\/[a-zA-Z0-9-]+\/?$/) {
		return Sesse::pr0n::Index::handler($r);
	} elsif ($uri =~ m#^/[a-zA-Z0-9-]+/(\d+x\d+/|original/)?((?:no)?box/)?[a-zA-Z0-9._()-]+$#) {
		return Sesse::pr0n::Image::handler($r);
	}

	$r->status(404);
	Sesse::pr0n::Common::header($r, "404 File Not Found");
	$r->print("     <p>The file you requested was not found.</p>");
	Sesse::pr0n::Common::footer($r);
	return Apache2::Const::OK;
}

1;


