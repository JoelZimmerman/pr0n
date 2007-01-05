package Sesse::pr0n::Rotate;
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

	Sesse::pr0n::Common::header($r, "Rotation/deletion results");

	{
		# Enable transactions and error raising temporarily
		local $dbh->{AutoCommit} = 0;
		local $dbh->{RaiseError} = 1;

		my @params = $apr->param();
		my $key;
		for $key (@params) {
			# Rotation
			if ($key =~ /^rot-(\d+)-(90|180|270)$/ && $apr->param($key) eq 'on') {
				my ($id, $rotval) = ($1,$2);
				my $fname = Sesse::pr0n::Common::get_disk_location($r, $id);
				(my $tmpfname = $fname) =~ s/\.jpg$/-tmp.jpg/;

				system("/usr/bin/jpegtran -rotate $rotval -copy all < '$fname' > '$tmpfname' && mv '$tmpfname' '$fname'") == 0
					or error($r, "Rotation of $id [/usr/bin/jpegtran -rotate $rotval -copy all < '$fname' > '$tmpfname' && mv '$tmpfname' '$fname'] failed: $!.");
				$r->print("    <p>Rotated image ID `$id' by $rotval degrees.</p>\n");

				if ($rotval == 90 || $rotval == 270) {
					my $q = $dbh->do('UPDATE images SET height=width,width=height WHERE id=?', undef, $id)
						or dberror($r, "Size clear of $id failed");
					$dbh->do('UPDATE events SET last_update=CURRENT_TIMESTAMP WHERE id=( SELECT event FROM images WHERE id=? )',
						undef, $id)
						or dberror($r, "Cache invalidation at $id failed");
				}
			} elsif ($key =~ /^del-(\d+)$/ && $apr->param($key) eq 'on') {
				my $id = $1;
				{

					eval {
						$dbh->do('UPDATE events SET last_update=CURRENT_TIMESTAMP WHERE id=( SELECT event FROM images WHERE id=? )',
							undef, $id);
						$dbh->do('INSERT INTO deleted_images SELECT * FROM images WHERE id=?',
							undef, $id);
						$dbh->do('DELETE FROM images WHERE id=?',
							undef, $id);
					};
					if ($@) {
# Some error occurred, rollback and bomb out
						$dbh->rollback;
						dberror($r, "Transaction aborted because $@");
					}
				}
				$r->print("    <p>Deleted image `$id'.</p>\n");
			}
		}
	}
	
	my $event = $apr->param('event');
	$dbh->do('UPDATE events SET last_update=CURRENT_TIMESTAMP WHERE id=?', undef, $event)
		or dberror($r, "Cache invalidation failed");

	Sesse::pr0n::Common::footer($r);

	return Apache2::Const::OK;
}

1;


