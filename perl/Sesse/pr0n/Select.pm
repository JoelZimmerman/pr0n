package Sesse::pr0n::Select;
use strict;
use warnings;

use Sesse::pr0n::Common qw(error dberror);
use Apache2::Request;

sub handler {
	my $r = shift;
	my $apr = Apache2::Request->new($r);
	my $dbh = Sesse::pr0n::Common::get_dbh();
	my ($user, $takenby) = Sesse::pr0n::Common::check_access($r);
	if (!defined($user)) {
		return Apache2::Const::OK;
	}

	my $event = $apr->param('event');

	Sesse::pr0n::Common::header($r, "Selection results");

	{
		# Enable transactions and error raising temporarily
		local $dbh->{AutoCommit} = 0;
		local $dbh->{RaiseError} = 1;

		my $filename = $apr->param('filename');
		my $selected = $apr->param('selected');
		my $sql_selected = 'f';
		if (!defined($selected) || $selected eq '1') {
			$sql_selected = 't';
		}
		$dbh->do('UPDATE images SET selected=? WHERE vhost=? AND event=? AND filename=?', undef, $sql_selected, $r->get_server_name, $event, $filename);
	}

	$dbh->do('UPDATE last_picture_cache SET last_update=CURRENT_TIMESTAMP WHERE vhost=? AND event=?', undef, $r->get_server_name, $event)
		or dberror($r, "Cache invalidation failed");

	Sesse::pr0n::Common::footer($r);

	return Apache2::Const::OK;
}

1;


