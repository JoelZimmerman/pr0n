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
	
	my $id = $apr->param('id');
	my $date = $apr->param('date');
	my $desc = $apr->param('desc');

	my @errors = Sesse::pr0n::Common::add_new_event($r, $dbh, $id, $date, $desc);
	
	if (scalar @errors > 0) {
		for my $err (@errors) {
			$r->print("    <p>Feil: $err</p>\n");
		}
		$r->print("    <p>Rett opp i feilene over før du går videre.</p>\n");
	} else {
		$r->print("    <p>Hendelsen '$id' lagt til.</p>");
	}
	
	Sesse::pr0n::Common::footer($r);

	return Apache2::Const::OK;
}

1;


