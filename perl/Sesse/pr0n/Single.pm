package Sesse::pr0n::Single;
use strict;
use warnings;

use Sesse::pr0n::Common;
use Sesse::pr0n::Index;
use Apache2::Request;
use POSIX;

sub handler {
	my $r = shift;
	my $apr = Apache2::Request->new($r);

	# Read the appropriate settings from the query string into the settings hash
        my %defsettings = (
                thumbxres => 80,
                thumbyres => 64,
                xres => undef,
                yres => undef,
                start => 1,
                num => undef,
                svurr => 0
        );
        my %settings = %defsettings;

	for my $s qw(thumbxres thumbyres xres yres svurr start num) {
		my $val = $apr->param($s);
		if (defined($val) && $val =~ /^(\d+)$/) {
			$settings{$s} = $val;
		}
	}

	my $thumbxres = $settings{'thumbxres'};
	my $thumbyres = $settings{'thumbyres'};
	my $xres = $settings{'xres'};
	my $yres = $settings{'yres'};
	my $start = $settings{'start'};
	my $num = $settings{'num'};

	# Print the page itself
	Sesse::pr0n::Common::header($r, "Singles");

	Sesse::pr0n::Index::print_thumbsize($r, 'single', \%settings, \%defsettings);
	Sesse::pr0n::Index::print_viewres($r, 'single', \%settings, \%defsettings);

	for my $id ($start..($start+$num)) { 
		my $filename = "$id.jpeg";
		my $uri = $filename;
		if (defined($xres) && defined($yres)) {
			$uri = "${xres}x$yres/$filename";
		}
		
		$r->print("      <a href=\"$uri\"><img src=\"${thumbxres}x${thumbyres}/$filename\" alt=\"\" /></a>\n");
	}
	$r->print("    </p>\n");

	Sesse::pr0n::Common::footer($r);

	return Apache2::Const::OK;
}

1;


