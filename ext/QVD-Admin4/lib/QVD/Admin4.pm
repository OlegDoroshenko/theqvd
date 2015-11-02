package QVD::Admin4;

use 5.010;
use strict;
use warnings;
use Moo;
use QVD::DB::Simple;
use QVD::Config;
use QVD::Config::Core;
use File::Copy qw(copy move);
use Config::Properties;
use QVD::Admin4::Exception;
use DateTime;
use List::Util qw(sum);
use File::Basename qw(basename dirname);
use QVD::Admin4::REST::Model;
use QVD::Admin4::REST::Request;
use DBIx::Error;
use TryCatch;
use Data::Page;
use Clone qw(clone);
use QVD::Admin4::AclsOverwriteList;
use QVD::Admin4::ConfigsOverwriteList;
use Mojo::JSON qw(encode_json);

our $VERSION = '0.01';

# This class is a store with the functions intended to properly
# execute the actions asked to the API.

my $DB;

#########################
## STARTING THE OBJECT ##
#########################

sub BUILD
{
    my $self = shift;

    $DB = eval { db() };
    QVD::Admin4::Exception->throw(code=>'2100') if $@;

# 'exception_action' is the function that is executed when 
# the database throws an error. With this setting, DBIx::Error 
# exceptions will be thrown.

    $DB->exception_action( DBIx::Error->exception_action );
}

sub _db { $DB; }

#####################
### GENERIC FUNCTIONS
#####################

# The majority of actions in the API will be executed by means of these generic functions

# FOR REGULAR VISUALIZATION ACTIONS

sub select
{
    my ($self,$request) = @_;

    my @rows;
    my $rs;

    eval { $rs = $DB->resultset($request->table)->search($request->filters,$request->modifiers);
	   @rows = $rs->all };

    QVD::Admin4::Exception->throw(exception => $@, query => 'select') if $@;

    { total => ($rs->is_paged ? $rs->pager->total_entries : $rs->count), 
      rows => \@rows,
      extra => $self->get_extra_info_from_related_views($request) }; # Extra info about objects retrieved from database
}                                                                    # is stored in here. This info has been retrieved
                                                                     # by a second request to database

# Some objects in QVD have some kind of heavy info that cannot be retrieved directly 
# in the main request to the database. For example, properties and other objects related
# to the main object in a 1 to many relation cannot be retrieved in a single step from 
# the database with the prefeatch feature. So they are retieved in an extra  

sub get_extra_info_from_related_views
{
    my ($self,$request) = @_;
    my $extra = {};
    
    my $view_name = $request->related_view;
    return $extra unless $view_name;

    my $vrs = $DB->resultset($view_name)->search();
    $extra->{$_->id} = $_ for $vrs->all;
    $extra;
}

# Ad hoc function for tenant_view_get_list action of API 

sub tenant_view_get_list
{
    my ($self,$request) = @_;

    my @rows;
    my $rs;

# The table provided by $request is supposed to be a view
# In DBIx::Class, views don't accept filters directly. But you can 
# compose queries by adding 'search' methods in a recursive way.
# So, in this case, filters are added in a second 'search' call

    eval { $rs = $DB->resultset($request->table)->search()->search(
	       $request->filters,$request->modifiers);
	   @rows = $rs->all };

    QVD::Admin4::Exception->throw(exception => $@, query => 'select') if $@;

    { total => ($rs->is_paged ? $rs->pager->total_entries : $rs->count), 
      rows => \@rows};
}

# Ad hoc function for acl_get_list action of API

sub acl_get_list
{
    my ($self,$request) = @_;
    my (@rows, $rs);

# The table provided by $request is supposed to be a view
# In DBIx::Class, views don't accept filters directly. But you can 
# compose queries by adding 'search' methods in a recursive way.
# So, in this case, filters are added in a second 'search' call

# This view needs to bind three placeholders. The values of the 
# placeholders must be regular expresions that define lists of 
# acls forbidden, allowed or hidden for the current administrator. 
# Those lists of acls are the acls that should be overwritten 
# over the regular assignation of acls for the administrator.

    my $admin = $request->get_parameter_value('administrator');
    my $aol = QVD::Admin4::AclsOverwriteList->new(admin_id => $admin->id);
    my $bind = [$aol->acls_to_close_re,$aol->acls_to_open_re,$aol->acls_to_hide_re];

    eval { $rs = $DB->resultset($request->table)->search({},{bind => $bind})->search(
	       $request->filters, $request->modifiers);
	   @rows = $rs->all };
    QVD::Admin4::Exception->throw(exception => $@, query => 'select') if $@;

    { total => ($rs->is_paged ? $rs->pager->total_entries : $rs->count), 
      rows => \@rows};
}

# Ad hoc function for get_acls_in_admins action of API

sub get_acls_in_admins
{
    my ($self,$request) = @_;
    my (@rows, $rs);

# The table provided by $request is supposed to be a view
# In DBIx::Class, views don't accept filters directly. But you can 
# compose queries by adding 'search' methods in a recursive way.
# So, in this case, filters are added in a second 'search' call

# This view needs to bind three placeholders. The values of the 
# placeholders must be regular expresions that define lists of 
# acls forbidden, allowed or hidden for the current administrator. 
# Those lists of acls are the acls that should be overwritten 
# over the regular assignation of acls for the administrator.

    my $admin_id = $request->json_wrapper->get_filter_value('admin_id')
	// $request->get_parameter_value('administrator')->id;

    my $aol = QVD::Admin4::AclsOverwriteList->new(admin_id => $admin_id);
    my $bind = [$aol->acls_to_close_re,$aol->acls_to_open_re,$aol->acls_to_hide_re];

    eval { $rs = $DB->resultset($request->table)->search({},{bind => $bind})->search(
	       $request->filters, $request->modifiers);
	   @rows = $rs->all };
    QVD::Admin4::Exception->throw(exception => $@, query => 'select') if $@;

    { total => ($rs->is_paged ? $rs->pager->total_entries : $rs->count), 
      rows => \@rows};
}

# Ad hoc function for get_acls_in_roles action of API

