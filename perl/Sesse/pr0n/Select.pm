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

		if (defined($apr->param('mode')) && $apr->param('mode') eq 'single') {
			# single mode; enable one (FIXME: need to support disable too)
			my $filename = $apr->param('filename');
			$dbh->do('UPDATE images SET selected=\'t\' WHERE event=? AND filename=?', undef, $event, $filename);
		} else {
			# traditional multi-mode
			$dbh->do('UPDATE images SET selected=\'f\' WHERE event=?', undef, $event);
		
			my @params = $apr->param();
			my $key;
			for $key (@params) {
				if ($key =~ /^sel-(\d+)/ && $apr->param($key) eq 'on') {
					my $id = $1;
					my $q = $dbh->do('UPDATE images SET selected=\'t\' WHERE id=?', undef, $id)
						or dberror($r, "Selection of $id failed: $!");
					$r->print("    <p>Selected image ID `$id'.</p>\n");
				}
			}
		}
	}

	Sesse::pr0n::Common::footer($r);

	return Apache2::Const::OK;
}

1;


