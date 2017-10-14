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
#use routes::modifysub;
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
    "/modify" => \&modify_subdomain,
    "/delete" => \&deletesub::delete_subdomain,
    "/lock" => \&locksub::lock_subdomain,
    "/chgkey" => \&chgkey::chgkey_subdomain,
    "/list" => \&listsub::list_subdomains,
    "/help" => \&help::get_help,
    "/update" => \&updatesub::update_ddns,
    "/clear" => \&clearsub::clear_ddns,
);

sub modify_subdomain {
    my $req = shift;
    
    my $c_method = check_method($req); if (defined $c_method) { return $c_method; }
    my $c_params = check_params($req, ("key", "subdomain", "ip")); if (defined $c_params) { return $c_params; }
    my $c_isvalid = valid_subdomain($req); if (defined $c_isvalid) { return $c_isvalid; }
    my @subdomain_r = subdomain_exists($req); my $c_subexists = @subdomain_r;
    if ($c_subexists == 1) { return $subdomain_r[0]->finalize; }
    my $c_key = check_key($req, $conf::admin_key); if (defined $c_key) { return $c_key; }
    
    my $subdomain = $req->body_parameters->get('subdomain');
    my $address   = $req->body_parameters->get('ip');
    my $ttl       = 2;
    my $rec_type  = ip_record_type($address);
    if (!defined $rec_type) {
        my $res = $req->new_response(400, [], "Invalid IP address specified.\n"); return $res->finalize;
    }

    my $dns_update = new Net::DNS::Update($conf::NAMESERVER_DNS_ZONE);
    $dns_update->push(update => rr_del("$subdomain.$conf::NAMESERVER_DNS_ZONE. $rec_type"));
    $dns_update->push(update => rr_add("$subdomain.$conf::NAMESERVER_DNS_ZONE. $ttl $rec_type $address"));
    $dns_update->sign_tsig($conf::NAMESERVER_DNSSEC_KEY);

    my ($r_code, $r_msg) = execute_ddns($dns_update);
    if (!$r_code) {
        my $res = $req->new_response(400, [], "Modfication failed.\n"); return $res->finalize;
    } else {
        my $time = time;
        if ($rec_type eq "A") {
            $database::DDNS_DB_UPD_ADR->execute($address, $subdomain_r[3], $time, $subdomain_r[0]);
        } elsif ($rec_type eq "AAAA") {
            $database::DDNS_DB_UPD_ADR->execute($subdomain_r[2], $address, $time, $subdomain_r[0]);
        }
        
        my $res = $req->new_response(200, [], "Modfication successful.\n"); return $res->finalize;
    }
}

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