sub get_acls_in_roles
{
    my ($self,$request) = @_;
    my (@rows, $rs);

    my $admin = $request->get_parameter_value('administrator');
    my $aol = QVD::Admin4::AclsOverwriteList->new(admin => $admin, admin_id => $admin->id);
    my $bind = [$aol->acls_to_close_re,$aol->acls_to_hide_re];

# The table provided by $request is supposed to be a view
# In DBIx::Class, views don't accept filters directly. But you can 
# compose queries by adding 'search' methods in a recursive way.
# So, in this case, filters are added in a second 'search' call

# This view needs to bind two placeholders. The values of the 
# placeholders must be regular expresions that define lists of 
# acls forbidden or hidden for the current administrator. 
# Those lists of acls are the acls that should be overwritten 
# over the regular assignation of acls for the administrator.

    eval { $rs = $DB->resultset($request->table)->search({},{bind => $bind})->search(
	       $request->filters, $request->modifiers);
	   @rows = $rs->all };
    QVD::Admin4::Exception->throw(exception => $@, query => 'select') if $@;

    { total => ($rs->is_paged ? $rs->pager->total_entries : $rs->count), 
      rows => \@rows};
}

# FOR REGULAR UPDATE ACTIONS

sub update
{
    my ($self,$request,%modifiers) = @_;
    my $result = $self->select($request);
    QVD::Admin4::Exception->throw(code => 1300) unless $result->{total};
    my $conditions = $modifiers{conditions} // [];

    my $failures;
    for my $obj (@{$result->{rows}})
    {
	eval { $DB->txn_do( sub { $self->$_($obj) for @$conditions;
				  # Update the main object
				  $obj->update($request->arguments);                 
                                  # Update tables related to the main object (i.e. vm_runtimes for vms)
				  $self->update_related_objects($request,$obj);      
                                  # Assign and unassign other objects to the main objects (i.e. tags for dis, acls for roles, properties for vms...)
				  $self->exec_nested_queries($request,$obj); } ) };  
	$failures->{$obj->id} = QVD::Admin4::Exception->new(exception => $@, query => 'update')->json if $@; 

	$self->report_in_log($request,$obj,$failures && exists $failures->{$obj->id} ? $failures->{$obj->id}->{status} : 0);
    }

    QVD::Admin4::Exception->throw(failures => $failures) 
	if defined $failures; 
    $result->{rows} = [];
    $result;
}

sub update_related_objects
{
    my($self,$request,$obj)=@_;

    my %tables = %{$request->related_objects_arguments};
    for (keys %tables)
    {
	$obj->$_->update($tables{$_}); 
    }    
}

# FOR REGULAR DELETE ACTIONS

sub delete
{
    my ($self,$request,%modifiers) = @_;
    my $result = $self->select($request);
    QVD::Admin4::Exception->throw(code => 1300) unless $result->{total};

    my $conditions = $modifiers{conditions} // [];
    my $failures;
    for my $obj (@{$result->{rows}})
    {
	eval { $self->$_($obj) for @$conditions; 
	       $obj->delete;};

	$failures->{$obj->id} = QVD::Admin4::Exception->new(exception => $@,query => 'delete')->json if $@;
    	$self->report_in_log($request,$obj,$failures && exists $failures->{$obj->id} ? $failures->{$obj->id}->{status} : 0);
    }
    QVD::Admin4::Exception->throw(failures => $failures) 
	if defined $failures; 

    $result->{rows} = [];
    $result;
}

# Ad hoc function to vm_delete action of API

sub vm_delete
{
    my ($self,$request) = @_;

    $self->delete($request,conditions => [qw(vm_is_stopped)]);
}

# Ad hoc function to di_delete action of API

sub di_delete {
    my ($self, $request) = @_;

    $self->delete($request,conditions => [qw(di_no_vm_runtimes 
                                             di_no_dependant_vms
                                             di_no_head_default_tags
                                             di_delete_disk_image)]);
}

# It deletes config tokens in the database only when tokens
# are custom tokens (they are present neither in Defaults.pm nor in config files) 
 
sub config_delete
{
    my ($self,$request) = @_;

	# Raise an exception if admin cannot delete config
	$self->is_admin_allowed_to_config($request);

    my $result = $self->delete($request, conditions => [qw(is_not_custom_config)]);

    QVD::Config::reload(); # To refresh config tokens in QVD::Config 
    $result;
}

# It deletes config tokens in the database only when tokens
# are not custom tokens (they are present either in Defaults.pm or in config files) 

sub config_default
{
    my ($self,$request) = @_;

	# Raise an exception if admin cannot modify config
	$self->is_admin_allowed_to_config($request);

    my $result = $self->delete($request, conditions => [qw(is_custom_config)]);

    QVD::Config::reload(); # To refresh config tokens in QVD::Config 
    $result;
}


# FOR REGULAR CREATE ACTIONS

sub create
{
    my ($self,$request,%modifiers) = @_;
    my $result;
    my $conditions = $modifiers{conditions} // [];
    my $obj;
    eval 
    {
		$DB->txn_do(
			sub {
				$self->$_($request) for @$conditions;
			   $obj = $DB->resultset($request->table)->create($request->arguments); 
                           # Create tables related to the main object (i.e. vm_runtimes for vms)
			   $self->create_related_objects($request,$obj);
                           # Assign and unassign other objects to the main objects (i.e. tags for dis, acls for roles, properties for vms...)
			   $self->exec_nested_queries($request,$obj);
				$result->{rows} = [ $obj ]
			}
		)
    };
    
    print $@ if $@;
    my $e = $@ ? QVD::Admin4::Exception->new(exception => $@, query => 'create') : undef;
    $self->report_in_log($request,$obj, $e ? $e->code : 0);

    $e->throw if $e;
    $result->{total} = 1;
    $result->{extra} = {};
    
    $result;
}

sub create_related_objects
{
    my ($self,$request,$obj) = @_;
    my $related_args = $request->related_objects_arguments;

    for my $table ($request->dependencies)
    {
	$obj->create_related($table,($related_args->{$table} || {}));
    }
}

# Ad hoc function to di_create action of API

