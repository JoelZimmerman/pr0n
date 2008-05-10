package Sesse::pr0n::Index;
use strict;
use warnings;

use Sesse::pr0n::Common qw(error dberror);
use Apache2::Request;
use POSIX;

sub handler {
	my $r = shift;
	my $apr = Apache2::Request->new($r);
	my $dbh = Sesse::pr0n::Common::get_dbh();

	my ($event, $abspath, $datesort, $tag);
	if ($r->uri =~ /^\/\+all\/?/) {
		$event = '+all';
		$abspath = 1;
		$tag = undef; 

		$datesort = 'DESC NULLS LAST';
	} elsif ($r->uri =~ /^\/\+tags\/([a-zA-Z0-9-]+)\/?$/) {
		$tag = $1;
		$event = "+tags/$tag";
		$abspath = 1;
		
		$datesort = 'DESC NULLS LAST';
	} else {
		# Find the event
		$r->uri =~ /^\/([a-zA-Z0-9-]+)\/?$/
			or error($r, "Could not extract event");
		$event = $1;
		$abspath = 0;
		$tag = undef;
		$datesort = 'ASC NULLS LAST';
	}

	# Fix common error: pr0n.sesse.net/event -> pr0n.sesse.net/event/
	if ($r->uri !~ /\/$/) {
		$r->headers_out->{'location'} = $r->uri . "/";
		return Apache2::Const::REDIRECT;
	}

	# Internal? (Ugly?) 
	if ($r->get_server_name =~ /internal/ || $r->get_server_name =~ /skoyen\.bilder\.knatten\.com/ || $r->get_server_name =~ /lia\.heimdal\.org/) {
		my $user = Sesse::pr0n::Common::check_access($r);
		if (!defined($user)) {
			return Apache2::Const::OK;
		}
	}

	# Read the appropriate settings from the query string into the settings hash
	my %defsettings = (
		thumbxres => 80,
		thumbyres => 64,
		xres => -1,
		yres => -1,
		start => 1,
		num => 250,
		all => 1,
		infobox => 1,
		rot => 0,
		sel => 0,
		fullscreen => 0,
		model => undef,
		lens => undef,
		author => undef
	);
	
	my $where;
	if (defined($tag)) {
		my $tq = $dbh->quote($tag);
		$where = " AND id IN ( SELECT image FROM tags WHERE tag=$tq )";
	} elsif ($event eq '+all') {
		$where = '';
	} else {
		$where = ' AND event=' . $dbh->quote($event);
	}
	
	# Any NEF files => default to processing
	my $ref = $dbh->selectrow_hashref("SELECT * FROM images WHERE vhost=? $where AND LOWER(filename) LIKE '%.nef' LIMIT 1",
		undef, $r->get_server_name)
		and $defsettings{'xres'} = $defsettings{'yres'} = undef;
	
	# Reduce the front page load when in overload mode.
	if (Sesse::pr0n::Overload::is_in_overload($r)) {
		$defsettings{'num'} = 100;
	}
		
	my %settings = %defsettings;

	for my $s qw(thumbxres thumbyres xres yres start num all infobox rot sel fullscreen model lens author) {
		my $val = $apr->param($s);
		if (defined($val) && $val =~ /^(\d+)$/) {
			$settings{$s} = $val;
		}
		if (($s eq "num" || $s eq "xres" || $s eq "yres") && defined($val) && $val == -1) {
			$settings{$s} = $val;
		}
		if ($s eq "model" || $s eq "lens" || $s eq "author") {
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
	my $infobox = $settings{'infobox'} ? '' : 'nobox/';
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

	if ($event eq '+all' || defined($tag)) {
		$ref = $dbh->selectrow_hashref("SELECT EXTRACT(EPOCH FROM MAX(last_update)) AS last_update FROM events WHERE vhost=?",
			undef, $r->get_server_name)
			or error($r, "Could not list events", 404, "File not found");
		$date = undef;
		$name = Sesse::pr0n::Templates::fetch_template($r, 'all-event-title');
		$r->set_last_modified($ref->{'last_update'});
	} else {
		$ref = $dbh->selectrow_hashref("SELECT name,date,EXTRACT(EPOCH FROM last_update) AS last_update FROM events WHERE vhost=? AND event=?",
			undef, $r->get_server_name, $event)
			or error($r, "Could not find event $event", 404, "File not found");

		$date = HTML::Entities::encode_entities(Encode::decode_utf8($ref->{'date'}));
		$name = HTML::Entities::encode_entities(Encode::decode_utf8($ref->{'name'}));
		$r->set_last_modified($ref->{'last_update'});
	}
		                
	# If the client can use cache, do so
	if ((my $rc = $r->meets_conditions) != Apache2::Const::OK) {
		return $rc;
	}
	
	# Count the number of selected images.
	$ref = $dbh->selectrow_hashref("SELECT COUNT(*) AS num_selected FROM images WHERE vhost=? $where AND selected=\'t\'", undef, $r->get_server_name);
	my $num_selected = $ref->{'num_selected'};

	# Find all images related to this event.
	my $limit = (defined($start) && defined($num) && !$settings{'fullscreen'}) ? (" LIMIT $num OFFSET " . ($start-1)) : "";

	my $q = $dbh->prepare("SELECT *, (date - INTERVAL '6 hours')::date AS day FROM images WHERE vhost=? $where ORDER BY (date - INTERVAL '6 hours')::date $datesort,takenby,date,filename $limit")
		or dberror($r, "prepare()");
	$q->execute($r->get_server_name)
		or dberror($r, "image enumeration");

	# Print the page itself
	if ($settings{'fullscreen'}) {
		$r->content_type("text/html; charset=utf-8");

		if (defined($tag)) {
			my $title = Sesse::pr0n::Templates::process_template($r, "tag-title", { tag => $tag });
			Sesse::pr0n::Templates::print_template($r, "fullscreen-header", { title => $title });
		} else {
			Sesse::pr0n::Templates::print_template($r, "fullscreen-header", { title => "$name [$event]" });
		}

		my @files = ();
		while (my $ref = $q->fetchrow_hashref()) {
			my $width = defined($ref->{'width'}) ? $ref->{'width'} : -1;
			my $height = defined($ref->{'height'}) ? $ref->{'height'} : -1;
			push @files, [ $ref->{'event'}, $ref->{'filename'}, $width, $height ];
		}
		
		for my $i (0..$#files) {
			my $line = sprintf "        [ \"%s\", \"%s\", %d, %d ]", @{$files[$i]};
			$line .= "," unless ($i == $#files);
			$r->print($line . "\n");
		}

		my %settings_no_fullscreen = %settings;
		$settings_no_fullscreen{'fullscreen'} = 0;

		my $returnurl = "http://" . $r->get_server_name . "/" . $event . "/" .
			Sesse::pr0n::Common::get_query_string(\%settings_no_fullscreen, \%defsettings);
		
		# *whistle*
		$returnurl =~ s/&amp;/&/g;

		Sesse::pr0n::Templates::print_template($r, "fullscreen-footer", {
			vhost => $r->get_server_name,
			returnurl => $returnurl,
			start => $settings{'start'} - 1,
			sel => $settings{'sel'},
			infobox => $infobox
		});
	} else {
		if (defined($tag)) {
			my $title = Sesse::pr0n::Templates::process_template($r, "tag-title", { tag => $tag });
			Sesse::pr0n::Common::header($r, $title);
		} else {
			Sesse::pr0n::Common::header($r, "$name [$event]");
		}
		if (defined($date)) {
			Sesse::pr0n::Templates::print_template($r, "date", { date => $date });
		}

		if (Sesse::pr0n::Overload::is_in_overload($r)) {
			Sesse::pr0n::Templates::print_template($r, "overloadmode");
		}

		print_thumbsize($r, $event, \%settings, \%defsettings);
		print_viewres($r, $event, \%settings, \%defsettings);
		print_pagelimit($r, $event, \%settings, \%defsettings);
		print_infobox($r, $event, \%settings, \%defsettings);
		print_selected($r, $event, \%settings, \%defsettings) if ($num_selected > 0);
		print_fullscreen($r, $event, \%settings, \%defsettings);
		print_nextprev($r, $event, $where, \%settings, \%defsettings);
	
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
			$eq->execute($r->get_server_name)
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
				Sesse::pr0n::Templates::print_template($r, "equipment-start");
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
						Sesse::pr0n::Templates::print_template($r, "equipment-item-singular", { eqspec => $eqspec, filterurl => $url, action => $action });
					} else {
						Sesse::pr0n::Templates::print_template($r, "equipment-item", { eqspec => $eqspec, num => $e->{'num'}, filterurl => $url, action => $action });
					}
				}
				Sesse::pr0n::Templates::print_template($r, "equipment-end");
			}
		}

		my $toclose = 0;
		my $lastupl = "";
		my $img_num = (defined($start) && defined($num)) ? $start : 1;
		
		# Print out all thumbnails
		if ($rot == 1) {
			$r->print("    <form method=\"post\" action=\"/rotate\">\n");
			$r->print("      <input type=\"hidden\" name=\"event\" value=\"$event\" />\n");
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
				$r->print("    </p>\n\n") if ($lastupl ne "" && $rot != 1);
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
				
				$r->print("    <h2>");
				Sesse::pr0n::Templates::print_template($r, "submittedby", { author => $takenby, action => $action, filterurl => $url, date => $day });
				print_fullscreen_fromhere($r, $event, \%settings, \%defsettings, $img_num);
				$r->print("</h2>\n");

				if ($rot != 1) {
					$r->print("    <p class=\"photos\">\n");
				}
			}

			if (defined($ref->{'width'}) && defined($ref->{'height'})) {
				my $width = $ref->{'width'};
				my $height = $ref->{'height'};
					
				($width, $height) = Sesse::pr0n::Common::scale_aspect($width, $height, $thumbxres, $thumbyres);
				$imgsz = " width=\"$width\" height=\"$height\"";
			}

			my $filename = $ref->{'filename'};
			my $uri = $infobox . $filename;
			if (defined($xres) && defined($yres) && $xres != -1) {
				$uri = "${xres}x$yres/$infobox$filename";
			} elsif (defined($xres) && $xres == -1) {
				$uri = "original/$infobox$filename";
			}
			
			my $prefix = "";
			if ($abspath) {
				$prefix = "/" . $ref->{'event'} . "/";
			}
		
			if ($rot == 1) {	
				$r->print("    <p>");
			} else {
				$r->print("     ");
			}
			$r->print("<a href=\"$prefix$uri\"><img src=\"$prefix${thumbxres}x${thumbyres}/$filename\" alt=\"\"$imgsz /></a>\n");
		
			if ($rot == 1) {
				$r->print("      90 <input type=\"checkbox\" name=\"rot-" .
					$ref->{'id'} . "-90\" />\n");
				$r->print("      180 <input type=\"checkbox\" name=\"rot-" .
					$ref->{'id'} . "-180\" />\n");
				$r->print("      270 <input type=\"checkbox\" name=\"rot-" .
					$ref->{'id'} . "-270\" />\n");
				$r->print("      &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;" .
					"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Del <input type=\"checkbox\" name=\"del-" . $ref->{'id'} . "\" /></p>\n");
			}
			
			++$img_num;
		}

		if ($rot == 1) {
			$r->print("      <input type=\"submit\" value=\"Rotate\" />\n");
			$r->print("    </form>\n");
		} else {
			$r->print("    </p>\n");
		}

		print_nextprev($r, $event, $where, \%settings, \%defsettings);
		Sesse::pr0n::Common::footer($r);
	}

	return Apache2::Const::OK;
}

