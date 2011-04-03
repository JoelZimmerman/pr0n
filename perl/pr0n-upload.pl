#! /usr/bin/perl

#
# Small multithreaded pr0n uploader, based partially on dave from HTTP::DAV.
# Use like
#
#   pr0n-upload.pl http://pr0n.sesse.net/webdav/upload/random/ *.JPG
#
# Adjust $threads to your own liking.
#

use strict;
use warnings;
use HTTP::DAV;
use threads;
use Thread::Queue;

my $threads = 16;
my $running_threads :shared = 0;
my $queue :shared = Thread::Queue->new;
my @succeeded :shared = ();
my @failed :shared = ();

# Enqueue all the images.
my $url = shift @ARGV;
$queue->enqueue(@ARGV);

# Fetch username and password, and check that they actually work.
my ($user, $pass) = get_credentials();
my $dav = init_dav($url, $user, $pass);

# Fire up the worker threads, and wait for them to finish.
my @threads = ();
for my $i (1..$threads) {
	push @threads, threads->create(\&upload_thread);
}
while ($running_threads > 0) {
	printf "%d threads running, %d images queued\n", $running_threads, $queue->pending;
	sleep 1;
}
for my $thread (@threads) {
	$thread->join();
}

if (scalar @failed != 0 && scalar @succeeded != 0) {
	# Output failed files in an easily-pastable format.
	print "\nFailed files: ", join(' ', @failed), "\n";
}

sub upload_thread {
	$running_threads++;

	my $dav = init_dav($url, $user, $pass);
	while (my $filename = $queue->dequeue_nb) {
		if ($dav->put(-local => $filename, -url => $url)) {
			push @succeeded, $filename;
		} else {
			push @failed, $filename;
			warn "Couldn't upload $filename: " . $dav->message . "\n";
		}
	}
	
	$running_threads--;
}

sub init_dav {
	my ($url, $user, $pass) = @_;
	my $ua = HTTP::DAV::UserAgent->new();
	$ua->agent('pr0n-uploader/v1.0 (perldav)');
	my $dav = HTTP::DAV->new(-useragent=>$ua);
	$dav->credentials(-user=>$user, -pass=>$pass, -url=>$url, -realm=>'pr0n.sesse.net');
	$dav->open(-url => $url)
		or die "Couldn't open $url: " . $dav->message . "\n";
	return $dav;
}

sub get_credentials {
	print "\nEnter username for $url: ";
	chomp (my $user = <STDIN>);
	exit if (!defined($user));
	print "Password: ";
	system("stty -echo");
	chomp (my $pass = <STDIN>);
	system("stty echo");
	print "\n";

	return ($user, $pass);
}
