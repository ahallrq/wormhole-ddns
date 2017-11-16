package Wormhole::Util::Checks;
use strict;
use warnings;
 
use Exporter qw(import);
our @EXPORT_OK = qw(check_params check_key check_method subdomain_exists valid_subdomain);

use Wormhole::Util::Database;

sub check_params {
    my ($req, @param_list) = @_;
    
    my $query = $req->body_parameters;

    foreach my $param (@param_list) {
        my $tmp = $query->get($param);
        
        if (!defined $tmp) {
            my $res = $req->new_response(400, [], 
                    "One or more required parameters is missing from the request.\n" .
                    "Check the documentation for more informaion.\n");
            return $res->finalize;
        }
    }

    return undef;
}

sub check_key {
    my ($req, $valid_key) = @_;
    
    my $query     = $req->body_parameters;
    my $api_key   = $query->get('key');
    
    if ($api_key ne $valid_key) {
	    my $res = $req->new_response(403, [], 
            "An invalid key has been supplied and as a result access has been denied.\n");
	    return $res->finalize;
    }
    
    return undef;
}

sub check_method {
    my $req = shift;

    if ($req->method ne 'POST') {
        my $res = $req->new_response(405, [], "Only POST requests are supported.\n");
        return $res->finalize;
    }
    
    return undef;
}

sub subdomain_exists {
    my $req = shift;

    $Wormhole::Util::Database::DDNS_DB_SEL->execute($req->body_parameters->get('subdomain'));
    my @result = $Wormhole::Util::Database::DDNS_DB_SEL->fetchrow_array;
    if (!@result) {
        my @res = ($req->new_response(404, [], "The specified subdomain was not found.\n"));
        return @res;
    }
    
    return @result;
}

sub valid_subdomain {
    my $req = shift;

    my $subdomain = $req->body_parameters->get('subdomain');

    if ($subdomain !~ m/^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$/) {
        my $res = $req->new_response(400, [], 
                "Requested subdomain contains one or more invalid characters.\n" . 
                "Subdomains must consist of alphanumeric characters and hyphens." .
                "Furthermore they must not start or end with hyphens.\n");
        return $res->finalize;
    }
    
    return undef;
}

1;