sub di_create
{
    my ($self,$request) = @_;

    my $result = $self->create($request);
    my $di = @{$result->{rows}}[0];

    eval
    {
	$di->osf->delete_tag('head');
	$di->osf->delete_tag($di->version);
	$DB->resultset('DI_Tag')->create({di_id => $di->id, tag => $di->version, fixed => 1});
	$DB->resultset('DI_Tag')->create({di_id => $di->id, tag => 'head'});
	$DB->resultset('DI_Tag')->create({di_id => $di->id, tag => 'default'})
	    unless $di->osf->di_by_tag('default');
    };

    QVD::Admin4::Exception->throw(exception => $@,
				  query => 'tags') if $@;

    $di->update({path => $di->id . '-' . $di->path});
    
    $result;
}

# FOR SETTING OF CONFIG TOKENS AND CONFIG VIEWS
# QVD configuration tokens and WAT views are created/updated
# by means of this action 

sub create_or_update
{
    my ($self,$request) = @_;
    my $result;
    my $obj;
    for (1 .. 20) # FIX ME!!! This is to avoid problems with concurrent updates
    {             # For some reason, it happens sometimes in the test with this function 
	eval
	{
	    $DB->txn_do( sub { $obj = $DB->resultset($request->table)->update_or_create($request->arguments);
			       $result->{rows} = [ $obj ] } )
	};
    
	last unless $@;
    }

    my $e = $@ ? QVD::Admin4::Exception->new(exception => $@, query => 'set') : undef;

    $self->report_in_log($request,$obj, $e ? $e->code : 0);
    $e->throw if $e;

    $result->{total} = 1;
    $result->{extra} = {};
    $result;
}

sub config_set
{
    my ($self,$request) = @_;

	# Raise an exception if admin cannot modify config
	$self->is_admin_allowed_to_config($request);

	# Modify parameter if no exception is raised
    my $result = $self->create_or_update($request);

    QVD::Config::reload(); # To refresh config tokens in QVD::Config 
	return $result;
}

# FOR EXECUTION OF VMs

sub vm_user_disconnect
{
    my ($self,$request) = @_;
    my $result = $self->select($request);

    my $failures;
    for my $vm (@{$result->{rows}})
    {
	eval { $vm->vm_runtime->send_user_abort  };   
	
	$failures->{$vm->id} = QVD::Admin4::Exception->new(
	    code => 5110, object => $vm->vm_runtime->user_state)->json if $@; 

	$self->report_in_log($request,$vm,$failures && exists $failures->{$vm->id} ? $failures->{$vm->id}->{status} : 0);
    }
    QVD::Admin4::Exception->throw(failures => $failures) 
	if defined $failures;  

    $result->{rows} = [];
    $result;
}

sub vm_start
{
    my ($self,$request) = @_;

    my $result = $self->select($request);
    my ($failures, %host);

    for my $vm (@{$result->{rows}})
    {
	for (1 .. 5) { eval { $DB->txn_do( sub {

		  $vm->vm_runtime->can_send_vm_cmd('start')  ||
		  QVD::Admin4::Exception->throw(code => 5130, 
					      object => $vm->vm_runtime->vm_state);
		  $self->vm_assign_host($vm->vm_runtime);
		  $vm->vm_runtime->send_vm_start;
		  $host{$vm->vm_runtime->host_id}++;}

				  ) }; $@ or last; } 

	$failures->{$vm->id} = QVD::Admin4::Exception->new(exception => $@)->json if $@; 
	$self->report_in_log($request,$vm,$failures && exists $failures->{$vm->id} ? $failures->{$vm->id}->{status} : 0);
    }

    notify("qvd_admin4_vm_start");
    notify("qvd_cmd_for_vm_on_host$_") for keys %host;
    QVD::Admin4::Exception->throw(failures => $failures) 
	if defined $failures;  

    $result->{rows} = [];
    $result;
}

sub vm_stop
{
    my ($self,$request) = @_;

    my $result = $self->select($request);
    my ($failures, %host);

    for my $vm (@{$result->{rows}})
    {
	for (1 .. 5) { eval { $DB->txn_do( sub {

		  $vm->vm_runtime->send_vm_stop;
		  $host{$vm->vm_runtime->host_id}++; }

				  ) }; $@ or last; } 
       
	$failures->{$vm->id} = QVD::Admin4::Exception->new(
	    code => 5120, object => $vm->vm_runtime->vm_state)->json if $@; 
	$self->report_in_log($request,$vm,$failures && exists $failures->{$vm->id} ? $failures->{$vm->id}->{status} : 0);
	$vm->vm_runtime->update({ vm_cmd => undef })
	    if $vm->vm_runtime->vm_state eq 'stopped' &&
	    $vm->vm_runtime->vm_cmd                   &&
	    $vm->vm_runtime->vm_cmd eq 'start'; 
    }

    notify("qvd_admin4_vm_stop");
    notify("qvd_cmd_for_vm_on_host$_") for keys %host;
    QVD::Admin4::Exception->throw(failures => $failures) 
	if defined $failures;  

    $result->{rows} = [];
    $result;
}

####################
# To report in log #
####################

sub report_in_log
{
   my ($self,$request,$obj,$status) = @_; 

   my $arguments = eval { $request->json_wrapper->original_request->{arguments} } // {};
   my $qvd_object = $request->qvd_object_model->qvd_object_log_style;
   my $type_of_action = $request->qvd_object_model->type_of_action_log_style;

   if ($qvd_object eq 'config' && $type_of_action eq 'delete')
   {
       @{$arguments}{qw(key value)} = ($obj->key,$obj->value);
   }

   if ($qvd_object =~ /^(tenant|admin)_view$/ && $type_of_action eq 'delete')
   {
       @{$arguments}{qw(field visible view_type device_type qvd_object property)} = 
	   ($obj->field, $obj->visible, $obj->view_type, $obj->device_type, 
	    $obj->qvd_object, $obj->property);
   }

   my $admin = $request->get_parameter_value('administrator');

   QVD::Admin4::LogReport->new(

       action => { action => $request->json_wrapper->action,
		   type_of_action => $type_of_action },
       qvd_object => $qvd_object,
       tenant => eval { $obj->tenant } // $admin->tenant,
       object => $obj,
       administrator => $admin,
       ip => $request->get_parameter_value('remote_address'),
       source => $request->get_parameter_value('source'),
       arguments => $arguments,
       status => $status 

       )->report;
}

