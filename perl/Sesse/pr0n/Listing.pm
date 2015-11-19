package Sesse::pr0n::Listing;
use strict;
use warnings;

use Sesse::pr0n::Common qw(error dberror);
use HTML::TagCloud;

sub handler {
	my $r = shift;
	my $dbh = Sesse::pr0n::Common::get_dbh();

        # Internal? (Ugly?)
	if (Sesse::pr0n::Common::get_server_name($r) =~ /internal/ ||
	    Sesse::pr0n::Common::get_server_name($r) =~ /skoyen\.bilder\.knatten\.com/ ||
	    Sesse::pr0n::Common::get_server_name($r) =~ /lia\.heimdal\.org/) {
		my $user = Sesse::pr0n::Common::check_access($r);
		return Sesse::pr0n::Common::generate_401($r) if (!defined($user));
	}
	
	# Fix common error: pr0n.sesse.net/+foo -> pr0n.sesse.net/+foo/
	if ($r->path_info !~ /\/$/) {
		my $res = Plack::Response->new(301);
		$res->header('Location' => $r->path_info . "/");
		return $res;
	}

	my $res = Plack::Response->new(200);
	my $io = IO::String->new;
	
	# find the last modification
	my $ref = $dbh->selectrow_hashref('SELECT EXTRACT(EPOCH FROM last_update) AS last_update FROM last_picture_cache WHERE vhost=? ORDER BY last_update DESC LIMIT 1',
		undef, Sesse::pr0n::Common::get_server_name($r))
		or return error($r, "Could not find any events", 404, "File not found");
	Sesse::pr0n::Common::set_last_modified($r, $ref->{'last_update'});
	$res->content_type('text/html; charset=utf-8');
		                
	# # If the client can use cache, do so
	# if ((my $rc = $r->meets_conditions) != Apache2::Const::OK) {
	# 	return $rc;
	# }
	
	if ($r->path_info =~ /^\/\+tags\/?/) {
		# Tag cloud
		my $q = $dbh->prepare('SELECT tag,COUNT(*) AS frequency FROM tags t JOIN images i ON t.image=i.id WHERE vhost=? GROUP BY tag ORDER BY COUNT(*) DESC LIMIT 75')
			or return dberror($r, "Couldn't list events");
		$q->execute(Sesse::pr0n::Common::get_server_name($r))
			or return dberror($r, "Couldn't get events");
		
		Sesse::pr0n::Common::header($r, $io, Sesse::pr0n::Templates::fetch_template($r, 'tag-listing'));
		Sesse::pr0n::Templates::print_template($r, $io, 'mainmenu-tags');

		my $cloud = HTML::TagCloud->new;

		while (my $ref = $q->fetchrow_hashref()) {
			my $tag = $ref->{'tag'};
			my $html = HTML::Entities::encode_entities($tag);    # is this right?
			my $uri = Sesse::pr0n::Common::pretty_escape($tag);  # and this?

			$cloud->add($html, "/+tags/$uri/", $ref->{'frequency'});
		}

		$io->print($cloud->html_and_css());
		Sesse::pr0n::Common::footer($r, $io);

		$q->finish();
	} else {
		# main listing
#		my $q = $dbh->prepare('SELECT t1.id,t1.date,t1.name FROM events t1 LEFT JOIN images t2 ON t1.id=t2.event WHERE t1.vhost=? GROUP BY t1.id,t1.date,t1.name ORDER BY COALESCE(MAX(t2.date),\'1970-01-01 00:00:00\'),t1.id') or
#			dberror($r, "Couldn't list events");
		my $q = $dbh->prepare('SELECT event,date,name FROM events e JOIN last_picture_cache c USING (vhost,event) WHERE vhost=? ORDER BY last_picture DESC NULLS LAST')
			or return dberror($r, "Couldn't list events");
		$q->execute(Sesse::pr0n::Common::get_server_name($r))
			or return dberror($r, "Couldn't get events");
		
		Sesse::pr0n::Common::header($r, $io, Sesse::pr0n::Templates::fetch_template($r, 'event-listing'));

		# See if there are any tags related to this vhost
		my $ref = $dbh->selectrow_hashref('SELECT * FROM tags t JOIN images i ON t.image=i.id WHERE vhost=? LIMIT 1',
			undef, Sesse::pr0n::Common::get_server_name($r));
		if (defined($ref)) {
			Sesse::pr0n::Templates::print_template($r, $io, 'mainmenu-events');
		}

		my $allcaption = Sesse::pr0n::Templates::fetch_template($r, 'all-event-title');
		$io->print("    <ul>\n");
		$io->print("      <li><a href=\"+all/\">$allcaption</a></li>\n");
		$io->print("    </ul>\n");
		
		$io->print("    <ul>\n");

		while (my $ref = $q->fetchrow_hashref()) {
			my $id = $ref->{'event'};
			my $date = HTML::Entities::encode_entities($ref->{'date'});
			my $name = HTML::Entities::encode_entities($ref->{'name'});
			
			$io->print("      <li><a href=\"$id/\">$name</a> ($date)</li>\n");
		}

		$io->print("    </ul>\n");
		Sesse::pr0n::Common::footer($r, $io);

		$q->finish();
	}

	$io->setpos(0);
	$res->body($io);
	return $res;
}

1;


