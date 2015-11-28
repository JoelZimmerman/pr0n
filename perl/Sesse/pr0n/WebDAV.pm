package Sesse::pr0n::WebDAV;
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
	$r->header('DAV' => "1,2");

	# We only handle depth=0, depth=1 (cf. the RFC)
	my $depth = $r->header('depth');
	$depth = 0 if (!defined($depth));
	if (defined($depth) && $depth ne "0" && $depth ne "1") {
		$res->status(403);	
		$res->content_type('text/plain; charset="utf-8"');
		$res->body("Invalid depth setting");
		return $res;
	}

	# Just "ping, are you alive and do you speak WebDAV"
	if ($r->method eq "OPTIONS") {
		$res->content_type('text/plain; charset="utf-8"');
		$res->header('allow' => 'OPTIONS,PUT');
		$res->header('ms-author-via' => 'DAV');
		return $res;
	}
	
	my ($user,$takenby) = Sesse::pr0n::Common::check_access($r);
	return Sesse::pr0n::Common::generate_401($r) if (!defined($user));

	# Directory listings et al
	if ($r->method eq "PROPFIND") {
		$res->content_type('text/xml; charset="utf-8"');
		$res->status(207);

		if ($r->path_info =~ m#^/webdav/?$#) {
			$res->header('content-location' => "/webdav/");
		
			# Root directory
			$io->print(<<"EOF");
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
				$io->print(<<"EOF");
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
			$io->print("</multistatus>\n");
		 } elsif ($r->path_info =~ m#^/webdav/upload/?$#) {
			$res->header('content-location' => "/webdav/upload/");
			
			# Upload root directory
			$io->print(<<"EOF");
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
					return dberror($r, "Couldn't list events");
				$q->execute(Sesse::pr0n::Common::get_server_name($r)) or
					return dberror($r, "Couldn't get events");
		
				while (my $ref = $q->fetchrow_hashref()) {
					my $id = Encode::encode_utf8($ref->{'event'});
					my $name = Encode::encode_utf8($ref->{'name'});
				
					$name =~ s/&/\&amp;/g;  # hack :-)
					$io->print(<<"EOF");
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

			$io->print("</multistatus>\n");
		} elsif ($r->path_info =~ m#^/webdav/upload/([a-zA-Z0-9-]+)/?$#) {
			my $event = $1;
			
			$res->header('content-location' => "/webdav/upload/$event/");
			
			# Check that we do indeed exist
			my $ref = $dbh->selectrow_hashref('SELECT count(*) AS numev FROM events WHERE vhost=? AND event=?',
				undef, Sesse::pr0n::Common::get_server_name($r), $event);
			if ($ref->{'numev'} != 1) {
				$res->status(404);
				$res->content_type('text/plain; charset=utf-8');
				$res->body("Couldn't find event in database");
				return $res;
			}
			
			# OK, list the directory
			$io->print(<<"EOF");
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
				my $q = $dbh->prepare('SELECT * FROM images WHERE vhost=? AND event=?') or
					return dberror($r, "Couldn't list images");
				$q->execute(Sesse::pr0n::Common::get_server_name($r), $event) or
					return dberror($r, "Couldn't get events");
		
				while (my $ref = $q->fetchrow_hashref()) {
					my $id = $ref->{'id'};
					my $filename = $ref->{'filename'};
					my $fname = Sesse::pr0n::Common::get_disk_location($r, $id);
				        my (undef, undef, undef, undef, undef, undef, undef, $size, undef, $mtime) = stat($fname)
				                or next;
					$mtime = POSIX::strftime("%a, %d %b %Y %H:%M:%S GMT", gmtime($mtime));
					my $mime_type = Sesse::pr0n::Common::get_mimetype_from_filename($filename);

					$io->print(<<"EOF");
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
				$io->print(<<"EOF");
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

			$io->print("</multistatus>\n");
			$io->setpos(0);
			$res->body($io);
			return $res;
		} elsif ($r->path_info =~ m#^/webdav/upload/([a-zA-Z0-9-]+)/autorename/?$#) {
			# The autorename folder is always empty
			my $event = $1;
			
			$res->header('content-location' => "/webdav/upload/$event/autorename/");
			
			# Check that we do indeed exist
			my $ref = $dbh->selectrow_hashref('SELECT count(*) AS numev FROM events WHERE vhost=? AND event=?',
				undef, Sesse::pr0n::Common::get_server_name($r), $event);
			if ($ref->{'numev'} != 1) {
				$res->status(404);
				$res->content_type('text/plain; charset=utf-8');
				$res->body("Couldn't find event in database");
				return $res;
			}
			
			# OK, list the (empty) directory
			$res->body(<<"EOF");
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
	
			return $res;
		} elsif ($r->path_info =~ m#^/webdav/upload/([a-zA-Z0-9-]+)/([a-zA-Z0-9._()-]+)$#) {
			# stat a single file
			my ($event, $filename) = ($1, $2);
			my ($fname, $size, $mtime);
			
			# check if we have a pending fake file for this
			my $ref = $dbh->selectrow_hashref('SELECT count(*) AS numfiles FROM fake_files WHERE event=? AND vhost=? AND filename=? AND expires_at > now()',
				undef, $event, Sesse::pr0n::Common::get_server_name($r), $filename);
			if ($ref->{'numfiles'} == 1) {
				$fname = "/dev/null";
				$size = 0;
				$mtime = time;
			} else {
			 	($fname, $size, $mtime) = Sesse::pr0n::Common::stat_image($r, $event, $filename);
			}
			
			if (!defined($fname)) {
				$res->status(404);
				$res->content_type('text/plain; charset=utf-8');
				$res->body("Couldn't find file");
				return $res;
			}
			my $mime_type = Sesse::pr0n::Common::get_mimetype_from_filename($filename);
			
			$mtime = POSIX::strftime("%a, %d %b %Y %H:%M:%S GMT", gmtime($mtime));
			$res->body(<<"EOF");
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
			return $res;
		} elsif ($r->path_info =~ m#^/webdav/upload/([a-zA-Z0-9-]+)/autorename/(.{1,250})$#) {
			# stat a single file in autorename
			my ($event, $filename) = ($1, $2);
			my ($fname, $size, $mtime);
			
			# check if we have a pending fake file for this
			my $ref = $dbh->selectrow_hashref('SELECT count(*) AS numfiles FROM fake_files WHERE event=? AND vhost=? AND filename=? AND expires_at > now()',
				undef, $event, Sesse::pr0n::Common::get_server_name($r), $filename);
			if ($ref->{'numfiles'} == 1) {
				$fname = "/dev/null";
				$size = 0;
				$mtime = time;
			} else {
				# check if we have a "shadow file" for this
				my $ref = $dbh->selectrow_hashref('SELECT id FROM shadow_files WHERE vhost=? AND event=? AND filename=? AND expires_at > now()',
					undef, Sesse::pr0n::Common::get_server_name($r), $event, $filename);
				if (defined($ref)) {
				 	($fname, $size, $mtime) = Sesse::pr0n::Common::stat_image_from_id($r, $ref->{'id'});
				}
			}
			
			if (!defined($fname)) {
				$res->status(404);
				$res->content_type('text/plain; charset=utf-8');
				$res->body("Couldn't find file");
				return $res;
			}
			my $mime_type = Sesse::pr0n::Common::get_mimetype_from_filename($filename);
			
			$mtime = POSIX::strftime("%a, %d %b %Y %H:%M:%S GMT", gmtime($mtime));
			$io->print(<<"EOF");
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
			$res->status(404);
			$res->content_type('text/plain; charset=utf-8');
			$res->body("Couldn't find file");
			return $res;
		}
		$io->setpos(0);
		$res->body($io);
		return $res;
	}
	
	if ($r->method eq "HEAD" or $r->method eq "GET") {
		if ($r->path_info !~ m#^/webdav/upload/([a-zA-Z0-9-]+)/(autorename/)?(.{1,250})$#) {
			$res->status(404);
			$res->content_type('text/xml; charset=utf-8');
			$res->body("<?xml version=\"1.0\"?>\n<p>Couldn't find file</p>");
			return $res;
		}

		my ($event, $autorename, $filename) = ($1, $2, $3);
		
		# Check if this file really exists
		my ($fname, $size, $mtime);

		# check if we have a pending fake file for this
		my $ref = $dbh->selectrow_hashref('SELECT count(*) AS numfiles FROM fake_files WHERE event=? AND vhost=? AND filename=? AND expires_at > now()',
			undef, $event, Sesse::pr0n::Common::get_server_name($r), $filename);
		if ($ref->{'numfiles'} == 1) {
			$fname = "/dev/null";
			$size = 0;
			$mtime = time;
		} else {
			# check if we have a "shadow file" for this
			if (defined($autorename) && $autorename eq "autorename/") {
				my $ref = $dbh->selectrow_hashref('SELECT id FROM shadow_files WHERE vhost=? AND event=? AND filename=? AND expires_at > now()',
					undef, Sesse::pr0n::Common::get_server_name($r), $event, $filename);
				if (defined($ref)) {
				 	($fname, $size, $mtime) = Sesse::pr0n::Common::stat_image_from_id($r, $ref->{'id'});
				}
			} elsif (!defined($fname)) {
				($fname, $size, $mtime) = Sesse::pr0n::Common::stat_image($r, $event, $filename);
			}
		}
		
		if (!defined($fname)) {
			$res->status(404);
			$res->content_type('text/plain; charset=utf-8');
			$res->body("Couldn't find file");
			return $res;
		}
		
		$res->status(200);
		$res->set_content_length($size);
		Sesse::pr0n::Common::set_last_modified($res, $mtime);
	
		if ($r->method eq "GET") {
			$res->content(IO::File::WithPath->new($fname));
		}
		return $res;
	}
	
	if ($r->method eq "PUT") {
		if ($r->path_info !~ m#^/webdav/upload/([a-zA-Z0-9-]+)/(autorename/)?(.{1,250})$#) {
			$res->status(403);
			$res->content_type('text/plain; charset=utf-8');
			$res->body("No access");
			return $res;
		}
		
		my ($event, $autorename, $filename) = ($1, $2, $3);
		my $size = $r->header('content-length');
		if (!defined($size)) {
			$size = $r->header('x-expected-entity-length');
		}
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
		
		#
		# gnome-vfs and mac os x love to make zero-byte files,
		# make them happy
		# 
		if ($size == 0 || $filename =~ /^\.(_|DS_Store)/) {
			$dbh->do('DELETE FROM fake_files WHERE expires_at <= now() OR (event=? AND vhost=? AND filename=?);',
				undef, $event, Sesse::pr0n::Common::get_server_name($r), $filename)
				or return dberror($r, "Couldn't prune fake_files");
			$dbh->do('INSERT INTO fake_files (vhost,event,filename,expires_at) VALUES (?,?,?,now() + interval \'1 day\');',
				undef, Sesse::pr0n::Common::get_server_name($r), $event, $filename)
				or return dberror($r, "Couldn't add file");
			$res->content_type('text/plain; charset="utf-8"');
			$res->status(201);
			$res->body("OK");
			Sesse::pr0n::Common::log_info($r, "Fake upload of $event/$filename");
			return $res;
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
				$dbh->do('DELETE FROM fake_files WHERE vhost=? AND event=? AND filename=?',
					undef, Sesse::pr0n::Common::get_server_name($r), $event, $filename);
					
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
				# Don't do it for the resource forks Mac OS X loves to upload :-(
				if ($filename !~ /^\.(_|DS_Store)/) {
					# FIXME: Ideally we'd want to ensure cache of -1x-1 here as well (for NEFs), but that would
					# preclude mipmapping in its current form.
					Sesse::pr0n::Common::ensure_cached($r, $filename, $newid, undef, undef, 320, 256);
				}
				
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

		# Insert a `shadow file' we can stat the next day or so
		if (defined($autorename) && $autorename eq "autorename/") {
			$dbh->do('DELETE FROM shadow_files WHERE expires_at <= now() OR (vhost=? AND event=? AND filename=?);',
				undef, Sesse::pr0n::Common::get_server_name($r), $event, $filename)
				or return dberror($r, "Couldn't prune shadow_files");
			$dbh->do('INSERT INTO shadow_files (vhost,event,filename,id,expires_at) VALUES (?,?,?,?,now() + interval \'1 day\');',
				undef, Sesse::pr0n::Common::get_server_name($r), $event, $orig_filename, $newid)
				or return dberror($r, "Couldn't add shadow file");
			Sesse::pr0n::Common::log_info($r, "Added shadow entry for $event/$filename");
		}

		$res->content_type('text/plain; charset="utf-8"');
		$res->status(201);
		$res->body("OK");
		return $res;
	}
	
	# Yes, we fake locks. :-)
	if ($r->method eq "LOCK") {
		if ($r->path_info !~ m#^/webdav/upload/([a-zA-Z0-9-]+)/(autorename/)?([a-zA-Z0-9._-]+)$#) {
			$res->status(403);
			$res->content_type('text/plain; charset=utf-8');
			$res->body("No access");
			return $res;
		}

		my ($event, $autorename, $filename) = ($1, $2, $3);
		$autorename = '' if (!defined($autorename));
		my $sha1 = Digest::SHA::sha1_base64("/$event/$autorename$filename");

		$res->status(200);
		$res->content_type('text/xml; charset=utf-8');

		$io->print(<<"EOF");
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
		$io->setpos(0);
		$res->body($io);
		return $res;
	}
	
	if ($r->method eq "UNLOCK") {
		$res->content_type('text/plain; charset="utf-8"');
		$res->status(200);
		$res->body("OK");
		return $res;
	}

	if ($r->method eq "DELETE") {
		if ($r->path_info !~ m#^/webdav/upload/([a-zA-Z0-9-]+)/(autorename/)?(\._[a-zA-Z0-9._-]+)$#) {
			$res->status(403);
			$res->content_type('text/plain; charset=utf-8');
			$res->body("No access");
			return $res;
		}
		
		my ($event, $autorename, $filename) = ($1, $2, $3);
		$dbh->do('DELETE FROM images WHERE vhost=? AND event=? AND filename=?',
			undef, Sesse::pr0n::Common::get_server_name($r), $event, $filename)
			or return dberror($r, "Couldn't remove file");
		$dbh->do('UPDATE last_picture_cache SET last_update=CURRENT_TIMESTAMP WHERE vhost=? AND event=?',
			undef, Sesse::pr0n::Common::get_server_name($r), $event)
			or return dberror($r, "Couldn't invalidate cache");
		$res->status(200);
		$res->body("OK");

		Sesse::pr0n::Common::log_info($r, "deleted $event/$filename");
		
		return $res;
	}
	
	if ($r->method eq "MOVE" or
	    $r->method eq "MKCOL" or
	    $r->method eq "RMCOL" or
	    $r->method eq "RENAME" or
	    $r->method eq "COPY") {
		$res->content_type('text/plain; charset="utf-8"');
		$res->status(403);
		$res->body("Sorry, you do not have access to that feature.");
		return $res;
	}

	$res->content_type('text/plain; charset=utf-8');
	Sesse::pr0n::Common::log_error($r, "unknown method " . $r->method);
	$res->status(500);
	$res->body("Unknown method");
	return $res;
}

1;


