package Wormhole::AppRouting;

use strict;
use warnings;

use Wormhole::Route::CreateSub;
use Wormhole::Route::ModifySub;
use Wormhole::Route::DeleteSub;
use Wormhole::Route::LockSub;
use Wormhole::Route::ChgKey;
use Wormhole::Route::ListSub;
use Wormhole::Route::Help;
use Wormhole::Route::UpdateSub;
use Wormhole::Route::ClearSub;

our %routes = (
    "/create" => \&Wormhole::Route::CreateSub::create_subdomain,
    "/modify" => \&Wormhole::Route::ModifySub::modify_subdomain,
    "/delete" => \&Wormhole::Route::DeleteSub::delete_subdomain,
    "/lock" => \&Wormhole::Route::LockSub::lock_subdomain,
    "/chgkey" => \&Wormhole::Route::ChgKey::chgkey_subdomain,
    "/list" => \&Wormhole::Route::ListSub::list_subdomains,
    "/help" => \&Wormhole::Route::Help::get_help,
    "/update" => \&Wormhole::Route::UpdateSub::update_ddns,
    "/clear" => \&Wormhole::Route::ClearSub::clear_ddns,
);

1;