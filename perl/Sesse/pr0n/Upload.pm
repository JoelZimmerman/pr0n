package Sesse::pr0n::Upload;
use strict;
use warnings;

use Sesse::pr0n::Common qw(error dberror);
use Digest::SHA;
use MIME::Base64;

sub handler {
	my $r = shift;
	my $dbh = Sesse::pr0n::Common::get_dbh();

	my $res = Plack::Response->new(200);
	my $io = IO::String->new;

	my ($user,$takenby) = Sesse::pr0n::Common::check_access($r);
	return Sesse::pr0n::Common::generate_401($r) if (!defined($user));

	# Just "ping, are you alive"
	if ($r->method eq "OPTIONS") {
		$res->content_type('text/plain; charset="utf-8"');
		return $res;
	}
	
	if ($r->method eq "PUT") {
		if ($r->path_info !~ m#^/upload/([a-zA-Z0-9-]+)/(autorename/)?(.{1,250})$#) {
			$res->status(403);
			$res->content_type('text/plain; charset=utf-8');
			$res->body("No access");
			return $res;
		}
		
		my ($event, $autorename, $filename) = ($1, $2, $3);
		my $size = $r->header('content-length');
		my $orig_filename = $filename;

		# Remove evil characters
		if ($filename =~ /[^a-zA-Z0-9._()-]/) {
			if (defined($autorename) && $autorename eq "autorename/") {
				$filename =~ tr/a-zA-Z0-9.()-/_/c;
			} else {
				$res->status(403);
				$res->content_type('text/plain; charset=utf-8');
				$res->body("Illegal characters in filename");
				return $res;
			}
		}
		
		# Get the new ID
		my $ref = $dbh->selectrow_hashref("SELECT NEXTVAL('imageid_seq') AS id;");
		my $newid = $ref->{'id'};
		if (!defined($newid)) {
			return dberror($r, "Couldn't get new ID");
		}
		
		# Autorename if we need to
		$ref = $dbh->selectrow_hashref("SELECT COUNT(*) AS numfiles FROM images WHERE vhost=? AND event=? AND filename=?",
		                               undef, Sesse::pr0n::Common::get_server_name($r), $event, $filename)
			or return dberror($r, "Couldn't check for existing files");
		if ($ref->{'numfiles'} > 0) {
			if (defined($autorename) && $autorename eq "autorename/") {
				Sesse::pr0n::Common::log_info($r, "Renaming $filename to $newid.jpeg");
				$filename = "$newid.jpeg";
			} else {
				$res->status(403);
				$res->content_type('text/plain; charset=utf-8');
				$res->body("File $filename already exists in event $event, cannot overwrite");
				return $res;
			}
		}
		
		{
			# Enable transactions and error raising temporarily
			local $dbh->{AutoCommit} = 0;
			local $dbh->{RaiseError} = 1;
			my $fname;

			# Try to insert this new file
			eval {
				$dbh->do('INSERT INTO images (id,vhost,event,uploadedby,takenby,filename) VALUES (?,?,?,?,?,?)',
					undef, $newid, Sesse::pr0n::Common::get_server_name($r), $event, $user, $takenby, $filename);
				Sesse::pr0n::Common::purge_cache($r, $res, "/$event/");

				# Now save the file to disk
				Sesse::pr0n::Common::ensure_disk_location_exists($r, $newid);	
				$fname = Sesse::pr0n::Common::get_disk_location($r, $newid);

				open NEWFILE, ">", $fname
					or die "$fname: $!";
				print NEWFILE $r->content;
				close NEWFILE or die "close($fname): $!";
				
				# Orient stuff correctly
				system("/usr/bin/exifautotran", $fname) == 0
					or die "/usr/bin/exifautotran: $!";

				# Make cache while we're at it.
				# FIXME: Ideally we'd want to ensure cache of -1x-1 here as well (for NEFs), but that would
				# preclude mipmapping in its current form.
				Sesse::pr0n::Common::ensure_cached($r, $filename, $newid, undef, undef, 320, 256);
				
				# OK, we got this far, commit
				$dbh->commit;

				Sesse::pr0n::Common::log_info($r, "Successfully wrote $event/$filename to $fname");
			};
			if ($@) {
				# Some error occurred, rollback and bomb out
				$dbh->rollback;
				unlink($fname);
				return error($r, "Transaction aborted because $@");
			}
		}

		$res->content_type('text/plain; charset="utf-8"');
		$res->status(201);
		$res->body("OK");
		return $res;
	}

	$res->content_type('text/plain; charset=utf-8');
	Sesse::pr0n::Common::log_error($r, "unknown method " . $r->method);
	$res->status(500);
	$res->body("Unknown method");
	return $res;
}

1;


