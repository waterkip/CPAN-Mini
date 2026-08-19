use strict;
use warnings;
use utf8;

use File::Temp qw( tempdir );
use File::Spec;
use Test::More;

use CPAN::Mini::Darkpan;

sub write_gz_index {
    my ($path, @lines) = @_;
    require IO::Compress::Gzip;
    my $body = join '', map {"$_\n"} (
        'File:         02packages.details.txt',
        'Columns:      package name, version, path',
        '',
        @lines,
    );
    my $gz = IO::Compress::Gzip->new($path) or die "gzip $path: $!";
    $gz->print($body);
    $gz->close;
}

sub write_index {
    my ($path, @lines) = @_;
    open my $fh, '>', $path or die "open $path: $!";
    print {$fh} "File:         02packages.details.txt\n";
    print {$fh} "Columns:      package name, version, path\n\n";
    print {$fh} "$_\n" for @lines;
    close $fh;
}

sub read_gz {
    my ($path) = @_;
    return undef unless -e $path;
    require IO::Uncompress::Gunzip;
    my $fh = IO::Uncompress::Gunzip->new($path) or return undef;
    local $/;
    return <$fh>;
}

# Sets up separate scratch/local dirs, mirroring how CPAN::Mini actually
# uses them: files land in scratch first, then _install_indices copies
# them into local.
sub setup_local {
    my (%opt) = @_;

    my $dir     = tempdir( CLEANUP => 1 );
    my $local   = File::Spec->catdir($dir, 'local');
    my $scratch = File::Spec->catdir($dir, 'scratch');
    mkdir $local;
    mkdir $scratch;
    mkdir File::Spec->catdir($scratch, 'modules');

    if ($opt{seed_packages}) {
        write_gz_index(
            File::Spec->catfile($scratch, qw(modules 02packages.details.txt.gz)),
            @{ $opt{seed_packages} },
        );
    }

    my $local_packages
        = File::Spec->catfile($local, qw(modules 02packages.details.txt.gz));

    return ($local, $scratch, $local_packages);
}

subtest 'orepan_package_path unset behaves like plain CPAN::Mini (no crash)' => sub {
    my ($local, $scratch, $packages_file) = setup_local(
        seed_packages => ['Foo::Bar 1.00 A/AU/AUTHOR/Foo-Bar-1.00.tar.gz'],
    );

    my $self = bless {
        local     => $local,
        scratch   => $scratch,
        dirmode   => 0755,
        log_level => 'info',
    }, 'CPAN::Mini::Darkpan';

    eval { $self->_install_indices };
    is $@, '', 'does not die';

    like read_gz($packages_file), qr/Foo::Bar/, 'index is installed untouched';
};

subtest 'orepan_package_path pointing at a nonexistent file is a no-op' => sub {
    my ($local, $scratch, $packages_file) = setup_local(
        seed_packages => ['Foo::Bar 1.00 A/AU/AUTHOR/Foo-Bar-1.00.tar.gz'],
    );

    my $self = bless {
        local               => $local,
        scratch             => $scratch,
        dirmode             => 0755,
        log_level           => 'info',
        orepan_package_path => File::Spec->catfile($local, 'does-not-exist.txt'),
    }, 'CPAN::Mini::Darkpan';

    eval { $self->_install_indices };
    is $@, '', 'does not die';
    like read_gz($packages_file), qr/Foo::Bar/, 'index is still installed untouched';
};

subtest 'missing freshly-synced packages_file is a no-op, not a crash' => sub {
    # Deliberately don't seed scratch's packages file, simulating a sync
    # that hasn't produced an index yet.
    my ($local, $scratch, $packages_file) = setup_local();
    my $orepan_index = File::Spec->catfile($local, 'orepan.txt');
    write_index($orepan_index, 'Foo::Bar 0.01 D/DU/DUMMY/Foo-Bar-0.01.tar.gz');

    my $self = bless {
        local               => $local,
        scratch             => $scratch,
        dirmode             => 0755,
        log_level           => 'info',
        orepan_package_path => $orepan_index,
    }, 'CPAN::Mini::Darkpan';

    eval { $self->_install_indices };
    is $@, '', 'does not die when the CPAN index has not been synced yet';
    ok !-e $packages_file, 'no packages file materializes out of nothing';
};

subtest 'orepan_protect_author matching zero packages warns, does not die' => sub {
    my ($local, $scratch, $packages_file) = setup_local(
        seed_packages => ['Foo::Bar 2.00 C/CP/CPANAUTH/Foo-Bar-2.00.tar.gz'],
    );
    my $orepan_index = File::Spec->catfile($local, 'orepan.txt');
    write_index($orepan_index, 'Foo::Bar 0.01 D/DU/DUMMY/Foo-Bar-0.01.tar.gz');

    my $self = bless {
        local                 => $local,
        scratch               => $scratch,
        dirmode               => 0755,
        log_level             => 'info',
        orepan_package_path   => $orepan_index,
        orepan_protect_author => 'NOBODY',
    }, 'CPAN::Mini::Darkpan';

    my $stderr = do {
        open my $fh, '>', \my $captured or die $!;
        local *STDERR = $fh;
        eval { $self->_install_indices };
        $captured;
    };
    is $@, '', 'does not die';
    like $stderr, qr/NOBODY.*matched no packages/,
        'warns about the unmatched author';

    like read_gz($packages_file), qr{Foo::Bar\s+2\.00\s+C/CP/CPANAUTH},
        'unmatched protection falls back to ordinary version-wins (CPAN 2.00 wins)';
};

subtest 'orepan_protect_author matches case-insensitively' => sub {
    my ($local, $scratch, $packages_file) = setup_local(
        seed_packages => ['Foo::Bar 2.00 C/CP/CPANAUTH/Foo-Bar-2.00.tar.gz'],
    );
    my $orepan_index = File::Spec->catfile($local, 'orepan.txt');
    write_index($orepan_index, 'Foo::Bar 0.01 D/DU/DUMMY/Foo-Bar-0.01.tar.gz');

    my $self = bless {
        local                 => $local,
        scratch               => $scratch,
        dirmode               => 0755,
        log_level             => 'info',
        orepan_package_path   => $orepan_index,
        orepan_protect_author => 'dummy',
    }, 'CPAN::Mini::Darkpan';

    $self->_install_indices;

    like read_gz($packages_file), qr{Foo::Bar\s+0\.01\s+D/DU/DUMMY},
        'lower-case config value still protects the DUMMY package';
};

done_testing;
