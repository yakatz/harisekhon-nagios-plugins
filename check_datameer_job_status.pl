#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-11-27 20:07:10 +0000 (Wed, 27 Nov 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

# http://documentation.datameer.com/documentation/display/DAS21/Accessing+Datameer+Using+the+REST+API

$DESCRIPTION = "Nagios Plugin to check the status of a specific Datameer job using the Rest API

Tested against Datameer 2.1.4.6 and 3.0.11";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use JSON::XS;
use LWP::UserAgent;

my $default_port = 8080;
$port = $default_port;

my $job_id;

%options = (
    "H|host=s"         => [ \$host,         "Datameer server" ],
    "P|port=s"         => [ \$port,         "Datameer port (default: $default_port)" ],
    "u|user=s"         => [ \$user,         "User to connect with (\$DATAMEER_USER)" ],
    "p|password=s"     => [ \$password,     "Password to connect with (\$DATAMEER_PASSWORD)" ],
    "j|job-id=s"       => [ \$job_id,       "Job Configuration Id (get this from the web UI)" ],
);

@usage_order = qw/host port user password job-id/;

env_creds("DATAMEER");

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);
$job_id     = validate_int($job_id, "job-id", 1, 100000);

my $url = "http://$host:$port/rest/job-configuration/job-status/$job_id";

vlog2;

my $ua = LWP::UserAgent->new;
$ua->agent("Hari Sekhon $progname $main::VERSION");
$ua->credentials($host, '', $user, $password);

# Lifted from check_cloudera_manager_metrics.pl TODO: move to lib
#my $content = get $url;
vlog2 "querying $url";
my $req = HTTP::Request->new('GET',$url);
$req->authorization_basic($user, $password);
my $response = $ua->request($req);
my $content  = $response->content;
chomp $content;
vlog3 "returned HTML:\n\n" . ( $content ? $content : "<blank>" ) . "\n";
vlog2 "http code: " . $response->code;
vlog2 "message: " . $response->message;

unless($response->code eq "200"){
    quit "UNKNOWN", $response->code . " " . $response->message;
}

my $json;
try{
    $json = decode_json $content;
};
catch{
    quit "CRITICAL", "invalid json returned by '$host:$port'";
};

foreach(qw/id jobStatus/){
    defined($json->{$_}) or quit "UNKNOWN", "$_ not returned for job $job_id in json from Datameer server. $nagios_plugins_support_msg";
}

$json->{"id"} == $job_id or quit "CRITICAL", "datameer server returned wrong job id!!";

my $job_status = $json{"jobStatus"};

my %job_state;
$job_state{"OK"}       = qw/RUNNING WAITING_FOR_OTHER_JOB COMPLETED/;
$job_state{"WARNING"}  = qw/COMPLETED_WITH_Warnings CANCELED CANCELLED/;
$job_state{"CRITICAL"} = qw/ERROR/;

$status = "UNKNOWN";
foreach my $state (qw/CRITICAL WARNING OK/){
    if(grep($job_status eq $_, @{$job_state{$state}})){
        $status = $state;
        last;
    }
}

$msg = "job $job_id state '" . lc $job_status . "'";

quit $status, $msg;
