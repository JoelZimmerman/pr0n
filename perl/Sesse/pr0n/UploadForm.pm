# Shows the upload dialog.

package Sesse::pr0n::UploadForm;
use strict;
use warnings;

use Sesse::pr0n::Common qw(error dberror);

sub handler {
	my $r = shift;
	my $dbh = Sesse::pr0n::Common::get_dbh();

	# Fix common error: pr0n.sesse.net/upload/event -> pr0n.sesse.net/upload/event/
	if ($r->path_info !~ /\/$/) {
		my $res = Plack::Response->new(301);
		$res->header('Location' => $r->path_info . "/");
		return $res;
	}
	$r->path_info =~ /^\/upload\/([a-zA-Z0-9-]+)\/?$/
		or return error($r, "Could not extract event");
	my $event = $1;

	my $res = Plack::Response->new(200);
	$res->content_type("text/html; charset=utf-8");
	my $io = IO::String->new;

	chomp (my $title = Sesse::pr0n::Templates::fetch_template($r, 'upload-title'));
	Sesse::pr0n::Common::header($r, $io, $title);
	Sesse::pr0n::Templates::print_template($r, $io, 'upload', {
		event => $event
	});
	Sesse::pr0n::Common::footer($r, $io);

	$io->setpos(0);
	$res->body($io);
	return $res;
}
       
1;

