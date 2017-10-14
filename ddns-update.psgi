#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper qw(Dumper);
$Data::Dumper::Sortkeys = 1;

use lib '.';
use conf;
use checks qw(check_params check_key check_method subdomain_exists valid_subdomain);
use util qw(rand_pass ip_record_type);
use database;
use routes::createsub;
use routes::modifysub;
use routes::deletesub;
use routes::locksub;
use routes::chgkey;
use routes::listsub;
use routes::help;
use routes::updatesub;
use routes::clearsub;

use DBI;
use Plack::Request;
use Net::DNS;

database::prepare_database();

my %routes = (
    "/create" => \&createsub::create_subdomain,
    "/modify" => \&modifysub::modify_subdomain,
    "/delete" => \&deletesub::delete_subdomain,
    "/lock" => \&locksub::lock_subdomain,
    "/chgkey" => \&chgkey::chgkey_subdomain,
    "/list" => \&listsub::list_subdomains,
    "/help" => \&help::get_help,
    "/update" => \&updatesub::update_ddns,
    "/clear" => \&clearsub::clear_ddns,
);

my $app_or_middleware = sub {
    my $env = shift; # PSGI env

    my $req = Plack::Request->new($env);

    my $path_info = $req->path_info;
    my $query     = $req->body_parameters;
    
    if (defined $routes{$path_info}) {
        return $routes{$path_info}($req);
    } else {
        my $res = $req->new_response(404, [], "Invalid URL.\n" .
            "For a full reference view /help or refer to the documentation.\n");
        return $res->finalize;
    }
};