#########################
##### NESTED QUERIES ####
#########################

# Creation and update functions trigger this method intended to assign
# or unassign to one QVD object other related objects:
# a) Assignation of custom properties to VMs, Users, Hosts, OSFs and DIs  
# b) Assignation of tags to DIs
# c) Assignation of roles to other roles or administrators
# d) Assignation of acls to roles

sub exec_nested_queries
{
    my($self,$request,$obj)=@_;

    my %nq = %{$request->nested_queries}; 
    for (keys %nq) #This is supposed to be a list of functions in this class
    {
	$self->$_($nq{$_},$obj); 
    }    
}


# ASSIGNATION OF CUSTOM PROPERTIES TO VMs, Users, etc.

sub custom_properties_set
{
    my ($self,$props,$obj) = @_;

    my $class = ref($obj);     # FIX ME.  Can be improved the identification of the class?
    $class =~ s/^QVD::DB::Result::(.+)$/$1/;

    while (my ($key,$value) = each %$props)
    { 
	$key = undef if defined $key && $key eq ''; 
    
	my $t = $class . "_Property";
	my $k = lc($class) . "_id";
	my $a = {property_id => $key, value => $value, $k => $obj->id};

	eval { $DB->resultset($t)->update_or_create($a) };
	QVD::Admin4::Exception->throw(exception => $@, 
				      query => 'properties') if $@;
    }
}

sub custom_properties_del
{
    my ($self,$props,$obj) = @_;

    for my $key (@$props)
    {
	$key = undef if defined $key && $key eq '';
	eval { $obj->search_related('properties', 
				    {key => $key})->delete_all };
	QVD::Admin4::Exception->throw(exception => $@, 
				      query => 'properties') if $@;	
    }
}

# ASSIGNATION OF TAGS TO DIs.

sub tags_create
{
    my ($self,$tags,$di) = @_;

    for my $tag (@$tags)
    { 	
	$tag = undef if defined $tag && $tag eq '';	
	eval
	{
	    my $old_tag = $DB->resultset('DI_Tag')->search({'me.tag' => $tag,
							    'osf.id' => $di->osf_id},
							   {join => [{ di => 'osf' }]})->first;
	    $old_tag->fixed ? 
		QVD::Admin4::Exception->throw(code => 7330) : 
		$old_tag->delete if $old_tag;

	    $DB->resultset('DI_Tag')->create({di_id => $di->id, tag => $tag});
	};

	QVD::Admin4::Exception->throw(exception => $@, 
				      query => 'tags') if $@;
    }
}

sub tags_delete
{
    my ($self,$tags,$di) = @_;

    for my $tag (@$tags)
    {
	$tag = undef if defined $tag && $tag eq ''; # FIX ME
	$tag = $di->search_related('tags',{tag => $tag})->first // next;	    
	eval 
	{ 
	    ($tag->fixed || $tag->tag eq 'head' || $tag->tag eq 'default') 
		&& QVD::Admin4::Exception->throw(code => 7340);
	    $tag->delete;
	};
	
	QVD::Admin4::Exception->throw(exception => $@, 
				      query => 'tags') if $@;
    }
}

# ASSIGNATION OF ROLES AND ACLS.

sub add_acls_to_role
{
    my ($self,$acls,$role) = @_;

# The API supports identification of acls both by name and by id
# But the function must operate with names. Here the switch is done if needed

    my $acl_names = $self->as_ids($acls,'acls') ? 
	$self->switch_ids_to_names('ACL',$acls) : $acls;

    for my $acl_name (@$acl_names)
    { 	
	$acl_name = undef if defined $acl_name && $acl_name eq '';

	next if $role->is_allowed_to($acl_name); # To avoid redundant assignation
	$role->has_own_negative_acl($acl_name) ?
	    $self->unassign_acl_to_role($role,$acl_name) : # Deletion of negative acl in order 
                                                           # to avoid the inhibition of the acl

	    $self->assign_acl_to_role($role,$acl_name,1);  # Direct assignation of the acl
    }
}

sub del_acls_to_role
{
    my ($self,$acls,$role) = @_;

# The API supports identification of acls both by name and by id
# But the function must operate with names. Here the switch is done if needed

    my $acl_names = $self->as_ids($acls,'acls') ? 
	$self->switch_ids_to_names('ACL',$acls) : $acls;

    for my $acl_name (@$acl_names)
    { 	
	$acl_name = undef if defined $acl_name && $acl_name eq '';
	next unless $role->is_allowed_to($acl_name);
	
	# If the acl has been directly assigned, it is directly deleted

	if ($role->has_own_positive_acl($acl_name)) 
	{
	    $self->unassign_acl_to_role($role,$acl_name);
	}

	# If the acl has been inherited, it is inhibited by means of a negative acls

	if ($role->has_inherited_acl($acl_name))
	{
	    $self->assign_acl_to_role($role,$acl_name,0);
	}
    }
}

sub add_roles_to_role
{
    my ($self,$roles_to_assign,$this_role) = @_;

# The API supports identification of roles both by name and by id
# But the function must operate with names. Here the switch is done if needed

    my $roles_ids = $self->as_ids($roles_to_assign,'roles') ? 
	$roles_to_assign : $self->switch_names_to_ids('Role',$roles_to_assign);

    for my $role_to_assign_id (@$roles_ids)
    {
	$role_to_assign_id = undef if defined $role_to_assign_id && $role_to_assign_id eq '';
	$self->assign_role_to_role($this_role,$role_to_assign_id);
	my $nested_role;
	
	# Deletion of redundant acls after assignation of the new role

	for my $own_acl_name ($this_role->get_negative_own_acl_names,
			      $this_role->get_positive_own_acl_names)
	{
	    $nested_role //= $DB->resultset('Role')->find({id => $role_to_assign_id});
	    $self->unassign_acl_to_role($this_role,$own_acl_name) 
		if $nested_role->is_allowed_to($own_acl_name);
	}
    }
}

