# Note: This package is shared between server processes as much as we can,
#       for obvious reasons (you don't want just half the server to go in
#       overload mode if you can help it)

package Sesse::pr0n::Overload;
use strict;
use warnings;

BEGIN {
	use Exporter ();
	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

	$VERSION     = 1.00;
	@ISA         = qw(Exporter);
	@EXPORT      = qw();
	%EXPORT_TAGS = qw();
	@EXPORT_OK   = qw();
}
our ($last_update, $loadavg, $in_overload);

sub is_in_overload {
	my $r = shift;

	# Manually set overload mode
	if ($Sesse::pr0n::Config::overload_mode) {
		return 1;
	}

	# By default we are not in overload mode
	if (!defined($in_overload)) {
		$in_overload = 0;
	}

	my $enable_threshold = $Sesse::pr0n::Config::overload_enable_threshold // 10.0;
	my $disable_threshold = $Sesse::pr0n::Config::overload_disable_threshold // 5.0;
	
	# Check if our load average estimate is more than a minute old
	if (!defined($last_update) || (time - $last_update) > 60) {
		open LOADAVG, "</proc/loadavg"
			or die "/proc/loadavg: $!";
		my $line = <LOADAVG>;
		close LOADAVG;
		
		$line =~ /^(\d+\.\d+) / or die "Couldn't parse /proc/loadavg";
		
		$loadavg = $1;
		$last_update = time;

		if ($in_overload) {
			if ($loadavg < $disable_threshold) {
				Sesse::pr0n::Common::log_info($r, "Current load average is $loadavg (threshold: $disable_threshold), leaving overload mode");
				$in_overload = 0;
			} else {
				Sesse::pr0n::Common::log_warn($r, "Current load average is $loadavg (threshold: $disable_threshold), staying in overload mode");
			}
		} else {
			if ($loadavg > $enable_threshold) {
				Sesse::pr0n::Common::log_warn($r, "Current load average is $loadavg (threshold: $enable_threshold), entering overload mode");
				$in_overload = 1;
			} else {
				Sesse::pr0n::Common::log_info($r, "Current load average is $loadavg (threshold: $enable_threshold)");
			}
		}
	}

	return $in_overload;
}

1;

