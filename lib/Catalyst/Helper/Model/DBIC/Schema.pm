package Catalyst::Helper::Model::DBIC::Schema;

use strict;
use warnings;

our $VERSION = '0.21';

use Carp;
use UNIVERSAL::require;

=head1 NAME

Catalyst::Helper::Model::DBIC::Schema - Helper for DBIC Schema Models

=head1 SYNOPSIS

  script/create.pl model CatalystModelName DBIC::Schema MyApp::SchemaClass [ create=dynamic | create=static ] [ connect_info arguments ]

=head1 DESCRIPTION

Helper for the DBIC Schema Models.

=head2 Arguments:

C<CatalystModelName> is the short name for the Catalyst Model class
being generated (i.e. callable with C<$c-E<gt>model('CatalystModelName')>).

C<MyApp::SchemaClass> is the fully qualified classname of your Schema,
which might or might not yet exist.  Note that you should have a good
reason to create this under a new global namespace, otherwise use an
existing top level namespace for your schema class.

C<create=dynamic> instructs this Helper to generate the named Schema
class for you, basing it on L<DBIx::Class::Schema::Loader> (which
means the table information will always be dynamically loaded at
runtime from the database).

C<create=static> instructs this Helper to generate the named Schema
class for you, using L<DBIx::Class::Schema::Loader> in "one shot"
mode to create a standard, manually-defined L<DBIx::Class::Schema>
setup, based on what the Loader sees in your database at this moment.
A Schema/Model pair generated this way will not require
L<DBIx::Class::Schema::Loader> at runtime, and will not automatically
adapt itself to changes in your database structure.  You can edit
the generated classes by hand to refine them.

C<connect_info> arguments are the same as what
DBIx::Class::Schema::connect expects, and are storage_type-specific.
For DBI-based storage, these arguments are the dsn, username,
password, and connect options, respectively.  These are optional for
existing Schemas, but required if you use either of the C<create=>
options.

Use of either of the C<create=> options requires L<DBIx::Class::Schema::Loader>.

=head1 TYPICAL EXAMPLES

  # Use DBIx::Class::Schema::Loader to create a static DBIx::Class::Schema,
  #  and a Model which references it:
  script/myapp_create.pl model CatalystModelName DBIC::Schema MyApp::SchemaClass create=static dbi:mysql:foodb myuname mypass

  # Same, but with extra Schema::Loader args (separate multiple values by commas):
  script/myapp_create.pl model CatalystModelName DBIC::Schema MyApp::SchemaClass create=static db_schema=foodb components=Foo,Bar exclude='^wibble|wobble$' dbi:Pg:dbname=foodb myuname mypass

  # See DBIx::Class::Schema::Loader::Base for list of options

  # Create a dynamic DBIx::Class::Schema::Loader-based Schema,
  #  and a Model which references it:
  script/myapp_create.pl model CatalystModelName DBIC::Schema MyApp::SchemaClass create=dynamic dbi:mysql:foodb myuname mypass

  # Reference an existing Schema of any kind, and provide some connection information for ->config:
  script/myapp_create.pl model CatalystModelName DBIC::Schema MyApp::SchemaClass dbi:mysql:foodb myuname mypass

  # Same, but don't supply connect information yet (you'll need to do this
  #  in your app config, or [not recommended] in the schema itself).
  script/myapp_create.pl model ModelName DBIC::Schema My::SchemaClass

=head1 METHODS

=head2 mk_compclass

=cut