sub del_roles_to_role
{
    my ($self,$roles_to_unassign,$this_role) = @_;

# The API supports identification of roles both by name and by id
# But the function must operate with names. Here the switch is done if needed

    my $roles_ids = $self->as_ids($roles_to_unassign,'roles') ? 
	$roles_to_unassign : $self->switch_names_to_ids('Role',$roles_to_unassign);

    for my $id (@$roles_ids)
    {
	$id = undef if defined $id && $id eq '';
	$self->unassign_role_to_role($this_role,$id) 
    }

    # This is a reload of the object needed after deletion of roles
    # in order to refresh the info in the 'has_inherited_acl' method of Role.
    # There must be a better solution... FIX ME
    # Maybe the reload could be triggered from the oibject itself
    # always has_inherited_acl and other similar methods are executed
    # That cpuld be more elegant, but it may involve performance issues

#    $this_role->discard_changes;

    # Deletion of redundant acls after assignation of the new role
    for my $neg_acl_name ($this_role->get_negative_own_acl_names)
    {
	$self->unassign_acl_to_role($this_role,$neg_acl_name) 
	    unless $this_role->has_inherited_acl($neg_acl_name);
    }
}

# Check if acls or roles have been identified by id or name

sub as_ids
{
    my ($self,$ids_or_names,$qvd_object) = @_;
    my ($as_ids_flag, $as_names_flag) = (0,0);
  
    $_ =~ /^[0-9]+$/ ? $as_ids_flag = 1 : $as_names_flag = 1 for @$ids_or_names;
    QVD::Admin4::Exception->throw(code => 6360, query => $qvd_object) 
	if $as_ids_flag && $as_names_flag;
    $as_ids_flag;
}

sub switch_ids_to_names
{
    my ($self,$table,$ids) = @_;
    [ map { $_->name }  $DB->resultset($table)->search({id => $ids})->all ]
}

sub switch_names_to_ids
{
    my ($self,$table,$names) = @_;
    [ map { $_->id }  $DB->resultset($table)->search({name => $names})->all ]
}


sub assign_acl_to_role
{
    my ($self,$role,$acl_name,$positive) = @_;

    eval
    {
	my $acl = $DB->resultset('ACL')->find({name => $acl_name})
	    // QVD::Admin4::Exception->throw(code => 6360);

	$role->create_related('acl_rels', { acl_id => $acl->id,
					    positive => $positive });
    };
    QVD::Admin4::Exception->throw(exception => $@, 
				  query => 'acls') if $@;
}

sub unassign_acl_to_role
{
    my ($self,$role,$acl_name) = @_;

    eval
    {
	my $acl = $DB->resultset('ACL')->find({name => $acl_name})
	    // QVD::Admin4::Exception->throw(code => 6360);

	$role->search_related('acl_rels', { acl_id => $acl->id })->delete_all;
    };
    QVD::Admin4::Exception->throw(exception => $@, 
				  query => 'acls') if $@;
}

sub assign_role_to_role
{
    my ($self,$inheritor_role,$inherited_role_id) = @_;

    eval
    { 
	my $inherited_role = $DB->resultset('Role')->find({id => $inherited_role_id})
	    // QVD::Admin4::Exception->throw(code => 6370);

        # In order to avoid circular inheritance
    
	$inheritor_role->id eq $_ && QVD::Admin4::Exception->throw(code => 7350)
	    for ($inherited_role->id, $inherited_role->get_all_inherited_role_ids);

	$inheritor_role->create_related('role_rels', { inherited_id => $inherited_role_id });
    };
    QVD::Admin4::Exception->throw(exception => $@, 
				  query => 'roles') if $@;
}

sub unassign_role_to_role
{
    my ($self,$role,$role_ids) = @_;

    eval { $role->search_related('role_rels', { inherited_id => $role_ids })->delete_all };

    QVD::Admin4::Exception->throw(exception => $@, 
				  query => 'roles') if $@;
}

sub del_roles_to_admin
{
    my ($self,$role_ids,$admin) = @_;

    my $ids = $self->as_ids($role_ids,'roles') ? 
	$role_ids : $self->switch_names_to_ids('Role',$role_ids);

    eval { $DB->resultset('Role_Administrator_Relation')->search(
	       {role_id => $ids,
		administrator_id => $admin->id})->delete_all };
    QVD::Admin4::Exception->throw(exception => $@, 
				  query => 'roles') if $@;
}

sub add_roles_to_admin
{
    my ($self,$role_ids,$admin) = @_;

    my $ids = $self->as_ids($role_ids,'roles') ? 
	$role_ids : $self->switch_names_to_ids('Role',$role_ids);

    for my $role_id (@$ids)
    {
	eval
	{
	    my $role = $DB->resultset('Role')->search({id => $role_id})->first
		// QVD::Admin4::Exception->throw(code => 6370);

	    $role->create_related('admin_rels', 
				  { administrator_id => $admin->id });
	};

	QVD::Admin4::Exception->throw(exception => $@, 
				      query => 'roles') if $@;
    }
}

#############################################################################
### CONDITIONS TO THE EXECUTION OF GENERAL UPDATE/CREATE/DELETE FUNCTIONS ###
#############################################################################

# Same of the main functions in this class (update, create and delete) accept
# a list of conditions as argument. These conditions are checked for all objects
# that may be updated/created/deleted. For every object, the action is executed 
# only if all the conditions are true for them.

my $lb;

# It assigns a host to the vm that has been asked to start

sub vm_assign_host {
    my ($self, $vmrt) = @_;
    if (!defined $vmrt->host_id) {
        $lb //= do {
            require QVD::L7R::LoadBalancer;
            QVD::L7R::LoadBalancer->new();
        };
        my $free_host = eval { $lb->get_free_host($vmrt->vm) } //
	    QVD::Admin4::Exception->throw(code => 5140);

        $vmrt->set_host_id($free_host);
    }
}

# It dies unless the vm is stopped

sub vm_is_stopped
{
    my ($self,$vm) = @_;
    QVD::Admin4::Exception->throw(code => 7310, query => 'delete') 
	unless $vm->vm_runtime->vm_state eq 'stopped';
}

# It dies if the di has vm runtimes

sub di_no_vm_runtimes
{
    my ($self,$di) = @_;
    QVD::Admin4::Exception->throw(code => 7320, query => 'delete') 
	unless $di->vm_runtimes->count == 0;
}

# It dies if the di has related vms  

