package Sesse::pr0n::Listing;
use strict;
use warnings;

use Sesse::pr0n::Common qw(error dberror);

sub handler {
	my $r = shift;
	my $dbh = Sesse::pr0n::Common::get_dbh();

        # Internal? (Ugly?)
	if ($r->get_server_name =~ /internal/ || $r->get_server_name =~ /skoyen\.bilder\.knatten\.com/) {
		my $user = Sesse::pr0n::Common::check_access($r);
		if (!defined($user)) {
			return Apache2::Const::OK;
		}
	}
	
	# find the last modification
	my $ref = $dbh->selectrow_hashref('SELECT EXTRACT(EPOCH FROM last_update) AS last_update FROM events WHERE vhost=? ORDER BY last_update DESC LIMIT 1',
		undef, $r->get_server_name)
		or error($r, "Could not any events", 404, "File not found");
	$r->set_last_modified($ref->{'last_update'});
	$r->content_type('text/html; charset=utf-8');
		                
	# If the client can use cache, do so
	if ((my $rc = $r->meets_conditions) != Apache2::Const::OK) {
		return $rc;
	}

#	my $q = $dbh->prepare('SELECT t1.id,t1.date,t1.name FROM events t1 LEFT JOIN images t2 ON t1.id=t2.event WHERE t1.vhost=? GROUP BY t1.id,t1.date,t1.name ORDER BY COALESCE(MAX(t2.date),\'1970-01-01 00:00:00\'),t1.id') or
#		dberror($r, "Couldn't list events");
	my $q = $dbh->prepare('SELECT event,date,name FROM events e JOIN last_picture_cache c USING (vhost,event) WHERE vhost=? ORDER BY last_picture DESC')
		or dberror($r, "Couldn't list events");
	$q->execute($r->get_server_name)
		or dberror($r, "Couldn't get events");
	
	Sesse::pr0n::Common::header($r, Sesse::pr0n::Templates::fetch_template($r, 'event-listing'));
	$r->print("    <ul>\n");

	while (my $ref = $q->fetchrow_hashref()) {
		my $id = $ref->{'event'};
		my $date = HTML::Entities::encode_entities(Encode::decode_utf8($ref->{'date'}));
		my $name = HTML::Entities::encode_entities(Encode::decode_utf8($ref->{'name'}));
		
		$r->print("      <li><a href=\"$id/\">$name</a> ($date)</li>\n");
	}

	$r->print("    </ul>\n");
	Sesse::pr0n::Common::footer($r);

	$q->finish();
	return Apache2::Const::OK;
}

1;


