package Wormhole;

use strict;
use warnings;

use Wormhole::Config;
use Wormhole::Util::Database qw(prepare_database);

use Wormhole::AppRouting;

use DBI;
use Plack::Request;
use Net::DNS;

prepare_database();

sub run_wormhole {
    my $env = shift; # PSGI env

    my $req = Plack::Request->new($env);

    my $path_info = $req->path_info;
    my $query     = $req->body_parameters;

    if (defined $Wormhole::AppRouting::routes{$path_info}) {
        return $Wormhole::AppRouting::routes{$path_info}($req);
    } else {
        my $res = $req->new_response(404, [], "Invalid URL.\n" .
            "For a full reference view /help or refer to the documentation.\n");
        return $res->finalize;
    }
};


