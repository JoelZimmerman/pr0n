package Sesse::pr0n::Rotate;
use strict;
use warnings;

use Sesse::pr0n::Common qw(error dberror);

sub handler {
	my $r = shift;
	my $dbh = Sesse::pr0n::Common::get_dbh();
	my ($user, $takenby) = Sesse::pr0n::Common::check_access($r);
	return Sesse::pr0n::Common::generate_401($r) if (!defined($user));

	# FIXME: People can rotate and delete across vhosts using this interface.
	# We should add some sanity checks.

	my @to_purge = ();

	Sesse::pr0n::Common::header($r, "Rotation/deletion results");

	my $res = Plack::Response->new(200);
	my $io = IO::String->new;

	{
		# Enable transactions and error raising temporarily
		local $dbh->{RaiseError} = 1;

		my @params = $r->param();
		my $key;
		for $key (@params) {
			local $dbh->{AutoCommit} = 0;

			# Rotation
			if ($key =~ /^rot-(\d+)-(90|180|270)$/ && $r->param($key) eq 'on') {
				my ($id, $rotval) = ($1,$2);
				my $fname = Sesse::pr0n::Common::get_disk_location($r, $id);
				push @to_purge, Sesse::pr0n::Common::get_all_cache_urls($r, $dbh, $id);
				(my $tmpfname = $fname) =~ s/\.jpg$/-tmp.jpg/;

				system("/usr/bin/jpegtran -rotate $rotval -copy all < '$fname' > '$tmpfname' && /bin/mv '$tmpfname' '$fname'") == 0
					or return error($r, "Rotation of $id [/usr/bin/jpegtran -rotate $rotval -copy all < '$fname' > '$tmpfname' && /bin/mv '$tmpfname' '$fname'] failed: $!.");
				$io->print("    <p>Rotated image ID `$id' by $rotval degrees.</p>\n");

				if ($rotval == 90 || $rotval == 270) {
					my $q = $dbh->do('UPDATE images SET height=width,width=height WHERE id=?', undef, $id)
						or return dberror($r, "Size clear of $id failed");
					$dbh->do('UPDATE last_picture_cache SET last_update=CURRENT_TIMESTAMP WHERE (vhost,event)=( SELECT vhost,event FROM images WHERE id=? )',
						undef, $id)
						or return dberror($r, "Cache invalidation at $id failed");
				}
			} elsif ($key =~ /^del-(\d+)$/ && $r->param($key) eq 'on') {
				my $id = $1;
				push @to_purge, Sesse::pr0n::Common::get_all_cache_urls($r, $dbh, $id);
				{

					eval {
						$dbh->do('UPDATE last_picture_cache SET last_update=CURRENT_TIMESTAMP WHERE (vhost,event)=( SELECT vhost,event FROM images WHERE id=? )',
							undef, $id);
						$dbh->do('INSERT INTO deleted_images SELECT * FROM images WHERE id=?',
							undef, $id);
						$dbh->do('DELETE FROM exif_info WHERE image=?',
							undef, $id);
						$dbh->do('DELETE FROM images WHERE id=?',
							undef, $id);
					};
					if ($@) {
# Some error occurred, rollback and bomb out
						$dbh->rollback;
						return dberror($r, "Transaction aborted because $@");
					}
				}
				$io->print("    <p>Deleted image `$id'.</p>\n");
			}
		}
	}
	
	my $event = $r->param('event');
	$dbh->do('UPDATE last_picture_cache SET last_update=CURRENT_TIMESTAMP WHERE vhost=? AND event=?', undef, Sesse::pr0n::Common::get_server_name($r), $event)
		or return dberror($r, "Cache invalidation failed");

	push @to_purge, "/$event/";
	push @to_purge, "/+all/";
	Sesse::pr0n::Common::purge_cache($r, $res, @to_purge);

	Sesse::pr0n::Common::footer($r, $io);
	$io->setpos(0);
	$res->body($io);
	return $res;
}

1;


