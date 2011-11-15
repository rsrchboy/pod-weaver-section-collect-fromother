package Pod::Weaver::Section::Collect::FromOther;

# ABSTRACT: Import sections from other POD

use Moose;
use namespace::autoclean;

use Moose::Autobox; # XXX I'm... hesitant.

use Path::Class;

use PPI;
use Pod::Elemental::Selectors -all;
use Pod::Elemental;
use Pod::Elemental::Document;
use Pod::Elemental::Element::Pod5::Command;
use Pod::Elemental::Transformer::Gatherer;

use Pod::Weaver::Plugin::EnsurePod5;
use Pod::Weaver::Section::Collect;

#use Smart::Comments '###';

# XXX plugin roles...
with
    'Pod::Weaver::Role::Preparer',
    ;

has command => (is => 'ro', isa => 'Str', default => 'from_other', required => 1);

has header => (
    is       => 'ro',
    isa      => 'Str',
    lazy     => 1,
    required => 1,
    default  => sub { shift->plugin_name },
);

sub prepare_input {
    my ($self, $input) = @_;

    my $our_doc = $input->{pod_document};

    ### our command: $self->command
    my $selector = s_command($self->command);
    return unless $our_doc->children->grep($selector)->length;

    # find our commands
    my @elts;
    $our_doc->children->each_value(sub {

        do { push @elts, $_; return }
            unless $_->does('Pod::Elemental::Command') && $_->command eq $self->command;

        # run against other file and stash
        my ($module, $header_text, $command) = split / \/ /, $_->content;
        my @other_nodes = $self->copy_sections_from_other($module, $header_text, $command);

        ### @other_nodes
        ### @elts
        push @elts, @other_nodes; #$self->copy_sections_from_other($module, $header_text, $command);
    });

    $our_doc->children( [ @elts ] );

    ### $our_doc
    return;
}

sub _find_module {
    my ($self, $module) = @_;

    my @module_as_fn = split /::/, $module . '.pm';

    ### looking for: $module
    for my $dir (map { dir $_ } @INC) {

        my $fn = file $dir, @module_as_fn;
        return $fn if $fn->stat;
    }

    # XXX native logging?
    die "Cannot find $module in \@INC?!";
}

sub copy_sections_from_other {
    my ($self, $module, $header_text, $command) = @_;

    ### find our remote nodes to copy...
    my $selector = s_command('head1');
    my $fn = $self->_find_module($module);

    ### $fn
    my $other_doc = Pod::Elemental->read_file($fn);
    Pod::Elemental::Transformer::Pod5->new->transform_node($other_doc);

    my $nester = Pod::Elemental::Transformer::Nester->new({
         top_selector      =>  s_command('head1'),
         content_selectors => [
             s_command([ qw(head2 head3 head4 over item back) ]),
             s_flat,
         ],
    });

    my $container = Pod::Elemental::Element::Nested->new({
        command => 'head1',
        content => $self->header,
    });

    ### attack \$other_doc!...
    my @newbies;
    my $found_command = 0;

    $nester->transform_node($other_doc);
    $other_doc->children->each_value(sub {

        return unless $_->content eq $header_text;

        my @children = @{ $_->children };

        for my $child (@children) {

            # XXX we likely want to make this optional
            do { $found_command++ } if $child->does('Pod::Elemental::Command');
            next unless $found_command;
            push @newbies, $child;
        }
    });

    ### @newbies
    return (scalar @newbies ? (@newbies) : ());
}

__PACKAGE__->meta->make_immutable;

!!42;

__END__

=head1 DESCRIPTION

Copy chunks of POD from other documents, and incorporate them.

=head1 SEE ALSO

L<Pod::Weaver>, L<Pod::Weaver::Section::Collect>

=head1 BUGS

All complex software has bugs lurking in it, and this module is no exception.

Bugs, feature requests and pull requests through GitHub are most welcome; our
page and repo (same URI):

    https://github.com/RsrchBoy/pod-weaver-section-collect-fromother

=cut