sub di_no_dependant_vms
{
    my ($self,$di) = @_;
    my $rs = $DB->resultset('VM')->search({'di.id' => $di->id }, 
					  { join => [qw(di)] });
        QVD::Admin4::Exception->throw(code => 7120, query => 'delete') 
	    if $rs->count;
}

# When deleting a di with head or default tags, 
# it reassigns head and default tags to other di 

sub di_no_head_default_tags
{
    my ($self,$di) = @_;

    for my $tag (qw/default head/) 
    {
	next unless $di->has_tag($tag);
	my @potentials = grep { $_->id ne $di->id } $di->osf->dis;
	if (@potentials) {
	    my $new_di = $potentials[-1];
	    $DB->resultset('DI_Tag')->create({di_id => $new_di->id, tag => $tag});
	}
    }
    return 1;
}

# When deleting a di, it deletes the related disk image 

sub di_delete_disk_image
{
    my ($self,$di) = @_;

    my $images_path  = eval { cfg('path.storage.images') } // return 1;
    my $images_file = $di->path;
    eval { unlink "$images_path/$images_file" };
}

# It checks if a config token is not only present in DB. Throws an exception otherwise

sub is_not_custom_config
{
    my ($self,$obj) = @_;
    QVD::Admin4::Exception->throw(code=>'7372') if defined eval { core_cfg($obj->key) };
    return 1;
}

# It checks if a config token is only present in DB. Throws an exception otherwise

sub is_custom_config
{
    my ($self,$obj) = @_;
    QVD::Admin4::Exception->throw(code=>'7371') unless defined eval { core_cfg($obj->key) };
    return 1;
}

# Check if the current admin is allowed to change the specified configuration

sub is_admin_allowed_to_config
{
	my ($self,$request) = @_;

	# Get current administrator
	my $admin = $request->qvd_object_model->current_qvd_administrator;

	# Check if configuration parameter to be changed is a global parameter
	my $col = QVD::Admin4::ConfigsOverwriteList->new(admin_id => $admin->id);
	my $col_re = $col->configs_global_re;
	my $general_config = ($request->get_adequate_value('key') =~ /$col_re/);

	# Get the tenant_id the change will take place
	my $tenant_id = $request->get_adequate_value('tenant_id') // $admin->tenant_id;

	# Common administrators can only modify configuration in his tenant
	if(!$admin->is_superadmin && ($admin->tenant_id != $tenant_id)){
		QVD::Admin4::Exception->throw(code => 4230);
	}

	# Local tokens cannot be defined as global
	if($tenant_id == -1 && !$general_config){
		QVD::Admin4::Exception->throw(code => 7380);
	}

	# Global tokens cannot be defined locally for a tenant
	if($tenant_id != -1 && $general_config){
		QVD::Admin4::Exception->throw(code => 7381);
	}

	return 1;
}

######################################
## AD HOC FUNCTIONS WITHOUT REQUEST
######################################

# All these functions are used to process special actions of the API
# They all take a JSON as argument instead of the request of the general
# functions

# Retrieves all fields 'source' in the log table of the database

sub sources_in_wat
{
    my $self = shift;

    my @sources = 
    grep { defined $_->{name} }
    map { { name => $_->source } }  
    $DB->resultset('Log')->search(
	{},{ distinct => 1, select => [qw(source)]})->all;

    { rows => \@sources , total => scalar @sources };
}

# Retrieves all the disk images in the staging directory

sub dis_in_staging
{
    my $self = shift;

    my $staging_path = cfg('path.storage.staging');
    QVD::Admin4::Exception->throw(code=>'2230')
	unless -d $staging_path;
    my $dir;
    opendir $dir, $staging_path;
    my @files = grep { $_ !~ /^\.{1,2}$/ } readdir $dir; 

    { rows => [map { { name => $_ } } @files ] , total => scalar @files };
}

# Retrieves to the WAT info needed to setup the enviroment
# according to the administrator that performs the query.

sub current_admin_setup
{
    my ($self,$administrator,$json_wrapper) = @_;

    my $localtime = localtime();

    { server_datetime => $localtime,
      multitenant => cfg('wat.multitenant'),
      admin_language => $administrator->wat_setups->language,
      tenant_language => $administrator->tenant->wat_setups->language,
      admin_block => $administrator->wat_setups->block,
      tenant_block => $administrator->tenant->wat_setups->block,
      admin_id => $administrator->id,
      tenant_id => $administrator->tenant_id,
      acls => [ $administrator->acls ],
      views => [ map { { $_->get_columns } }
		 $DB->resultset('Operative_Views_In_Administrator')->search(
		     {administrator_id => $administrator->id})->all ]};
}

# This function receives an administrator and a list of acl patterns. 
# And it returns the number of acls available for that administrator.

sub get_number_of_acls_in_admin
{
    my ($self,$administrator,$json_wrapper) = @_;

    my $acl_patterns = $json_wrapper->get_filter_value('acl_pattern') // '%';
    $acl_patterns = ref($acl_patterns) ? $acl_patterns : [$acl_patterns];
    my $admin_id = $json_wrapper->get_filter_value('admin_id') //
	QVD::Admin4::Exception->throw(code=>'6220', object => 'admin_id');
    my $aol = QVD::Admin4::AclsOverwriteList->new(admin_id => $admin_id);
    my $bind = [$aol->acls_to_close_re,$aol->acls_to_open_re,$aol->acls_to_hide_re];

    my $rs = $DB->resultset('Operative_Acls_In_Administrator')->search(
	{},{bind => $bind})->search({admin_id => $admin_id});

    $self->get_number_of_acls($rs,$acl_patterns);
}

sub get_number_of_acls_in_admin_old
{
    my ($self,$administrator,$json_wrapper) = @_;

    my $acl_patterns = $json_wrapper->get_filter_value('acl_pattern') // '%';
    $acl_patterns = ref($acl_patterns) ? $acl_patterns : [$acl_patterns];
    my $admin_id = $json_wrapper->get_filter_value('admin_id') //
        QVD::Admin4::Exception->throw(code=>'6220', object => 'admin_id');

# This view needs to bind three placeholders. The values of the 
# placeholders must be regular expresions that define lists of 
# acls forbidden, allowed or hidden for the current administrator. 
# Those lists of acls are the acls that should be overwritten 
# over the regular assignation of acls for the administrator.

    my $aol = QVD::Admin4::AclsOverwriteList->new(admin_id => $admin_id);
    my $bind = [$aol->acls_to_close_re,$aol->acls_to_open_re,$aol->acls_to_hide_re];

    my $rs = $DB->resultset('Operative_Acls_In_Administrator')->search(
        {},{bind => $bind})->search({admin_id => $admin_id});

    $self->get_number_of_acls($rs,$acl_patterns);
}