sub eq_with_undef {
	my ($a, $b) = @_;
	
	return 1 if (!defined($a) && !defined($b));
	return 0 unless (defined($a) && defined($b));
	return ($a eq $b);
}

sub print_changes {
	my ($r, $event, $template, $settings, $defsettings, $var1, $var2, $alternatives) = @_;

	my $title = Sesse::pr0n::Templates::fetch_template($r, $template);
	chomp $title;
	$r->print("    <p>$title:\n");

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

		$r->print("      ");

		# Check if these settings are current (print only label)
		if (eq_with_undef($settings->{$var1}, $newsettings{$var1}) &&
		    eq_with_undef($settings->{$var2}, $newsettings{$var2})) {
			$r->print($text);
		} else {
			Sesse::pr0n::Common::print_link($r, $text, "/$event/", \%newsettings, $defsettings);
		}
		$r->print("\n");
	}
	$r->print("    </p>\n");
}

sub print_thumbsize {
	my ($r, $event, $settings, $defsettings) = @_;
	my @alternatives = qw(80x64 120x96 160x128 240x192 320x256);

	print_changes($r, $event, 'thumbsize', $settings, $defsettings,
		      'thumbxres', 'thumbyres', \@alternatives);
}
sub print_viewres {
	my ($r, $event, $settings, $defsettings) = @_;
	my @alternatives = qw(320x256 512x384 640x480 800x600 1024x768 1152x864 1280x960 1400x1050 1600x1200);
	chomp (my $unlimited = Sesse::pr0n::Templates::fetch_template($r, 'viewres-unlimited'));
	chomp (my $original = Sesse::pr0n::Templates::fetch_template($r, 'viewres-original'));
	push @alternatives, [ $unlimited, undef, undef ];
	push @alternatives, [ $original, -1, -1 ];

	print_changes($r, $event, 'viewres', $settings, $defsettings,
		      'xres', 'yres', \@alternatives);
}