sub mk_compclass {
    my ( $self, $helper, $schema_class, @connect_info) = @_;

    $helper->{schema_class} = $schema_class
        or croak "Must supply schema class name";

    my $create = '';
    if($connect_info[0] && $connect_info[0] =~ /^create=(dynamic|static)$/) {
        $create = $1;
        shift @connect_info;
    }

    my %extra_args;
    while (@connect_info && $connect_info[0] !~ /^dbi:/) {
        my ($key, $val) = split /=/, shift(@connect_info);

        if ((my @vals = split /,/ => $val) > 1) {
            $extra_args{$key} = \@vals;
        } else {
            $extra_args{$key} = $val;
        }
    }

    if(@connect_info) {
        $helper->{setup_connect_info} = 1;
        my @helper_connect_info = @connect_info;
        for(@helper_connect_info) {
            $_ = qq{'$_'} if $_ !~ /^\s*[[{]/;
        }
        $helper->{connect_info} = \@helper_connect_info;
    }

    if($create eq 'dynamic') {
        my @schema_parts = split(/\:\:/, $helper->{schema_class});
        my $schema_file_part = pop @schema_parts;

        my $schema_dir  = File::Spec->catfile( $helper->{base}, 'lib', @schema_parts );
        my $schema_file = File::Spec->catfile( $schema_dir, $schema_file_part . '.pm' );

        $helper->mk_dir($schema_dir);
        $helper->render_file( 'schemaclass', $schema_file );
    }
    elsif($create eq 'static') {
        my $schema_dir  = File::Spec->catfile( $helper->{base}, 'lib' );
        DBIx::Class::Schema::Loader->use("dump_to_dir:$schema_dir", 'make_schema_at')
            or croak "Cannot load DBIx::Class::Schema::Loader: $@";

        my @loader_connect_info = @connect_info;
        my $num = 6; # argument number on the commandline for "dbi:..."
        for(@loader_connect_info) {
            if(/^\s*[[{]/) {
                $_ = eval "$_";
                croak "Perl syntax error in commandline argument $num: $@" if $@;
            }
            $num++;
        }

# Check if we need to be backward-compatible.
        my $compatible = 0;

        my @schema_pm   = split '::', $schema_class;
        $schema_pm[-1] .= '.pm';
        my $schema_file = File::Spec->catfile($helper->{base}, 'lib', @schema_pm);

        if (-f $schema_file) {
            my $schema_code = do { local (@ARGV, $/) = $schema_file; <> };
            $compatible = 1 if $schema_code =~ /->load_classes/;
        }

        my @components = $compatible ? () : ('InflateColumn::DateTime');

        if (exists $extra_args{components}) {
            $extra_args{components} = [ $extra_args{components} ]
                unless ref $extra_args{components};

            push @components, @{ delete $extra_args{components} };
        }

        for my $re_opt (qw/constraint exclude/) {
            $extra_args{$re_opt} = qr/$extra_args{$re_opt}/
                if exists $extra_args{$re_opt};
        }

        if (exists $extra_args{moniker_map}) {
            die "The moniker_map option is not currently supported by this helper, please write your own DBIx::Class::Schema::Loader script if you need it."
        }

        make_schema_at(
            $schema_class,
            {
                relationships => 1,
                (%extra_args ? %extra_args : ()),
                (!$compatible ? (
                    use_namespaces => 1
                ) : ()),
                (@components ? (
                    components => \@components
                ) : ())
            },
            \@loader_connect_info,
        );
    }

    my $file = $helper->{file};
    $helper->render_file( 'compclass', $file );
}

=head1 SEE ALSO

General Catalyst Stuff:

L<Catalyst::Manual>, L<Catalyst::Test>, L<Catalyst::Request>,
L<Catalyst::Response>, L<Catalyst::Helper>, L<Catalyst>,

Stuff related to DBIC and this Model style:

L<DBIx::Class>, L<DBIx::Class::Schema>,
L<DBIx::Class::Schema::Loader>, L<Catalyst::Model::DBIC::Schema>

=head1 AUTHOR

Brandon L Black, C<blblack@gmail.com>

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;

__DATA__

=begin pod_to_ignore

__schemaclass__
package [% schema_class %];

use strict;
use base qw/DBIx::Class::Schema::Loader/;

__PACKAGE__->loader_options(
    relationships => 1,
    # debug => 1,
);

=head1 NAME

[% schema_class %] - DBIx::Class::Schema::Loader class

=head1 SYNOPSIS

See L<[% app %]>

=head1 DESCRIPTION

Generated by L<Catalyst::Model::DBIC::Schema> for use in L<[% class %]>

=head1 AUTHOR

[% author %]

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;

__compclass__
package [% class %];

use strict;
use base 'Catalyst::Model::DBIC::Schema';

__PACKAGE__->config(
    schema_class => '[% schema_class %]',
    [% IF setup_connect_info %]connect_info => [
        [% FOREACH arg = connect_info %][% arg %],
        [% END %]
    ],[% END %]
);

=head1 NAME

[% class %] - Catalyst DBIC Schema Model
=head1 SYNOPSIS

See L<[% app %]>

=head1 DESCRIPTION

L<Catalyst::Model::DBIC::Schema> Model using schema L<[% schema_class %]>

=head1 AUTHOR

[% author %]

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
