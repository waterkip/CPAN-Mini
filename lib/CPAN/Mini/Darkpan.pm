package CPAN::Mini::Darkpan;
use strict;
use warnings;

use parent 'CPAN::Mini';

use File::Spec;

sub _install_indices {
    my $self = shift;
    $self->SUPER::_install_indices(@_);

    my $orepan_index = $self->{orepan_package_path};
    return unless $orepan_index && -e $orepan_index;

    my $packages_file = File::Spec->catfile(
        $self->{local}, qw(modules 02packages.details.txt.gz)
    );
    return unless -e $packages_file;

    require OrePAN2::Index;

    my $idx = OrePAN2::Index->new;
    $idx->load($orepan_index);

    my $cpan_idx = OrePAN2::Index->new;
    $cpan_idx->load($packages_file);

    $idx->merge(
        $cpan_idx,
        protect_author =>
            [ split /\s+/, ($self->{orepan_protect_author} || '') ],
    );

    $idx->write_gzip($packages_file);
}

1;
__END__

=head1 NAME

CPAN::Mini::Darkpan - merge a darkpan's own package index back into the minicpan mirror

=head1 SYNOPSIS

    minicpan -c CPAN::Mini::Darkpan -C /opt/cpan/.minicpanrc

In F<.minicpanrc>:

    orepan_package_path: /opt/cpan/orepan/02packages.details.txt.gz
    orepan_protect_author: DUMMY WATERKIP

=head1 DESCRIPTION

Subclasses L<CPAN::Mini> so that every mirror run also merges in the
02packages index of a companion darkpan (e.g. an L<OrePAN2::Server>
instance), so a periodic minicpan sync doesn't clobber locally uploaded
packages out of the mirror's index. Mirrors the same merge that
L<OrePAN2::Server> performs on upload, run from the other direction.

If C<orepan_package_path> isn't set or doesn't exist yet, or the mirror's
own C<02packages.details.txt.gz> doesn't exist yet either, this behaves
exactly like plain C<CPAN::Mini> -- no merge is attempted.

C<orepan_protect_author> is an optional space-separated list of PAUSE
ids. Any package whose darkpan index entry is authored by one of these
ids (i.e. its path looks like C<X/XX/AUTHORID/...>) keeps its darkpan
version even if the CPAN mirror has a numerically higher version of the
same package. Matching is case-insensitive. All other packages use
ordinary "higher version wins" semantics.

If a configured C<orepan_protect_author> id matches zero packages (a
typo, or nothing from that author has been uploaded yet), a warning is
emitted -- it doesn't fail the sync, but it means that id currently
protects nothing.

=cut
