#! /usr/bin/perl

#
# Small multithreaded pr0n uploader. Use like
#
#   pr0n-upload.pl http://pr0n.sesse.net/webdav/upload/random/ *.JPG
#
# Adjust $threads to your own liking.
#

use strict;
use warnings;
use LWP::UserAgent;
use threads;
use Thread::Queue;
use File::Spec;
use URI;

my $threads = 40;
my $running_threads :shared = 0;
my $queue :shared = Thread::Queue->new;
my @succeeded :shared = ();
my @failed :shared = ();

# Enqueue all the images.
my $url = shift @ARGV;
$url .= '/' if ($url !~ m#/$#);
$queue->enqueue(@ARGV);

# Fetch username and password, and check that they actually work.
my ($user, $pass) = get_credentials();
my $ua = init_ua($url, $user, $pass);

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

	my $ua = init_ua($url, $user, $pass);
	while (my $filename = $queue->dequeue_nb) {
		my (undef, undef, $basename) = File::Spec->splitpath($filename);
		my $newurl = $url . $basename;
		my $req = HTTP::Request->new(PUT => $newurl);
		{
			local $/ = undef;
			open my $fh, "<", $filename
				or die "Couldn't find $filename: $!";
			$req->content(<$fh>);
			close $fh;
		}

		my $res = $ua->request($req);
		if ($res->is_success) {
			push @succeeded, $filename;
		} else {
			push @failed, $filename;
			warn "Couldn't upload $filename: " . $res->message . "\n";
		}
	}
	
	$running_threads--;
}

sub init_ua {
	my ($url, $user, $pass) = @_;
	my $ua = LWP::UserAgent->new;
	$ua->agent('pr0n-uploader/v1.0');
	my $urlobj = URI->new($url);
	my $hostport = $urlobj->host . ':' . $urlobj->port;
	$ua->credentials($hostport, 'pr0n.sesse.net', $user, $pass);

	# Check that it works.
	my $req = HTTP::Request->new(PROPFIND => $url);
	my $res = $ua->request($req);
	die "$url: " . $res->status_line if (!$res->is_success);

	return $ua;
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