# This function receives a role and a list of acl patterns. 
# And it returns the number of acls available for that role.

sub get_number_of_acls_in_role
{
    my ($self,$administrator,$json_wrapper) = @_;

    my $acl_patterns = $json_wrapper->get_filter_value('acl_pattern') // '%';
    $acl_patterns = ref($acl_patterns) ? $acl_patterns : [$acl_patterns];
    my $role_id = $json_wrapper->get_filter_value('role_id') //
        QVD::Admin4::Exception->throw(code=>'6220', object => 'role_id');

# This view needs to bind two placeholders. The values of the 
# placeholders must be regular expresions that define lists of 
# acls forbidden or hidden for the current administrator. 
# Those lists of acls are the acls that should be overwritten 
# over the regular assignation of acls for the administrator.

    my $aol = QVD::Admin4::AclsOverwriteList->new(admin => $administrator,admin_id => $administrator->id);
    my $bind = [$aol->acls_to_close_re,$aol->acls_to_hide_re];

    my $rs = $DB->resultset('Operative_Acls_In_Role')->search(
        {},{bind => $bind})->search({role_id => $role_id});

    $self->get_number_of_acls($rs,$acl_patterns);
}

sub get_number_of_acls
{
    my ($self,$rs,$acl_patterns) = @_;

    my @acl_patterns = @$acl_patterns;
    $_ =~ s/\./[.]/g for @acl_patterns;
    $_ =~ s/%/.*/g for @acl_patterns;
    my %acl_patterns;
    @acl_patterns{@$acl_patterns} = @acl_patterns;

    my $output;
    $output->{$_} = { total => 0, effective => 0} for @$acl_patterns;

    for my $acl ($rs->all)
    {
        for my $acl_pattern (@$acl_patterns)
        {
            my $re = $acl_patterns{$acl_pattern};
            next unless $acl->acl_name =~ /$re/;
            $output->{$acl_pattern}->{total}++;
            $output->{$acl_pattern}->{effective}++ if $acl->operative;
        }
    }

#    $output->{$_}->{total} || delete $output->{$_} 
#    for keys %$output;

    $output;
}

# Statistics functions

sub users_count
{
    my ($self,$admin) = @_;
    $DB->resultset('User')->search(
	{'me.tenant_id' => $admin->tenants_scoop})->count;
}

sub blocked_users_count
{
    my ($self,$admin) = @_;
    $DB->resultset('User')->search(
	{ 'me.blocked' => 'true',
	  'me.tenant_id' => $admin->tenants_scoop})->count;
}

sub connected_users_count
{
    my ($self,$admin) = @_;
    $DB->resultset('VM')->search(
	{ 'vm_runtime.user_state' => 'connected',
	  'user.tenant_id' => $admin->tenants_scoop }, 
	{ columns => [ qw/user.id/ ],
	distinct => 1, 
	join => [qw(vm_runtime user)] })->count;
}

sub vms_count
{
    my ($self,$admin) = @_;
    $DB->resultset('VM')->search(
	{'user.tenant_id' => $admin->tenants_scoop},
	{ join => [qw(user)] })->count;
}

sub blocked_vms_count
{
    my ($self,$admin) = @_;
    $DB->resultset('VM')->search(
	{ 'vm_runtime.blocked' => 'true',
	  'user.tenant_id' => $admin->tenants_scoop }, 
	{ join => [qw(vm_runtime user)] })->count;
}

sub running_vms_count
{
    my ($self,$admin) = @_;
    $DB->resultset('VM')->search(
	{ 'vm_runtime.vm_state' => 'running',
	  'user.tenant_id' => $admin->tenants_scoop }, 
	{ join => [qw(vm_runtime user)] })->count;
}

sub hosts_count
{
    my ($self,$admin) = @_;
    $DB->resultset('Host')->search()->count;
}

sub blocked_hosts_count
{
    my ($self,$admin) = @_;

    $DB->resultset('Host')->search(
	{ 'runtime.blocked' => 'true' },
	{ join => [qw(runtime)] })->count;
}

sub running_hosts_count
{
    my ($self,$admin) = @_;
    $DB->resultset('Host')->search(
	{ 'runtime.state' => 'running' },
	{ join => [qw(runtime)] })->count;
}

sub osfs_count
{
    my ($self,$admin) = @_;
    $DB->resultset('OSF')->search(
	{'me.tenant_id' => $admin->tenants_scoop})->count;
}

sub dis_count
{
    my ($self,$admin) = @_;
    $DB->resultset('DI')->search(
	{ 'osf.tenant_id' => $admin->tenants_scoop }, 
	{ join => [qw(osf)] })->count;
}

sub blocked_dis_count
{
    my ($self,$admin) = @_;
    $DB->resultset('DI')->search(
	{ 'osf.tenant_id' => $admin->tenants_scoop,
	  'me.blocked' => 'true' }, 
	{ join => [qw(osf)] })->count;
}

sub vms_with_expiration_date
{
    my ($self,$admin) = @_;

    my $is_not_null = 'IS NOT NULL';
    my $rs = $DB->resultset('VM')->search(
	{ 'osf.tenant_id' => $admin->tenants_scoop,
	  'vm_runtime.vm_expiration_hard'  => \$is_not_null },
	{ join => [qw(vm_runtime osf)],
	  prefetch => [qw(vm_runtime)]});

    my $now = DateTime->now();

    [ sort { DateTime->compare($a->{expiration},$b->{expiration}) }
      grep { sum(values %{$_->{remaining_time}}) > 0 }
      map {{ name            => $_->name, 
	     id              => $_->id,
	     expiration      => $_->vm_runtime->vm_expiration_hard,
	     remaining_time  => $_->remaining_time_until_expiration_hard }}

      $rs->all ];
}

