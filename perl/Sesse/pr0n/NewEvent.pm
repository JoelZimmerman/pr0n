package Sesse::pr0n::NewEvent;
use strict;
use warnings;

use Sesse::pr0n::Common qw(error dberror);
use Apache2::Request;

sub handler {
	my $r = shift;
	my $apr = Apache2::Request->new($r);
	my $dbh = Sesse::pr0n::Common::get_dbh();
	my $user = Sesse::pr0n::Common::check_access($r);
	if (!defined($user)) {
		return Apache2::Const::OK;
	}

	Sesse::pr0n::Common::header($r, "Legger til ny hendelse");

	my $ok = 1;

	my $id = $apr->param('id');
	if (!defined($id) || $id =~ /^\s*$/ || $id !~ /^([a-zA-Z0-9-]+)$/) {
		$r->print("    <p>Feil: Manglende eller ugyldig ID.</p>\n");
		$ok = 0;
	}

	my $date = $apr->param('date');
	if (!defined($date) || $date =~ /^\s*$/ || $date =~ /[<>&]/ || length($date) > 100) {
		$r->print("    <p>Feil: Manglende eller ugyldig dato.</p>\n");
		$ok = 0;
	}
	
	my $desc = $apr->param('desc');
	if (!defined($desc) || $desc =~ /^\s*$/ || $desc =~ /[<>&]/ || length($desc) > 100) {
		$r->print("    <p>Feil: Manglende eller ugyldig beskrivelse.</p>\n");
		$ok = 0;
	}
	
	if ($ok == 0) {
		$r->print("    <p>Rett opp i feilene over før du går videre.</p>\n");
	} else {
		$dbh->do("INSERT INTO events (id,date,name,vhost) VALUES (?,?,?,?)",
			undef, $id, $date, $desc, $r->get_server_name)
			or dberror($r, "Kunne ikke sette inn ny hendelse");
		$dbh->do("INSERT INTO last_picture_cache (event,last_picture) VALUES (?,NULL)",
			undef, $id)
			or dberror($r, "Kunne ikke sette inn ny cache-rad");
		$r->print("    <p>Hendelsen '$id' lagt til.</p>");
	}
	
	Sesse::pr0n::Common::footer($r);

	return Apache2::Const::OK;
}

1;