sub print_pagelimit {
	my ($r, $event, $settings, $defsettings) = @_;
	
	my $title = Sesse::pr0n::Templates::fetch_template($r, 'imgsperpage');
	chomp $title;
	$r->print("    <p>$title:\n");
	
	# Get choices
	chomp (my $unlimited = Sesse::pr0n::Templates::fetch_template($r, 'imgsperpage-unlimited'));
	my @alternatives = qw(10 50 100 250 500);
	push @alternatives, $unlimited;
	
	for my $num (@alternatives) {
		my %newsettings = %$settings;

		if ($num !~ /^\d+$/) { # unlimited
			$newsettings{'num'} = -1;
		} else {
			$newsettings{'num'} = $num;
		}

		$r->print("      ");
		if (eq_with_undef($settings->{'num'}, $newsettings{'num'})) {
			$r->print($num);
		} else {
			Sesse::pr0n::Common::print_link($r, $num, "/$event/", \%newsettings, $defsettings);
		}
		$r->print("\n");
	}
	$r->print("    </p>\n");
}

sub print_infobox {
	my ($r, $event, $settings, $defsettings) = @_;

	chomp (my $title = Sesse::pr0n::Templates::fetch_template($r, 'infobox'));
	chomp (my $on = Sesse::pr0n::Templates::fetch_template($r, 'infobox-on'));
	chomp (my $off = Sesse::pr0n::Templates::fetch_template($r, 'infobox-off'));

        $r->print("    <p>$title:\n");

	my %newsettings = %$settings;

	if ($settings->{'infobox'} == 1) {
		$r->print($on);
	} else {
		$newsettings{'infobox'} = 1;
		Sesse::pr0n::Common::print_link($r, $on, "/$event/", \%newsettings, $defsettings);
	}

	$r->print(' ');

	if ($settings->{'infobox'} == 0) {
		$r->print($off);
	} else {
		$newsettings{'infobox'} = 0;
		Sesse::pr0n::Common::print_link($r, $off, "/$event/", \%newsettings, $defsettings);
	}
	
	$r->print('</p>');
}