sub top_populated_hosts
{
    my ($self,$admin) = @_;

    #my $rs = $DB->resultset('Host')->search({ 'vms.vm_state' => 'running'}, 
    my $rs = $DB->resultset('Host')->search({}, 
					    { distinct => 1, 
                                              join => [qw(vms)] });
    return [] unless $rs->count;

    my @hosts = sort { $b->{number_of_vms} <=> $a->{number_of_vms} }
                map {{ name          => $_->name, 
		       id            => $_->id,
		       number_of_vms => $_->vms_count }} 
                $rs->all;
    my $array_limit = $#hosts > 5 ? 5 : $#hosts;    
    return [@hosts[0 .. $array_limit]];
}

# It returns the list of prefixes of the configuration tokens 
# of the system: For example, for wat.multitenant, the prefix is
# wat.

sub config_preffix_get
{
    my ($self,$admin,$json_wrapper) = @_;

	# Tenant is sent as an argument if superadmin
	my $tenant = $admin->is_superadmin ? $json_wrapper->get_filter_value("tenant_id") : $admin->tenant_id;

	my @keys = cfg_keys($tenant);
    my %preffix;

	# Several configuration tokens of the sistem are not allowed to be used from the API
	# The class QVD::Admin4::ConfigsOverwriteList provides the regex that defines the
	# tokens available from the API.

    my $col = QVD::Admin4::ConfigsOverwriteList->new(admin_id => $admin->id);
	my $col_re = $col->configs_to_show_re($tenant);
    my $unclassified;

    for (@keys)
    {
	next unless m/$col_re/;
	if (m/^([^.]+)\./) 
	{  
	    $preffix{$1} = 1;
	}
	else
	{
	    $unclassified = 1;
	}
    }
    my @preffix = sort keys %preffix; 
    push @preffix, 'unclassified' if $unclassified;
    { total => scalar @preffix,
      rows => \@preffix };
}

sub config_get
{
    my ($self,$admin,$json_wrapper) = @_;

	# Tenant is sent as an argument if superadmin
	my $tenant = $admin->is_superadmin ? $json_wrapper->get_filter_value("tenant_id") : $admin->tenant_id;

	# Several configuration tokens of the sistem are not allowed to be used from the API
	# The class QVD::Admin4::ConfigsOverwriteList provides the regex that defines the
	# tokens available from the API.

    my $col = QVD::Admin4::ConfigsOverwriteList->new(admin_id => $admin->id);
	my $col_re = $col->configs_to_show_re($tenant);
    my $cp = $json_wrapper->get_filter_value('key');
    my $cp_re = $json_wrapper->get_filter_value('key_re');
	my @keys = cfg_keys($tenant);
    @keys = grep { $_ =~ /\Q$cp\E/ } @keys if $cp;
    @keys = grep { $_ =~ /$cp_re/ } @keys if $cp_re;
    @keys = grep { $_ =~ /$col_re/ } @keys;

    my $od = $json_wrapper->order_direction // '-asc';

    my $total = scalar @keys;
    my $block = $json_wrapper->block // $total;
    my $offset = $json_wrapper->offset // 1;

    my $page = Data::Page->new($total, $block, $offset);

    @keys = sort { $a cmp $b } @keys;
    @keys = reverse @keys if $od eq '-desc'; 
    @keys = $page->splice(\@keys);

   { total => $total,
     rows => [ map {{ key => $_, 
	operative_value => cfg($_, $tenant),
		      default_value => (defined eval{ core_cfg($_)} ? core_cfg($_) : undef) }} @keys ] };
}

sub config_ssl {
    my ($self,$admin,$json_wrapper) = @_;
    my $cert = $json_wrapper->get_argument_value('cert') //
	QVD::Admin4::Exception->throw(code=>'6240', object => 'cert');

    my $key = $json_wrapper->get_argument_value('key') //
	QVD::Admin4::Exception->throw(code=>'6240', object => 'key');

    my $crl = $json_wrapper->get_argument_value('crl');

    my $ca = $json_wrapper->get_argument_value('ca');

    rs("SSL_Config")->update_or_create({ key => 'l7r.ssl.cert',
                                       value => $cert });
    rs("SSL_Config")->update_or_create({ key => 'l7r.ssl.key',
                                       value => $key });

    if (defined $crl) {
        rs("SSL_Config")->update_or_create({ key => 'l7r.ssl.crl',
                                           value => $crl })
    }
    else {
        rs("SSL_Config")->search({ key => 'l7r.ssl.crl' })->delete;
    }

    if (defined $ca) {
        rs("SSL_Config")->update_or_create({key => 'l7r.ssl.ca',
                                          value => $ca });
    }
    else {
        rs("SSL_Config")->search({ key => 'l7r.ssl.ca' })->delete;
    }

    QVD::Config::reload(); # To refresh config tokens in QVD::Config 
#    notify('qvd_config_changed');
    
    { total => 1,
     rows => [ ] };
}

sub config_wat_get
{
	my ($self,$request) = @_;

	# Get current administrator
	my $admin = $request->qvd_object_model->current_qvd_administrator;

	# Tenant is sent as an argument if superadmin
	my $tenant = $admin->tenant_id;

	my $row;
	eval {
		my $rs = $DB->resultset($request->table)->search({tenant_id => $tenant});
		$row = $rs->first;
	};

	QVD::Admin4::Exception->throw(exception => $@, query => 'select') if $@;

	{
		total => 1,
		rows => [ $row ],
	};
}

sub config_wat_update
{
	my ($self,$request) = @_;

	# Get current administrator
	my $admin = $request->qvd_object_model->current_qvd_administrator;

	# Tenant is sent as an argument if superadmin
	my $tenant = $admin->tenant_id;

	my @rows;
	eval {
		for my $obj ($DB->resultset($request->table)->search({tenant_id => $tenant})->all){
			$DB->txn_do( sub {
				# Update the main object
				$obj->update($request->arguments);
				# Update tables related to the main object (i.e. vm_runtimes for vms)
				$self->update_related_objects($request,$obj);
			} );
		}
	};

	QVD::Admin4::Exception->throw(exception => $@, query => 'update') if $@;

	{
		rows => [],
	};
}

1;
