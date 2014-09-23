package QVD::Admin4::REST::Response;
use strict;
use warnings;
use Moose;

has 'status',  is => 'ro', isa => 'Int', required => 1;
has 'result', is => 'ro', isa => 'HashRef', default => sub {{};};
has 'failures', is => 'ro', isa => 'HashRef', default => sub {{};};
has 'qvd_object_model', is => 'ro', isa => 'QVD::Admin4::REST::Model';

my $mapper =  Config::Properties->new();
$mapper->load(*DATA);

sub BUILD
{
    my $self = shift;
    
    $self->map_result_from_dbix_objects_to_output_info
	if $self->qvd_object_model;
    
    while (my ($id, $code) = each %{$self->failures})
    {
	$self->failures->{$id} = $self->message($code);
	$self->{status} = 1;
    }
}

sub map_result_from_dbix_objects_to_output_info
{
    my $self = shift;
    return unless defined $self->result->{rows};
    $_ = $self->map_dbix_object_to_output_info($_)
	for @{$self->result->{rows}};

    $self->map_result_to_list_of_ids
	if $self->qvd_object_model->type_of_action eq 'all_ids';
}

sub map_result_from_dbix_objects_to_output_info
{
    my ($self,$dbix_object) = @_;
    my $result = {};

    for my $field_key ($qvd_object_model->fields)
    {
	my $dbix_field_key = $qvd_object_model->map_field_to_dbix_format($field_key);
        my ($table,$column) = $dbix_field_key =~ /^(.+)\.(.+)$/;

	$result->{$field_key} = 
	    eval { $table eq "me" ? 
		       $obj->$column : 
		       $obj->$table->$column } // undef;
	print $@ if $@;
    }
}

sub map_result_to_list_of_ids
{
    my $self = shift;
    $self->result->{rows} = 
	[ map { $_->{id} } @{$self->result->{rows}} ];
}

sub message
{
    my $self = shift;
    my $status = shift // $self->status;
    $mapper->getProperty($status) || 
	'No translation to code '.$status.': ask Batman...';
}

sub json
{
    my $self = shift;
    
   { status  => $self->status,
     message => $self->message,
     result  => $self->result,
     failures  => $self->failures};
}

1;

__DATA__

0 = Successful completion.
1 = Undefined error.
2 = Unable to connect to database.
3 = Unable to log in in database.
4 = Internal server error.
5 = Action non supported.
6 = Unable to assign tenant to user: permissions problem.
7 = Unable to assign role to user: permissions problem.
8 = Forbidden action for this administrator.
9 = Inappropiate filter for this action.
10 = No mandatory filter for this action.
11 = Unknown filter for this action.
12 = Innapropiate argument for this action
13 = Unknown argument for this action.
14 = Unknown order element.
15 = Syntax errors in input json.
16 = Condition to delete violated.
17 = Condition to create violated.
18 = Imposible to change state in current state.
19 = Related arguments are not part of this tenant.
20 = Unknow role.
21 = Unknown acl
23503 = Foreign Key violation.
23502 = Lack of mandatory argument violation.
23505 = Unique Key violation.
23007 = Invalid type of argument.

