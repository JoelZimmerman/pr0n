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

	# Find the event
	$r->uri =~ m#^/([a-zA-Z0-9-]+)/?$#
		or error($r, "Could not extract event");
	my $event = $1;

	# Fix common error: pr0n.sesse.net/event -> pr0n.sesse.net/event/
	if ($r->uri !~ m#/$#) {
		$r->headers_out->{'location'} = "/$event/";
		return Apache2::Const::REDIRECT;
	}

	# Internal? (Ugly?) 
	if ($r->get_server_name =~ /internal/) {
		my $user = Sesse::pr0n::Common::check_access($r);
		if (!defined($user)) {
			return Apache2::Const::OK;
		}
	}

	# Read the appropriate settings from the query string into the settings hash
	my %defsettings = (
		thumbxres => 80,
		thumbyres => 64,
		xres => undef,
		yres => undef,
		start => 1,
		num => -1,
		all => 1,
		infobox => 1,
		rot => 0,
		sel => 0,
		fullscreen => 0,
	);
	
	# Reduce the front page load when in overload mode.
	if (Sesse::pr0n::Overload::is_in_overload($r)) {
		$defsettings{'num'} = 100;
	}
		
	my %settings = %defsettings;

	for my $s qw(thumbxres thumbyres xres yres start num all infobox rot sel fullscreen) {
		my $val = $apr->param($s);
		if (defined($val) && $val =~ /^(\d+)$/) {
			$settings{$s} = $val;
		}
		if (($s eq "num" || $s eq "xres" || $s eq "yres") && defined($val) && $val == -1) {
			$settings{$s} = $val;
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

	if (defined($num) && $num == -1) {
		$num = undef;
	}

	my $ref = $dbh->selectrow_hashref('SELECT * FROM events WHERE id=? AND vhost=?',
		undef, $event, $r->get_server_name)
		or error($r, "Could not find event $event", 404, "File not found");

	my $name = $ref->{'name'};
	my $date = $ref->{'date'};
	
	# Count the number of selected images.
	$ref = $dbh->selectrow_hashref("SELECT COUNT(*) AS num_selected FROM images WHERE event=? AND selected=\'t\'", undef, $event);
	my $num_selected = $ref->{'num_selected'};

	# Find all images related to this event.
	my $q;
	my $where = ($all == 0) ? ' AND selected=\'t\'' : '';

	if (defined($start) && defined($num) && !$settings{'fullscreen'}) {
		$q = $dbh->prepare("SELECT *, (date - INTERVAL '6 hours')::date AS day FROM images WHERE event=? $where ORDER BY (date - INTERVAL '6 hours')::date,takenby,date,filename LIMIT $num OFFSET " . ($start-1))
			or dberror($r, "prepare()");
	} else {
		$q = $dbh->prepare("SELECT *, (date - INTERVAL '6 hours')::date AS day FROM images WHERE event=? $where ORDER BY (date - INTERVAL '6 hours')::date,takenby,date,filename")
			or dberror($r, "prepare()");
	}
	$q->execute($event)
		or dberror($r, "image enumeration");

	# Print the page itself
	if ($settings{'fullscreen'}) {
		$r->content_type("text/html; charset=utf-8");
		Sesse::pr0n::Templates::print_template($r, "fullscreen-header", { title => "$name [$event]" });
		while (my $ref = $q->fetchrow_hashref()) {
			$r->print("        \"" . $ref->{'filename'} . "\",\n");
		}

		my %settings_no_fullscreen = %settings;
		$settings_no_fullscreen{'fullscreen'} = 0;

		my $returnurl = "http://" . $r->get_server_name . "/" . $event . "/" .
			Sesse::pr0n::Common::get_query_string(\%settings_no_fullscreen, \%defsettings);

		# *whistle*
		$returnurl =~ s/&amp;/&/g;

		Sesse::pr0n::Templates::print_template($r, "fullscreen-footer", {
			vhost => $r->get_server_name,
			event => $event,
			start => $settings{'start'} - 1,
			returnurl => $returnurl
		});
	} else {
		Sesse::pr0n::Common::header($r, "$name [$event]");
		Sesse::pr0n::Templates::print_template($r, "date", { date => $date });

		if (Sesse::pr0n::Overload::is_in_overload($r)) {
			Sesse::pr0n::Templates::print_template($r, "overloadmode");
		}

		print_thumbsize($r, $event, \%settings, \%defsettings);
		print_viewres($r, $event, \%settings, \%defsettings);
		print_pagelimit($r, $event, \%settings, \%defsettings);
		print_infobox($r, $event, \%settings, \%defsettings);
		print_nextprev($r, $event, \%settings, \%defsettings);
		print_selected($r, $event, \%settings, \%defsettings) if ($num_selected > 0);

		my $toclose = 0;
		my $lastupl = "";
		
		# Print out all thumbnails
		if ($rot == 1) {
			$r->print("    <form method=\"post\" action=\"/rotate\">\n");
		
			while (my $ref = $q->fetchrow_hashref()) {
				my $imgsz = "";
				my $takenby = $ref->{'takenby'};
				if (defined($ref->{'day'})) {
					 $takenby .= ", " . $ref->{'day'};
				}

				if ($takenby ne $lastupl) {
					$lastupl = $takenby;
					Sesse::pr0n::Templates::print_template($r, "submittedby", { author => $lastupl });
				}
				if ($ref->{'width'} != -1 && $ref->{'height'} != -1) {
					my $width = $ref->{'width'};
					my $height = $ref->{'height'};
						
					($width, $height) = Sesse::pr0n::Common::scale_aspect($width, $height, $thumbxres, $thumbyres);
					$imgsz = " width=\"$width\" height=\"$height\"";
				}

				my $filename = $ref->{'filename'};
				my $uri = $filename;
				if (defined($xres) && defined($yres) && $xres != -1) {
					$uri = "${xres}x$yres/$infobox$filename";
				} elsif (defined($xres) && $xres == -1) {
					$uri = "original/$infobox$filename";
				}

				$r->print("    <p><a href=\"$uri\"><img src=\"${thumbxres}x${thumbyres}/$filename\" alt=\"\"$imgsz /></a>\n");
				$r->print("      90 <input type=\"checkbox\" name=\"rot-" .
					$ref->{'id'} . "-90\" />\n");
				$r->print("      180 <input type=\"checkbox\" name=\"rot-" .
					$ref->{'id'} . "-180\" />\n");
				$r->print("      270 <input type=\"checkbox\" name=\"rot-" .
					$ref->{'id'} . "-270\" />\n");
				$r->print("      &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;" .
					"&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Del <input type=\"checkbox\" name=\"del-" . $ref->{'id'} . "\" /></p>\n");
			}
			$r->print("      <input type=\"submit\" value=\"Rotate\" />\n");
			$r->print("    </form>\n");
		} elsif ($sel == 1) {
			$r->print("    <form method=\"post\" action=\"/select\">\n");
			$r->print("      <input type=\"hidden\" name=\"event\" value=\"$event\" />\n");
		
			while (my $ref = $q->fetchrow_hashref()) {
				my $imgsz = "";
				my $takenby = $ref->{'takenby'};
				if (defined($ref->{'day'})) {
					 $takenby .= ", " . $ref->{'day'};
				}

				if ($takenby ne $lastupl) {
					$lastupl = $takenby;
					Sesse::pr0n::Templates::print_template($r, "submittedby", { author => $lastupl });
				}
				if ($ref->{'width'} != -1 && $ref->{'height'} != -1) {
					my $width = $ref->{'width'};
					my $height = $ref->{'height'};
						
					($width, $height) = Sesse::pr0n::Common::scale_aspect($width, $height, $thumbxres, $thumbyres);
					$imgsz = " width=\"$width\" height=\"$height\"";
				}

				my $filename = $ref->{'filename'};
				my $uri = $filename;
				if (defined($xres) && defined($yres) && $xres != -1) {
					$uri = "${xres}x$yres/$infobox$filename";
				} elsif (defined($xres) && $xres == -1) {
					$uri = "original/$infobox$filename";
				}

				my $selected = $ref->{'selected'} ? ' checked="checked"' : '';

				$r->print("    <p><a href=\"$uri\"><img src=\"${thumbxres}x${thumbyres}/$filename\" alt=\"\"$imgsz /></a>\n");
				$r->print("      <input type=\"checkbox\" name=\"sel-" .
					$ref->{'id'} . "\"$selected /></p>\n");
			}
			$r->print("      <input type=\"submit\" value=\"Select\" />\n");
			$r->print("    </form>\n");
		} else {
			while (my $ref = $q->fetchrow_hashref()) {
				my $imgsz = "";
				my $takenby = $ref->{'takenby'};
				if (defined($ref->{'day'})) {
					 $takenby .= ", " . $ref->{'day'};
				}

				if ($takenby ne $lastupl) {
					$r->print("    </p>\n\n") if ($lastupl ne "");
					$lastupl = $takenby;
					Sesse::pr0n::Templates::print_template($r, "submittedby", { author => $lastupl });
					$r->print("    <p>\n");
				}
				if ($ref->{'width'} != -1 && $ref->{'height'} != -1) {
					my $width = $ref->{'width'};
					my $height = $ref->{'height'};
						
					($width, $height) = Sesse::pr0n::Common::scale_aspect($width, $height, $thumbxres, $thumbyres);
					$imgsz = " width=\"$width\" height=\"$height\"";
				}

				my $filename = $ref->{'filename'};
				my $uri = $filename;
				if (defined($xres) && defined($yres) && $xres != -1) {
					$uri = "${xres}x$yres/$infobox$filename";
				} elsif (defined($xres) && $xres == -1) {
					$uri = "original/$infobox$filename";
				}
				
				$r->print("      <a href=\"$uri\"><img src=\"${thumbxres}x${thumbyres}/$filename\" alt=\"\"$imgsz /></a>\n");
			}
			$r->print("    </p>\n");
		}

		print_nextprev($r, $event, \%settings, \%defsettings);
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
	my @alternatives = qw(320x256 512x384 640x480 800x600 1024x768 1280x960);
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
	my @alternatives = qw(10 50 100 500);
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
	my ($r, $event, $settings, $defsettings) = @_;
	my $start = $settings->{'start'};
	my $num = $settings->{'num'};
	my $dbh = Sesse::pr0n::Common::get_dbh();

	$num = undef if (defined($num) && $num == -1);
	return unless (defined($start) && defined($num));

	# determine total number
	my $ref = $dbh->selectrow_hashref('SELECT count(*) AS num_images FROM images WHERE event=?',
		undef, $event)
		or dberror($r, "image enumeration");
	my $num_images = $ref->{'num_images'};

	return if ($start == 1 && $start + $num >= $num_images);

	my $end = $start + $num - 1;
	if ($end > $num_images) {
		$end = $num_images;
	}

	$r->print("    <p>\n");

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
		Sesse::pr0n::Common::print_link($r, "$title ($newstart-$newend)\n", "/$event/", \%newsettings, $defsettings);
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
		Sesse::pr0n::Common::print_link($r, "$title ($newstart-$newend)", "/$event/", \%newsettings, $defsettings);
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
	
1;


