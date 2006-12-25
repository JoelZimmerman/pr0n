package Sesse::pr0n::WebDAV;
use strict;
use warnings;

use Sesse::pr0n::Common qw(error dberror);
use Digest::SHA1;
use MIME::Base64;

sub handler {
	my $r = shift;
	my $dbh = Sesse::pr0n::Common::get_dbh();
	
	$r->headers_out->{'DAV'} = "1,2";

	# We only handle depth=0, depth=1 (cf. the RFC)
	my $depth = $r->headers_in->{'depth'};
	$depth = 0 if (!defined($depth));
	if (defined($depth) && $depth ne "0" && $depth ne "1") {
		$r->content_type('text/plain; charset="utf-8"');
		$r->status(403);
		$r->print("Invalid depth setting");
		return Apache2::Const::OK;
	}

	my ($user,$takenby) = Sesse::pr0n::Common::check_access($r);
	if (!defined($user)) {
		return Apache2::Const::OK;
	}

	# Just "ping, are you alive and do you speak WebDAV"
	if ($r->method eq "OPTIONS") {
		$r->content_type('text/plain; charset="utf-8"');
		$r->status(200);
		$r->headers_out->{'allow'} = 'OPTIONS,PUT';
		$r->headers_out->{'ms-author-via'} = 'DAV';
		return Apache2::Const::OK;
	}
	
	# Directory listings et al
	if ($r->method eq "PROPFIND") {
		# We ignore the body, but we _must_ consume it fully before
		# we output anything, or Squid will get seriously confused
		$r->discard_request_body;

		$r->content_type('text/xml; charset="utf-8"');
		$r->status(207);

		if ($r->uri =~ m#^/webdav/?$#) {
			$r->headers_out->{'content-location'} = "/webdav/";
		
			# Root directory
			$r->print(<<"EOF");
<?xml version="1.0" encoding="utf-8"?>
<multistatus xmlns="DAV:">
  <response>
     <href>/webdav/</href>
     <propstat>
        <prop>
	  <resourcetype><collection/></resourcetype>
	  <getcontenttype>text/xml</getcontenttype>
	</prop>
        <status>HTTP/1.1 200 OK</status>
     </propstat>
  </response>
EOF

			# Optionally list the upload/ dir
			if ($depth >= 1) {
				$r->print(<<"EOF");
  <response>
     <href>/webdav/upload/</href>
     <propstat>
	<prop>
	  <resourcetype><collection/></resourcetype>
	  <getcontenttype>text/xml</getcontenttype>
	</prop>
	<status>HTTP/1.1 200 OK</status>
     </propstat>
  </response>
EOF
			}
			$r->print("</multistatus>\n");
		 } elsif ($r->uri =~ m#^/webdav/upload/?$#) {
			$r->headers_out->{'content-location'} = "/webdav/upload/";
			
			# Upload root directory
			$r->print(<<"EOF");
<?xml version="1.0" encoding="utf-8"?>
<multistatus xmlns="DAV:">
  <response>
     <href>/webdav/upload/</href>
     <propstat>
        <prop>
	  <resourcetype><collection/></resourcetype>
	  <getcontenttype>text/xml</getcontenttype>
	</prop>
        <status>HTTP/1.1 200 OK</status>
     </propstat>
  </response>
EOF

			# Optionally list all events
			if ($depth >= 1) {
				my $q = $dbh->prepare('SELECT * FROM events WHERE vhost=?') or
					dberror($r, "Couldn't list events");
				$q->execute($r->get_server_name) or
					dberror($r, "Couldn't get events");
		
				while (my $ref = $q->fetchrow_hashref()) {
					my $id = $ref->{'id'};
					my $name = $ref->{'name'};
				
					$name =~ s/&/\&amp;/g;  # hack :-)
					$r->print(<<"EOF");
  <response>
     <href>/webdav/upload/$id/</href>
     <propstat>
	<prop>
	  <resourcetype><collection/></resourcetype>
	  <getcontenttype>text/xml</getcontenttype>
	  <displayname>$name</displayname> 
	</prop>
	<status>HTTP/1.1 200 OK</status>
     </propstat>
  </response>
EOF
				}
				$q->finish;
			}

			$r->print("</multistatus>\n");
		} elsif ($r->uri =~ m#^/webdav/upload/([a-zA-Z0-9-]+)/?$#) {
			my $event = $1;
			
			$r->headers_out->{'content-location'} = "/webdav/upload/$event/";
			
			# Check that we do indeed exist
			my $ref = $dbh->selectrow_hashref('SELECT count(*) AS numev FROM events WHERE id=?',
				undef, $event);
			if ($ref->{'numev'} != 1) {
				$r->status(404);
				$r->content_type('text/plain; charset=utf-8');
				$r->print("Couldn't find event in database");
				return Apache2::Const::OK;
			}
			
			# OK, list the directory
			$r->print(<<"EOF");
<?xml version="1.0" encoding="utf-8"?>
<multistatus xmlns="DAV:">
  <response>
     <href>/webdav/upload/$event/</href>
     <propstat>
        <prop>
	  <resourcetype><collection/></resourcetype>
	  <getcontenttype>text/xml</getcontenttype>
	</prop>
        <status>HTTP/1.1 200 OK</status>
     </propstat>
  </response>
EOF

			# List all the files within too, of course :-)
			if ($depth >= 1) {
				my $q = $dbh->prepare('SELECT * FROM images WHERE event=?') or
					dberror($r, "Couldn't list images");
				$q->execute($event) or
					dberror($r, "Couldn't get events");
		
				while (my $ref = $q->fetchrow_hashref()) {
					my $id = $ref->{'id'};
					my $filename = $ref->{'filename'};
					my $fname = Sesse::pr0n::Common::get_disk_location($r, $id);
				        my (undef, undef, undef, undef, undef, undef, undef, $size, undef, $mtime) = stat($fname)
				                or next;
					$mtime = POSIX::strftime("%a, %d %b %Y %H:%M:%S GMT", gmtime($mtime));
					my $mime_type = Sesse::pr0n::Common::get_mimetype_from_filename($filename);

					$r->print(<<"EOF");
  <response>
     <href>/webdav/upload/$event/$filename</href>
     <propstat>
	<prop>
	  <resourcetype/>
	  <getcontenttype>$mime_type</getcontenttype>
	  <getcontentlength>$size</getcontentlength>
	  <getlastmodified>$mtime</getlastmodified>
	</prop>
	<status>HTTP/1.1 200 OK</status>
     </propstat>
  </response>
EOF
				}
				$q->finish;

				# And the magical autorename folder
				$r->print(<<"EOF");
  <response>
     <href>/webdav/upload/$event/autorename/</href>
     <propstat>
	<prop>
	  <resourcetype><collection/></resourcetype>
	  <getcontenttype>text/xml</getcontenttype>
	</prop>
	<status>HTTP/1.1 200 OK</status>
     </propstat>
  </response>
EOF
			}

			$r->print("</multistatus>\n");

			return Apache2::Const::OK;
		} elsif ($r->uri =~ m#^/webdav/upload/([a-zA-Z0-9-]+)/autorename/?$#) {
			# The autorename folder is always empty
			my $event = $1;
			
			$r->headers_out->{'content-location'} = "/webdav/upload/$event/autorename/";
			
			# Check that we do indeed exist
			my $ref = $dbh->selectrow_hashref('SELECT count(*) AS numev FROM events WHERE id=?',
				undef, $event);
			if ($ref->{'numev'} != 1) {
				$r->status(404);
				$r->content_type('text/plain; charset=utf-8');
				$r->print("Couldn't find event in database");
				return Apache2::Const::OK;
			}
			
			# OK, list the (empty) directory
			$r->print(<<"EOF");
<?xml version="1.0" encoding="utf-8"?>
<multistatus xmlns="DAV:">
  <response>
     <href>/webdav/upload/$event/autorename/</href>
     <propstat>
        <prop>
	  <resourcetype><collection/></resourcetype>
	  <getcontenttype>text/xml</getcontenttype>
	</prop>
        <status>HTTP/1.1 200 OK</status>
     </propstat>
  </response>
</multistatus>
EOF
	
			return Apache2::Const::OK;
		} elsif ($r->uri =~ m#^/webdav/upload/([a-zA-Z0-9-]+)/([a-zA-Z0-9._-]+)$#) {
			# stat a single file
			my ($event, $filename) = ($1, $2);
			my ($fname, $size, $mtime);
			
			# check if we have a pending fake file for this
			my $ref = $dbh->selectrow_hashref('SELECT count(*) AS numfiles FROM fake_files WHERE event=? AND filename=? AND expires_at > now()',
				undef, $event, $filename);
			if ($ref->{'numfiles'} == 1) {
				$fname = "/dev/null";
				$size = 0;
				$mtime = time;
			} else {
			 	($fname, $size, $mtime) = Sesse::pr0n::Common::stat_image($r, $event, $filename);
			}
			
			if (!defined($fname)) {
				$r->status(404);
				$r->content_type('text/plain; charset=utf-8');
				$r->print("Couldn't find file");
				return Apache2::Const::OK;
			}
			my $mime_type = Sesse::pr0n::Common::get_mimetype_from_filename($filename);
			
			$mtime = POSIX::strftime("%a, %d %b %Y %H:%M:%S GMT", gmtime($mtime));
			$r->print(<<"EOF");
<?xml version="1.0" encoding="utf-8"?>
<multistatus xmlns="DAV:">
  <response>
    <href>/webdav/upload/$event/$filename</href>
    <propstat>
      <prop>
        <resourcetype/>
        <getcontenttype>$mime_type</getcontenttype>
        <getcontentlength>$size</getcontentlength>
        <getlastmodified>$mtime</getlastmodified>
      </prop>
      <status>HTTP/1.1 200 OK</status>
    </propstat>
  </response>
</multistatus>
EOF
			return Apache2::Const::OK;
		} elsif ($r->uri =~ m#^/webdav/upload/([a-zA-Z0-9-]+)/autorename/(.{1,250})$#) {
			# stat a single file in autorename
			my ($event, $filename) = ($1, $2);
			my ($fname, $size, $mtime);
			
			# check if we have a pending fake file for this
			my $ref = $dbh->selectrow_hashref('SELECT count(*) AS numfiles FROM fake_files WHERE event=? AND filename=? AND expires_at > now()',
				undef, $event, $filename);
			if ($ref->{'numfiles'} == 1) {
				$fname = "/dev/null";
				$size = 0;
				$mtime = time;
			} else {
				# check if we have a "shadow file" for this
				my $ref = $dbh->selectrow_hashref('SELECT id FROM shadow_files WHERE event=? AND filename=? AND expires_at > now()',
					undef, $event, $filename);
				if (defined($ref)) {
				 	($fname, $size, $mtime) = Sesse::pr0n::Common::stat_image_from_id($r, $ref->{'id'});
				}
			}
			
			if (!defined($fname)) {
				$r->status(404);
				$r->content_type('text/plain; charset=utf-8');
				$r->print("Couldn't find file");
				return Apache2::Const::OK;
			}
			my $mime_type = Sesse::pr0n::Common::get_mimetype_from_filename($filename);
			
			$mtime = POSIX::strftime("%a, %d %b %Y %H:%M:%S GMT", gmtime($mtime));
			$r->print(<<"EOF");
<?xml version="1.0" encoding="utf-8"?>
<multistatus xmlns="DAV:">
  <response>
    <href>/webdav/upload/$event/autorename/$filename</href>
    <propstat>
      <prop>
        <resourcetype/>
        <getcontenttype>$mime_type</getcontenttype>
        <getcontentlength>$size</getcontentlength>
        <getlastmodified>$mtime</getlastmodified>
      </prop>
      <status>HTTP/1.1 200 OK</status>
    </propstat>
  </response>
</multistatus>
EOF
		} else {
			$r->status(404);
			$r->content_type('text/plain; charset=utf-8');
			$r->print("Couldn't find file");
		}
		return Apache2::Const::OK;
	}
	
	if ($r->method eq "HEAD" or $r->method eq "GET") {
		if ($r->uri !~ m#^/webdav/upload/([a-zA-Z0-9-]+)/(autorename/)?(.{1,250})$#) {
			$r->status(404);
			$r->content_type('text/xml; charset=utf-8');
			$r->print("<?xml version=\"1.0\"?>\n<p>Couldn't find file</p>");
			return Apache2::Const::OK;
		}

		my ($event, $autorename, $filename) = ($1, $2, $3);
		
		# Check if this file really exists
		my ($fname, $size, $mtime);

		# check if we have a pending fake file for this
		my $ref = $dbh->selectrow_hashref('SELECT count(*) AS numfiles FROM fake_files WHERE event=? AND filename=? AND expires_at > now()',
			undef, $event, $filename);
		if ($ref->{'numfiles'} == 1) {
			$fname = "/dev/null";
			$size = 0;
			$mtime = time;
		} else {
			# check if we have a "shadow file" for this
			if (defined($autorename) && $autorename eq "autorename/") {
				my $ref = $dbh->selectrow_hashref('SELECT id FROM shadow_files WHERE event=? AND filename=? AND expires_at > now()',
					undef, $event, $filename);
				if (defined($ref)) {
				 	($fname, $size, $mtime) = Sesse::pr0n::Common::stat_image_from_id($r, $ref->{'id'});
				}
			} elsif (!defined($fname)) {
				($fname, $size, $mtime) = Sesse::pr0n::Common::stat_image($r, $event, $filename);
			}
		}
		
		if (!defined($fname)) {
			$r->status(404);
			$r->content_type('text/plain; charset=utf-8');
			$r->print("Couldn't find file");
			return Apache2::Const::OK;
		}
		
		$r->status(200);
		$r->set_content_length($size);
		$r->set_last_modified($mtime);
	
		if ($r->method eq "GET") {
			$r->sendfile($fname);
		}
		return Apache2::Const::OK;
	}
	
	if ($r->method eq "PUT") {
		if ($r->uri !~ m#^/webdav/upload/([a-zA-Z0-9-]+)/(autorename/)?(.{1,250})$#) {
			$r->status(403);
			$r->content_type('text/plain; charset=utf-8');
			$r->print("No access");
			return Apache2::Const::OK;
		}
		
		my ($event, $autorename, $filename) = ($1, $2, $3);
		my $size = $r->headers_in->{'content-length'};
		my $orig_filename = $filename;

		# Remove evil characters
		if ($filename =~ /[^a-zA-Z0-9._-]/) {
			if (defined($autorename) && $autorename eq "autorename/") {
				$filename =~ tr/a-zA-Z0-9.-/_/c;
			} else {
				$r->status(403);
				$r->content_type('text/plain; charset=utf-8');
				$r->print("Illegal characters in filename");
				return Apache2::Const::OK;
			}
		}
		
		#
		# gnome-vfs and mac os x love to make zero-byte files,
		# make them happy
		# 
		if ($r->headers_in->{'content-length'} == 0) {
			$dbh->do('DELETE FROM fake_files WHERE expires_at <= now() OR (event=? AND filename=?);',
				undef, $event, $filename)
				or dberror($r, "Couldn't prune fake_files");
			$dbh->do('INSERT INTO fake_files (event,filename,expires_at) VALUES (?,?,now() + interval \'30 seconds\');',
				undef, $event, $filename)
				or dberror($r, "Couldn't add file");
			$r->content_type('text/plain; charset="utf-8"');
			$r->status(201);
			$r->print("OK");
			$r->log->info("Fake upload of $event/$filename");
			return Apache2::Const::OK;
		}

		# Get the new ID
		my $ref = $dbh->selectrow_hashref("SELECT NEXTVAL('imageid_seq') AS id;");
		my $newid = $ref->{'id'};
		if (!defined($newid)) {
			dberror($r, "Couldn't get new ID");
		}
		
		# Autorename if we need to
		if (defined($autorename) && $autorename eq "autorename/") {
			my $ref = $dbh->selectrow_hashref("SELECT COUNT(*) AS numfiles FROM images WHERE event=? AND filename=?",
				undef, $event, $filename)
				or dberror($r, "Couldn't check for existing files");
			if ($ref->{'numfiles'} > 0) {
				$r->log->info("Renaming $filename to $newid.jpeg");
				$filename = "$newid.jpeg";
			}
		}
		
		{
			# Enable transactions and error raising temporarily
			local $dbh->{AutoCommit} = 0;
			local $dbh->{RaiseError} = 1;
			my $fname;

			# Try to insert this new file
			eval {
				$dbh->do('DELETE FROM fake_files WHERE event=? AND filename=?;',
					undef, $event, $filename);
					
				$dbh->do('INSERT INTO images (id,event,uploadedby,takenby,filename) VALUES (?,?,?,?,?);',
					undef, $newid, $event, $user, $takenby, $filename);
				$dbh->do('UPDATE events SET last_update=CURRENT_TIMESTAMP WHERE id=?',
					undef, $event);

				# Now save the file to disk
				$fname = Sesse::pr0n::Common::get_disk_location($r, $newid);
				open NEWFILE, ">$fname"
					or die "$fname: $!";

				my $buf;
				my $content_length = $r->headers_in->{'content-length'};
				if ($r->read($buf, $content_length)) {
					print NEWFILE $buf or die "write($fname): $!";
				}

				close NEWFILE or die "close($fname): $!";
				
				# Orient stuff correctly
				system("/usr/bin/exifautotran", $fname) == 0
					or die "/usr/bin/exifautotran: $!";

				# Make cache while we're at it.
				# Don't do it for the resource forks Mac OS X loves to upload :-(
				if ($filename !~ /^\._/) {
					Sesse::pr0n::Common::ensure_cached($r, $filename, $newid, -1, -1, 1, 80, 64, 320, 256, -1, -1);
				}
				
				# OK, we got this far, commit
				$dbh->commit;

				$r->log->notice("Successfully wrote $event/$filename to $fname");
			};
			if ($@) {
				# Some error occurred, rollback and bomb out
				$dbh->rollback;
				error($r, "Transaction aborted because $@");
				unlink($fname);
			}
		}

		# Insert a `shadow file' we can stat the next 30 secs
		if (defined($autorename) && $autorename eq "autorename/") {
			$dbh->do('DELETE FROM shadow_files WHERE expires_at <= now() OR (event=? AND filename=?);',
				undef, $event, $filename)
				or dberror($r, "Couldn't prune shadow_files");
			$dbh->do('INSERT INTO shadow_files (event,filename,id,expires_at) VALUES (?,?,?,now() + interval \'30 seconds\');',
				undef, $event, $orig_filename, $newid)
				or dberror($r, "Couldn't add shadow file");
			$r->log->info("Added shadow entry for $event/$filename");
		}

		$r->content_type('text/plain; charset="utf-8"');
		$r->status(201);
		$r->print("OK");

		return Apache2::Const::OK;
	}

	# Yes, we fake locks. :-)
	if ($r->method eq "LOCK") {
		if ($r->uri !~ m#^/webdav/upload/([a-zA-Z0-9-]+)/(autorename/)?([a-zA-Z0-9._-]+)$#) {
			$r->status(403);
			$r->content_type('text/plain; charset=utf-8');
			$r->print("No access");
			return Apache2::Const::OK;
		}

		my ($event, $autorename, $filename) = ($1, $2, $3);
		my $sha1 = Digest::SHA1::sha1_base64("/$event/$autorename/$filename");

		$r->status(200);
		$r->content_type('text/xml; charset=utf-8');

		$r->print(<<"EOF");
<?xml version="1.0" encoding="utf-8"?>
<prop xmlns="DAV:">
  <lockdiscovery>
    <activelock>
      <locktype><write/></locktype>
      <lockscope><exclusive/></lockscope>
      <depth>0</depth>
      <owner>
        <href>/webdav/upload/$event/$autorename$filename</href>
      </owner>
      <timeout>Second-3600</timeout>
      <locktoken>
        <href>opaquelocktoken:$sha1</href>
      </locktoken>
    </activelock>
  </lockdiscovery>
</prop>
EOF
		return Apache2::Const::OK;
	}
	
	if ($r->method eq "UNLOCK") {
		$r->content_type('text/plain; charset="utf-8"');
		$r->status(200);
		$r->print("OK");

		return Apache2::Const::OK;
	}

	if ($r->method eq "DELETE") {
		if ($r->uri !~ m#^/webdav/upload/([a-zA-Z0-9-]+)/(autorename/)?(\._[a-zA-Z0-9._-]+)$#) {
			$r->status(403);
			$r->content_type('text/plain; charset=utf-8');
			$r->print("No access");
			return Apache2::Const::OK;
		}
		
		my ($event, $autorename, $filename) = ($1, $2, $3);
		$dbh->do('DELETE FROM images WHERE event=? AND filename=?;',
			undef, $event, $filename)
			or dberror($r, "Couldn't remove file");
		$dbh->do('UPDATE events SET last_update=CURRENT_TIMESTAMP WHERE id=?',
			undef, $event)
			or dberror($r, "Couldn't invalidate cache");
		$r->status(200);
		$r->print("OK");

		$r->log->info("deleted $event/$filename");
		
		return Apache2::Const::OK;
	}
	
	if ($r->method eq "MOVE" or
	    $r->method eq "MKCOL" or
	    $r->method eq "RMCOL" or
	    $r->method eq "RENAME" or
	    $r->method eq "COPY") {
		$r->content_type('text/plain; charset="utf-8"');
		$r->status(403);
		$r->print("Sorry, you do not have access to that feature.");
		return Apache2::Const::OK;
	}
	
	$r->content_type('text/plain; charset=utf-8');
	$r->log->error("unknown method " . $r->method);
	$r->status(500);
	$r->print("Unknown method");
	
	return Apache2::Const::OK;
}

1;