sub print_nextprev {
	my ($r, $event, $where, $settings, $defsettings) = @_;
	my $start = $settings->{'start'};
	my $num = $settings->{'num'};
	my $dbh = Sesse::pr0n::Common::get_dbh();

	$num = undef if (defined($num) && $num == -1);
	return unless (defined($start) && defined($num));

	# determine total number
	my $ref = $dbh->selectrow_hashref("SELECT count(*) AS num_images FROM images WHERE vhost=? $where",
		undef, $r->get_server_name)
		or dberror($r, "image enumeration");
	my $num_images = $ref->{'num_images'};

	return if ($start == 1 && $start + $num >= $num_images);

	my $end = $start + $num - 1;
	if ($end > $num_images) {
		$end = $num_images;
	}

	$r->print("    <p class=\"nextprev\">\n");

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
		Sesse::pr0n::Common::print_link($r, "$title ($newstart-$newend)\n", "/$event/", \%newsettings, $defsettings, $accesskey);
	}

	# This
	chomp (my $title = Sesse::pr0n::Templates::fetch_template($r, 'thispage'));
	$r->print("    $title ($start-$end)\n");

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
		Sesse::pr0n::Common::print_link($r, "$title ($newstart-$newend)", "/$event/", \%newsettings, $defsettings, $accesskey);
	}

	$r->print("    </p>\n");
}

sub print_selected {
	my ($r, $event, $settings, $defsettings) = @_;

	chomp (my $title = Sesse::pr0n::Templates::fetch_template($r, 'show'));
	chomp (my $all = Sesse::pr0n::Templates::fetch_template($r, 'show-all'));
	chomp (my $sel = Sesse::pr0n::Templates::fetch_template($r, 'show-selected'));

        $r->print("    <p>$title:\n");

	my %newsettings = %$settings;

	if ($settings->{'all'} == 0) {
		$r->print($sel);
	} else {
		$newsettings{'all'} = 0;
		Sesse::pr0n::Common::print_link($r, $sel, "/$event/", \%newsettings, $defsettings);
	}

	$r->print(' ');

	if ($settings->{'all'} == 1) {
		$r->print($all);
	} else {
		$newsettings{'all'} = 1;
		Sesse::pr0n::Common::print_link($r, $all, "/$event/", \%newsettings, $defsettings);
	}
	
	$r->print('</p>');
}

sub print_fullscreen {
	my ($r, $event, $settings, $defsettings) = @_;

	chomp (my $title = Sesse::pr0n::Templates::fetch_template($r, 'fullscreen'));

	my %newsettings = %$settings;
	$newsettings{'fullscreen'} = 1;

        $r->print("    <p>");
	Sesse::pr0n::Common::print_link($r, $title, "/$event/", \%newsettings, $defsettings);
	$r->print("</p>\n");
}

sub print_fullscreen_fromhere {
	my ($r, $event, $settings, $defsettings, $start) = @_;

	chomp (my $title = Sesse::pr0n::Templates::fetch_template($r, 'fullscreen-fromhere'));

	my %newsettings = %$settings;
	$newsettings{'fullscreen'} = 1;
	$newsettings{'start'} = $start;

        $r->print("    <span class=\"fsfromhere\">");
	Sesse::pr0n::Common::print_link($r, $title, "/$event/", \%newsettings, $defsettings);
	$r->print("</span>\n");
}
	
1;


