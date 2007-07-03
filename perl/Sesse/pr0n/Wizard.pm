package Sesse::pr0n::Wizard;
use strict;
use warnings;

use Sesse::pr0n::Common qw(error dberror);
use Apache2::Request;

sub handler {
	my $r = shift;
	my $apr = Apache2::Request->new($r);
	my $dbh = Sesse::pr0n::Common::get_dbh();

        # Internal? (Ugly?)
	if ($r->get_server_name =~ /internal/ || $r->get_server_name =~ /skoyen\.bilder\.knatten\.com/) {
		my $user = Sesse::pr0n::Common::check_access($r);
		if (!defined($user)) {
			return Apache2::Const::OK;
		}
	}

	# Find events
	my $q = $dbh->prepare('SELECT event,date,name FROM events e JOIN last_picture_cache c USING (vhost,event) WHERE vhost=? ORDER BY last_picture DESC')
		or dberror($r, "Couldn't list events");
	$q->execute($r->get_server_name)
		or dberror($r, "Couldn't get events");

	$r->content_type('text/html; charset=utf-8');
	$r->print(Sesse::pr0n::Templates::fetch_template($r, 'wizard-header'));
	
	while (my $ref = $q->fetchrow_hashref()) {
		my $id = $ref->{'event'};
		my $date = $ref->{'date'};
		my $name = $ref->{'name'};
		
		$r->print("              <option value=\"$id\">$name</option>\n");
	}

	$r->print(Sesse::pr0n::Templates::fetch_template($r, 'wizard-footer'));

	return Apache2::Const::OK;
}
	
1;


