# Not related to Apache2::Registry; generates a .reg file for Windows XP to import.

package Sesse::pr0n::Registry;
use strict;
use warnings;

use Sesse::pr0n::Common qw(error dberror);
use Apache2::Request;

sub handler {
	my $r = shift;
	my $dbh = Sesse::pr0n::Common::get_dbh();
	my $vhost = $r->get_server_name;
	chomp (my $desc = Sesse::pr0n::Templates::fetch_template($r, 'wizard-description'));

	$r->content_type("application/octet-stream");
	$r->headers_out->add('Content-disposition' => 'attachment; filename="' . $vhost . '.reg"');

	$r->print("Windows Registry Editor Version 5.00\r\n\r\n");
	$r->print("[HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\Currentversion\\Explorer\\PublishingWizard\\PublishingWizard\\Providers\\$vhost]\r\n");
	$r->print("\"Icon\"=\"http://$vhost/pr0n.ico\"\r\n");
	$r->print("\"DisplayName\"=\"$vhost\"\r\n");
	$r->print("\"Description\"=\"$desc\"\r\n");
	$r->print("\"HREF\"=\"http://$vhost/wizard\"\r\n");

	return Apache2::Const::OK;
}
	
1;


