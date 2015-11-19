package Sesse::pr0n::Index;
use strict;
use warnings;

use Sesse::pr0n::Common qw(error dberror);
use POSIX;

sub handler {
	my $r = shift;
	my $dbh = Sesse::pr0n::Common::get_dbh();

	my ($event, $abspath, $datesort);
	if ($r->path_info =~ /^\/\+all\/?/) {
		$event = '+all';
		$abspath = 1;

		$datesort = 'DESC NULLS LAST';
	} else {
		# Find the event
		$r->path_info =~ /^\/([a-zA-Z0-9-]+)\/?$/
			or return error($r, "Could not extract event");
		$event = $1;
		$abspath = 0;
		$datesort = 'ASC NULLS LAST';
	}

	# Fix common error: pr0n.sesse.net/event -> pr0n.sesse.net/event/
	if ($r->path_info !~ /\/$/) {
		my $res = Plack::Response->new(301);
		$res->header('Location' => $r->path_info . "/");
		return $res;
	}

	# Internal? (Ugly?) 
	if (Sesse::pr0n::Common::get_server_name($r) =~ /internal/ ||
	    Sesse::pr0n::Common::get_server_name($r) =~ /skoyen\.bilder\.knatten\.com/ ||
	    Sesse::pr0n::Common::get_server_name($r) =~ /lia\.heimdal\.org/) {
		my $user = Sesse::pr0n::Common::check_access($r);
		return Sesse::pr0n::Common::generate_401($r) if (!defined($user));
	}

	# Read the appropriate settings from the query string into the settings hash
	my %defsettings = (
		thumbxres => 320,
		thumbyres => 256,
		xres => -1,
		yres => -1,
		start => 1,
		num => 250,
		all => 1,
		rot => 0,
		sel => 0,
		fullscreen => 0,
		model => undef,
		lens => undef,
		author => undef
	);
	
	my $where;
	if ($event eq '+all') {
		$where = '';
	} else {
		$where = ' AND event=' . $dbh->quote($event);
	}
	
	# Any NEF files => default to processing
	my $ref = $dbh->selectrow_hashref("SELECT * FROM images WHERE vhost=? $where AND ( LOWER(filename) LIKE '%.nef' OR LOWER(filename) LIKE '%.cr2' ) LIMIT 1",
		undef, Sesse::pr0n::Common::get_server_name($r))
		and $defsettings{'xres'} = $defsettings{'yres'} = undef;
	
	my %settings = %defsettings;

	for my $s (qw(thumbxres thumbyres xres yres start num all rot sel fullscreen model lens author)) {
		my $val = $r->param($s);
		if (defined($val) && $val =~ /^(\d+)$/) {
			$settings{$s} = $val;
		}
		if ($s eq "num" && defined($val) && $val == -1) {
			$settings{$s} = $val;
		}
		if (($s eq "xres" || $s eq "yres") && defined($val) && ($val == -1 || $val == -2)) {
			$settings{$s} = $val;
		}
		if (($s eq "model" || $s eq "lens" || $s eq "author") && defined($val)) {
			$settings{$s} = Sesse::pr0n::Common::pretty_unescape($val);
		}
	}

	my $thumbxres = $settings{'thumbxres'};
	my $thumbyres = $settings{'thumbyres'};
	my $xres = $settings{'xres'};
	my $yres = $settings{'yres'};
	my $start = $settings{'start'};
	my $num = $settings{'num'};
	my $all = $settings{'all'};
	my $rot = $settings{'rot'};
	my $sel = $settings{'sel'};
	my $model = $settings{'model'};
	my $lens = $settings{'lens'};
	my $author = $settings{'author'};

	# Construct SQL for this filter
	if ($all == 0) {
		$where .= ' AND selected=\'t\'';	
	}
	if (defined($model) && defined($lens)) {
		my $mq = $dbh->quote($model);
		my $lq = $dbh->quote($lens);

		if ($model eq '') {
			# no defined model
			$where .= " AND model IS NULL";
		} else {
			$where .= " AND model=$mq";
		}
	
		if ($lens eq '') {
			# no defined lens
			$where .= " AND lens IS NULL";
		} else {
			$where .= " AND lens=$lq";
		}
	}
	if (defined($author)) {
		my $aq = $dbh->quote($author);

		$where .= " AND takenby=$aq";
	}

	if (defined($num) && $num == -1) {
		$num = undef;
	}

	my ($date, $name);

	if ($event eq '+all') {
		$ref = $dbh->selectrow_hashref("SELECT EXTRACT(EPOCH FROM MAX(last_update)) AS last_update FROM last_picture_cache WHERE vhost=?",
			undef, Sesse::pr0n::Common::get_server_name($r))
			or return error($r, "Could not list events", 404, "File not found");
		$date = undef;
		$name = Sesse::pr0n::Templates::fetch_template($r, 'all-event-title');
		Sesse::pr0n::Common::set_last_modified($r, $ref->{'last_update'});
	} else {
		$ref = $dbh->selectrow_hashref("SELECT name,date,EXTRACT(EPOCH FROM last_update) AS last_update FROM events NATURAL JOIN last_picture_cache WHERE vhost=? AND event=?",
			undef, Sesse::pr0n::Common::get_server_name($r), $event)
			or return error($r, "Could not find event $event", 404, "File not found");

		$date = HTML::Entities::encode_entities($ref->{'date'});
		$name = HTML::Entities::encode_entities($ref->{'name'});
		Sesse::pr0n::Common::set_last_modified($r, $ref->{'last_update'});
	}
		                
	# # If the client can use cache, do so
	# if ((my $rc = $r->meets_conditions) != Apache2::Const::OK) {
	# 	return $rc;
	# }
	
	# Count the number of selected images.
	$ref = $dbh->selectrow_hashref("SELECT COUNT(*) AS num_selected FROM images WHERE vhost=? $where AND selected=\'t\'", undef, Sesse::pr0n::Common::get_server_name($r));
	my $num_selected = $ref->{'num_selected'};

	# Find all images related to this event.
	my $limit = (defined($start) && defined($num) && !$settings{'fullscreen'}) ? (" LIMIT $num OFFSET " . ($start-1)) : "";

	my $q = $dbh->prepare("SELECT *, (date - INTERVAL '6 hours')::date AS day FROM images WHERE vhost=? $where ORDER BY (date - INTERVAL '6 hours')::date $datesort,takenby,date,filename $limit")
		or return dberror($r, "prepare()");
	$q->execute(Sesse::pr0n::Common::get_server_name($r))
		or return dberror($r, "image enumeration");

	# Print the page itself
	my $res = Plack::Response->new(200);
	my $io = IO::String->new;
	if ($settings{'fullscreen'}) {
		$res->content_type("text/html; charset=utf-8");

		Sesse::pr0n::Templates::print_template($r, $io, "fullscreen-header", { title => "$name [$event]" });

		my @files = ();
		while (my $ref = $q->fetchrow_hashref()) {
			my $width = defined($ref->{'width'}) ? $ref->{'width'} : -1;
			my $height = defined($ref->{'height'}) ? $ref->{'height'} : -1;
			push @files, [ $ref->{'event'}, $ref->{'filename'}, $width, $height ];
		}
		
		for my $i (0..$#files) {
			my $line = sprintf "        [ \"%s\", \"%s\", %d, %d ]", @{$files[$i]};
			$line .= "," unless ($i == $#files);
			$io->print($line . "\n");
		}

		my %settings_no_fullscreen = %settings;
		$settings_no_fullscreen{'fullscreen'} = 0;

		my $returnurl = "http://" . Sesse::pr0n::Common::get_server_name($r) . "/" . $event . "/" .
			Sesse::pr0n::Common::get_query_string(\%settings_no_fullscreen, \%defsettings);
		
		# *whistle*
		$returnurl =~ s/&amp;/&/g;

		Sesse::pr0n::Templates::print_template($r, $io, "fullscreen-footer", {
			returnurl => $returnurl,
			start => $settings{'start'} - 1,
			sel => $settings{'sel'}
		});
	} else {
		Sesse::pr0n::Common::header($r, $io, "$name [$event]");
		if (defined($date)) {
			Sesse::pr0n::Templates::print_template($r, $io, "date", { date => $date });
		}

		if (Sesse::pr0n::Overload::is_in_overload($r)) {
			Sesse::pr0n::Templates::print_template($r, $io, "overloadmode");
		}

		print_selected($r, $io, $event, \%settings, \%defsettings) if ($num_selected > 0);
		print_fullscreen($r, $io, $event, \%settings, \%defsettings);
		print_nextprev($r, $io, $event, $where, \%settings, \%defsettings);
	
		if (1 || $event ne '+all') {
			# Find the equipment used
			my $eq = $dbh->prepare("
				SELECT
					model,
					lens,
					COUNT(*) AS num
				FROM images
				WHERE vhost=? $where
				GROUP BY 1,2
				ORDER BY 1,2")
				or die "Couldn't prepare to find equipment: $!";
			$eq->execute(Sesse::pr0n::Common::get_server_name($r))
				or die "Couldn't find equipment: $!";

			my @equipment = ();
			my %cameras_seen = ();
			while (my $ref = $eq->fetchrow_hashref) {
				if (!defined($ref->{'lens'}) && exists($cameras_seen{$ref->{'model'}})) {
					#
					# Some compact cameras seem to add lens info sometimes and not at other
					# times; if we have seen a camera with at least one specific lens earlier,
					# just combine entries without a lens with the previous one.
					#
					$equipment[$#equipment]->{'num'} += $ref->{'num'};
					next;
				}
				push @equipment, $ref;
				$cameras_seen{$ref->{'model'}} = 1;
			}
			$eq->finish;

			if (scalar @equipment > 0) {
				Sesse::pr0n::Templates::print_template($r, $io, "equipment-start");
				for my $e (@equipment) {
					my $eqspec = $e->{'model'};
					$eqspec .= ', ' . $e->{'lens'} if (defined($e->{'lens'}));
					$eqspec = HTML::Entities::encode_entities($eqspec);

					my %newsettings = %settings;

					my $action;
					if (defined($model) && defined($lens)) {
						chomp ($action = Sesse::pr0n::Templates::fetch_template($r, "unfilter"));
						$newsettings{'model'} = undef;
						$newsettings{'lens'} = undef;
						$newsettings{'start'} = 1;
					} else {
						chomp ($action = Sesse::pr0n::Templates::fetch_template($r, "filter"));
						$newsettings{'model'} = $e->{'model'};
						$newsettings{'lens'} = defined($e->{'lens'}) ? $e->{'lens'} : '';
						$newsettings{'start'} = 1;
					}
					
					my $url = "/$event/" . Sesse::pr0n::Common::get_query_string(\%newsettings, \%defsettings);

					# This isn't correct for all languages. Fix if we ever need to care. :-)
					if ($e->{'num'} == 1) {
						Sesse::pr0n::Templates::print_template($r, $io, "equipment-item-singular", { eqspec => $eqspec, filterurl => $url, action => $action });
					} else {
						Sesse::pr0n::Templates::print_template($r, $io, "equipment-item", { eqspec => $eqspec, num => $e->{'num'}, filterurl => $url, action => $action });
					}
				}
				Sesse::pr0n::Templates::print_template($r, $io, "equipment-end");
			}
		}

		my $toclose = 0;
		my $lastupl = "";
		my $img_num = (defined($start) && defined($num)) ? $start : 1;
		
		# Print out all thumbnails
		if ($rot == 1) {
			$io->print("    <form method=\"post\" action=\"/rotate\">\n");
			$io->print("      <input type=\"hidden\" name=\"event\" value=\"$event\" />\n");
		}

		while (my $ref = $q->fetchrow_hashref()) {
			my $imgsz = "";
			my $takenby = $ref->{'takenby'};
			my $day = '';
			if (defined($ref->{'day'})) {
				$day = ", " . $ref->{'day'};
			}

			my $groupkey = $takenby . $day;

			if ($groupkey ne $lastupl) {
				$io->print("    </p>\n\n") if ($lastupl ne "" && $rot != 1);
				$lastupl = $groupkey;

				my %newsettings = %settings;

				my $action;
				if (defined($author)) {
					chomp ($action = Sesse::pr0n::Templates::fetch_template($r, "unfilter"));
					$newsettings{'author'} = undef;
					$newsettings{'start'} = 1;
				} else {
					chomp ($action = Sesse::pr0n::Templates::fetch_template($r, "filter"));
					$newsettings{'author'} = $ref->{'takenby'};
					$newsettings{'start'} = 1;
				}

				my $url = "/$event/" . Sesse::pr0n::Common::get_query_string(\%newsettings, \%defsettings);
				
				$io->print("    <h2>");
				Sesse::pr0n::Templates::print_template($r, $io, "submittedby", { author => $takenby, action => $action, filterurl => $url, date => $day });
				print_fullscreen_fromhere($r, $io, $event, \%settings, \%defsettings, $img_num);
				$io->print("</h2>\n");

				if ($rot != 1) {
					$io->print("    <p class=\"photos\">\n");
				}
			}

			if (defined($ref->{'width'}) && defined($ref->{'height'})) {
				my $width = $ref->{'width'};
				my $height = $ref->{'height'};
					
				($width, $height) = Sesse::pr0n::Common::scale_aspect($width, $height, $thumbxres, $thumbyres);
				$imgsz = " width=\"$width\" height=\"$height\"";
			}

			# Add fullscreen link.
			my %fssettings = %settings;
			$fssettings{'fullscreen'} = 1;
			$fssettings{'start'} = $img_num;
			my $fsquery = Sesse::pr0n::Common::get_query_string(\%fssettings, \%defsettings);

			my $filename = $ref->{'filename'};
			my $uri = $filename;
			if (defined($xres) && defined($yres) && $xres != -1 && $xres != -2) {
				$uri = "${xres}x$yres/$filename";
			} elsif (defined($xres) && $xres == -1) {
				$uri = "original/$filename";
			}
			
			my $prefix = "";
			if ($abspath) {
				$prefix = "/" . $ref->{'event'} . "/";
			}
		
			if ($rot == 1) {	
				$io->print("    <p>");
			} else {
				$io->print("     ");
			}
			$io->print("<a href=\"$prefix$uri\" onclick=\"location.href='$prefix$fsquery';return false;\"><img src=\"$prefix${thumbxres}x${thumbyres}/$filename\" alt=\"\"$imgsz /></a>\n");
		
			if ($rot == 1) {
				$io->print("      90 <input type=\"checkbox\" name=\"rot-" .
					$ref->{'id'} . "-90\" />\n");
				$io->print("      180 <input type=\"checkbox\" name=\"rot-" .
					$ref->{'id'} . "-180\" />\n");
				$io->print("      270 <input type=\"checkbox\" name=\"rot-" .
					$ref->{'id'} . "-270\" />\n");
				$io->print("      &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;" .
					"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Del <input type=\"checkbox\" name=\"del-" . $ref->{'id'} . "\" /></p>\n");
			}
			
			++$img_num;
		}

		if ($rot == 1) {
			$io->print("      <input type=\"submit\" value=\"Rotate\" />\n");
			$io->print("    </form>\n");
		} else {
			$io->print("    </p>\n");
		}

		print_nextprev($r, $io, $event, $where, \%settings, \%defsettings);
		Sesse::pr0n::Common::footer($r, $io);
	}

	$io->setpos(0);
	$res->body($io);
	return $res;
}

sub eq_with_undef {
	my ($a, $b) = @_;
	
	return 1 if (!defined($a) && !defined($b));
	return 0 unless (defined($a) && defined($b));
	return ($a eq $b);
}

sub print_changes {
	my ($r, $io, $event, $template, $settings, $defsettings, $var1, $var2, $alternatives) = @_;

	my $title = Sesse::pr0n::Templates::fetch_template($r, $template);
	chomp $title;
	$io->print("    <p>$title:\n");

	for my $a (@$alternatives) {
		my $text;
		my %newsettings = %$settings;

		if (ref $a) {
			my ($v1, $v2);
			($text, $v1, $v2) = @$a;
			
			$newsettings{$var1} = $v1;
			$newsettings{$var2} = $v2;
		} else {
			$text = $a;

			# Parse the current alternative
			my ($v1, $v2) = split /x/, $a;

			$newsettings{$var1} = $v1;
			$newsettings{$var2} = $v2;
		}

		$io->print("      ");

		# Check if these settings are current (print only label)
		if (eq_with_undef($settings->{$var1}, $newsettings{$var1}) &&
		    eq_with_undef($settings->{$var2}, $newsettings{$var2})) {
			$io->print($text);
		} else {
			Sesse::pr0n::Common::print_link($io, $text, "/$event/", \%newsettings, $defsettings);
		}
		$io->print("\n");
	}
	$io->print("    </p>\n");
}

sub print_nextprev {
	my ($r, $io, $event, $where, $settings, $defsettings) = @_;
	my $start = $settings->{'start'};
	my $num = $settings->{'num'};
	my $dbh = Sesse::pr0n::Common::get_dbh();

	$num = undef if (defined($num) && $num == -1);
	return unless (defined($start) && defined($num));

	# determine total number
	my $ref = $dbh->selectrow_hashref("SELECT count(*) AS num_images FROM images WHERE vhost=? $where",
		undef, Sesse::pr0n::Common::get_server_name($r))
		or return dberror($r, "image enumeration");
	my $num_images = $ref->{'num_images'};

	return if ($start == 1 && $start + $num >= $num_images);

	my $end = $start + $num - 1;
	if ($end > $num_images) {
		$end = $num_images;
	}

	$io->print("    <p class=\"nextprev\">\n");

	# Previous
	if ($start > 1) {
		my $newstart = $start - $num;
		if ($newstart < 1) {
			$newstart = 1;
		}
		my $newend = $newstart + $num - 1;
		if ($newend > $num_images) {
			$newend = $num_images;
		}

		my %newsettings = %$settings;
		$newsettings{'start'} = $newstart;
		chomp (my $title = Sesse::pr0n::Templates::fetch_template($r, 'prevpage'));
		chomp (my $accesskey = Sesse::pr0n::Templates::fetch_template($r, 'prevaccesskey'));
		Sesse::pr0n::Common::print_link($io, "$title ($newstart-$newend)\n", "/$event/", \%newsettings, $defsettings, $accesskey);
	}

	# This
	chomp (my $title = Sesse::pr0n::Templates::fetch_template($r, 'thispage'));
	$io->print("    $title ($start-$end)\n");

	# Next
	if ($end < $num_images) {
		my $newstart = $start + $num;
		my $newend = $newstart + $num - 1;
		if ($newend > $num_images) {
			$newend = $num_images;
		}
		
		my %newsettings = %$settings;
		$newsettings{'start'} = $newstart;
		chomp (my $title = Sesse::pr0n::Templates::fetch_template($r, 'nextpage'));
		chomp (my $accesskey = Sesse::pr0n::Templates::fetch_template($r, 'nextaccesskey'));
		Sesse::pr0n::Common::print_link($io, "$title ($newstart-$newend)", "/$event/", \%newsettings, $defsettings, $accesskey);
	}

	$io->print("    </p>\n");
}

sub print_selected {
	my ($r, $io, $event, $settings, $defsettings) = @_;

	chomp (my $title = Sesse::pr0n::Templates::fetch_template($r, 'show'));
	chomp (my $all = Sesse::pr0n::Templates::fetch_template($r, 'show-all'));
	chomp (my $sel = Sesse::pr0n::Templates::fetch_template($r, 'show-selected'));

        $io->print("    <p>$title:\n");

	my %newsettings = %$settings;

	if ($settings->{'all'} == 0) {
		$io->print($sel);
	} else {
		$newsettings{'all'} = 0;
		Sesse::pr0n::Common::print_link($io, $sel, "/$event/", \%newsettings, $defsettings);
	}

	$io->print(' ');

	if ($settings->{'all'} == 1) {
		$io->print($all);
	} else {
		$newsettings{'all'} = 1;
		Sesse::pr0n::Common::print_link($io, $all, "/$event/", \%newsettings, $defsettings);
	}
	
	$io->print('</p>');
}

sub print_fullscreen {
	my ($r, $io, $event, $settings, $defsettings) = @_;

	chomp (my $title = Sesse::pr0n::Templates::fetch_template($r, 'fullscreen'));

	my %newsettings = %$settings;
	$newsettings{'fullscreen'} = 1;

        $io->print("    <p>");
	Sesse::pr0n::Common::print_link($io, $title, "/$event/", \%newsettings, $defsettings);
	$io->print("</p>\n");
}

sub print_fullscreen_fromhere {
	my ($r, $io, $event, $settings, $defsettings, $start) = @_;

	chomp (my $title = Sesse::pr0n::Templates::fetch_template($r, 'fullscreen-fromhere'));

	my %newsettings = %$settings;
	$newsettings{'fullscreen'} = 1;
	$newsettings{'start'} = $start;

        $io->print("    <span class=\"fsfromhere\">");
	Sesse::pr0n::Common::print_link($io, $title, "/$event/", \%newsettings, $defsettings);
	$io->print("</span>\n");
}
	
1;


