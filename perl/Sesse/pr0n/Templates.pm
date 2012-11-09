package Sesse::pr0n::Templates;
use strict;
use warnings;

use Sesse::pr0n::Common qw(error dberror);

BEGIN {
	use Exporter ();
	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

	$VERSION     = 1.00;
	@ISA         = qw(Exporter);
	@EXPORT      = qw();
	%EXPORT_TAGS = qw();
	@EXPORT_OK   = qw();
}
our %dirs = ();

sub update_dirs {
	my $r = shift;
	my $base = $r->dir_config('TemplateBase');
	
	for my $dir (<$base/*>) {
		next unless -d $dir;
		$dir =~ m#/([^/]+)$#;
		
		warn "Templates exist for '$1'";
		$dirs{$1} = {};
	}
}

sub r_to_dir {
	my $r = shift;

	if (scalar(keys %dirs) == 0) {
		update_dirs($r);
	}
	
	my $site = $r->get_server_name();
	if (defined($dirs{$site})) {
		return $site;
	} else {
		return "default";
	}
}

sub fetch_template {
	my ($r, $template) = @_;

	my $dir = r_to_dir($r);
	my $cache = $dirs{$dir}{$template};
	if (defined($cache) && time - $cache->{'time'} <= 300) {
		return $cache->{'contents'};
	}

	my $newcache = {};

	my $base = $r->dir_config('TemplateBase');
	open TEMPLATE, "<$base/$dir/$template"
		or ($dir ne 'default' and open TEMPLATE, "<$base/default/$template")
		or Sesse::pr0n::Common::error($r, "Couldn't open $dir/$template: $!");

	local $/;
	$newcache->{'contents'} = <TEMPLATE>;

	close TEMPLATE;

	$newcache->{'time'} = time;
	$dirs{$dir}{$template} = $newcache;
	return $newcache->{'contents'};
}

sub process_template {
	my ($r, $template, $args) = @_;
	my $text = fetch_template($r, $template);

	# do substitutions
	while (my ($key, $value) = each (%$args)) {
		$key = "%" . uc($key) . "%";
		$text =~ s/$key/$value/g;
	}

	return $text;
}

sub print_template {
	my ($r, $template, $args) = @_;
	$r->print(process_template($r, $template, $args));
}

1;

