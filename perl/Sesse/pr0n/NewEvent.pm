package Sesse::pr0n::NewEvent;
use strict;
use warnings;

use Sesse::pr0n::Common qw(error dberror);

sub handler {
	my $r = shift;
	my $dbh = Sesse::pr0n::Common::get_dbh();
	my $user = Sesse::pr0n::Common::check_access($r);
	return Sesse::pr0n::Common::generate_401($r) if (!defined($user));

	my $res = Plack::Response->new(200);
	my $io = IO::String->new;
	Sesse::pr0n::Common::header($r, $io, "Legger til ny hendelse");
	
	my $id = $r->param('id');
	my $date = Encode::decode_utf8($r->param('date'));
	my $desc = Encode::decode_utf8($r->param('desc'));

	my @errors = Sesse::pr0n::Common::add_new_event($r, $res, $dbh, $id, $date, $desc);
	
	if (scalar @errors > 0) {
		for my $err (@errors) {
			$io->print("    <p>Feil: $err</p>\n");
		}
		$io->print("    <p>Rett opp i feilene over før du går videre.</p>\n");
	} else {
		$io->print("    <p>Hendelsen '<a href=\"/upload/$id/\">$id</a>' lagt til.</p>");
	}
	
	Sesse::pr0n::Common::footer($r, $io);

	$io->setpos(0);
	$res->body($io);
	return $res;
}

1;


