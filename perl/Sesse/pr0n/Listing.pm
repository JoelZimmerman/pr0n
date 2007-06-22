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


	my $q = $dbh->prepare('SELECT event,date,name FROM events e JOIN last_picture_cache c USING (vhost,event) WHERE vhost=? ORDER BY last_picture DESC')
		or dberror($r, "Couldn't list events");
	$q->execute($r->get_server_name)
		or dberror($r, "Couldn't get events");

	my @events = ();
	while (my $ref = $q->fetchrow_hashref()) {
		my $id = $ref->{'event'};
		my $date = Encode::decode_utf8($ref->{'date'});
		my $name = Encode::decode_utf8($ref->{'name'});
	
		push @events, {
			'a' => $name,
			'a/href' => "$id/",
			'date' => $date
		};
	}
	$q->finish();

	Sesse::pr0n::Templates::output_page($r, 'listing.xml', { 'ul' => \@events });
	return Apache2::Const::OK;
}

1;


