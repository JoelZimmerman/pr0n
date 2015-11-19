package Sesse::pr0n::Select;
use strict;
use warnings;

use Sesse::pr0n::Common qw(error dberror);

sub handler {
	my $r = shift;
	my $dbh = Sesse::pr0n::Common::get_dbh();
	my ($user, $takenby) = Sesse::pr0n::Common::check_access($r);
	return Sesse::pr0n::Common::generate_401($r) if (!defined($user));

	my $event = $r->param('event');

	my $res = Plack::Response->new(200);
	my $io = IO::String->new;
	Sesse::pr0n::Common::header($r, $io, "Selection results");

	{
		# Enable transactions and error raising temporarily
		local $dbh->{AutoCommit} = 0;
		local $dbh->{RaiseError} = 1;

		my $filename = $r->param('filename');
		my $selected = $r->param('selected');
		my $sql_selected = 'f';
		if (!defined($selected) || $selected eq '1') {
			$sql_selected = 't';
		}
		$dbh->do('UPDATE images SET selected=? WHERE vhost=? AND event=? AND filename=?', undef, $sql_selected, Sesse::pr0n::Common::get_server_name($r), $event, $filename);
	}

	$dbh->do('UPDATE last_picture_cache SET last_update=CURRENT_TIMESTAMP WHERE vhost=? AND event=?', undef, Sesse::pr0n::Common::get_server_name($r), $event)
		or return dberror($r, "Cache invalidation failed");
	Sesse::pr0n::Common::purge_cache($r, $res, "/$event/");
	Sesse::pr0n::Common::footer($r, $io);

	$io->setpos(0);
	$res->body($io);
	return $res;
}

1;


