#!/usr/bin/perl -w
#This program is licensed under the BSD 2-Clause License a copy of which
#is included with this program.
# (c) Ian Malone 2012

use Image::ExifTool qw(ImageInfo);
use MIME::Base64;
use File::Basename qw(basename);
use strict;

my $prog = basename $0;

my %allowedmime = (
    "image/png" => {
	depth => sub {
	    my $EI = $_[0];
	    return if ! defined $EI->{BitDepth};
	    return $EI->{BitDepth};
	}
    },
    "image/jpeg" => {
	depth => sub {
	    my $EI = $_[0];
	    return if ! defined $EI->{BitsPerSample} ||
		! defined $EI->{ColorComponents};
	    return $EI->{BitsPerSample} * $EI->{ColorComponents};
	}
    }
);


my $wblock64 =  "block64";
my $wblockraw = "blockraw";
my $wtag =      "tag";

my %typenames = (
    Other => 0,
    FileIconSmall => 1,
    FileIcon      => 2,
    CoverFront => 3,
    CoverBack  => 4,
    Leaflet => 5,
    Media => 6,
    ArtistLead => 7,
    Artist => 8,
    Conductor => 9,
    Band => 10,
    Composer => 11,
    Lyricist => 12,
    Location => 13,
    Recording => 14,
    Performance => 15,
    ScreenCapture => 16,
    ABrightColouredFish => 17,
    Illustration => 18,
    BandLogo => 19,
    PublisherLogo => 20
    );


my %opt = readOpts(@ARGV);

if ( ! -f $opt{inimg} ) {
    print "Couldn't find $opt{inimg}\n";
    exit 1;
}

my $flacblock = fillBlockInfo($opt{inimg}, $opt{type}, $opt{desc});

printblock($flacblock) if $opt{verbose};

testiconsmall($flacblock) if $opt{type} == 1;

writeblock($flacblock, $opt{outname}, $opt{writemode});


sub readOpts {
    my %opt = (
	writemode => $wtag,
	inimg     => "",
	outname   => "",
	desc      => "",
	type      => 0,
	verbose   => 0
	);

    my $usage = getUsage();

    my $ARGPROBS=0;
    my $HELP = 0;
    while (my $arg = shift @_) {
	if ($arg eq "-i") {
	    if (@_ < 1) {
		print "$arg requires an argument\n";
		$ARGPROBS=1;
	    }
	    else {
		$opt{inimg} = shift @_;
	    }
	}
	elsif ($arg eq "-o") {
	    if (@_ < 1) {
		print "$arg requires an argument\n";
		$ARGPROBS=1;
	    }
	    else {
		$opt{outname} = shift @_;
	    }
	}
	elsif ($arg eq "-desc") {
	    if (@_ < 1) {
		print "$arg requires an argument\n";
		$ARGPROBS=1;
	    }
	    else {
		$opt{desc} = shift @_;
	    }
	}
	elsif ($arg eq "-type") {
	    if (@_ < 1) {
		print "$arg requires an argument\n";
		$ARGPROBS=1;
	    }
	    else {
		$opt{type} = shift @_;
	    }
	}
	elsif ($arg eq "-write") {
	    if (@_ < 1) {
		print "$arg requires an argument\n";
		$ARGPROBS=1;
	    }
	    else {
		my $reqmode = shift @_;
		my $gotmode = "";
		for my $test ($wblock64, $wblockraw, $wtag) {
		    $gotmode = $test if $test eq $reqmode;
		}
		if ( $gotmode ne "" ){
		    $opt{writemode} = $gotmode;
		}
		else {
		    print "'$reqmode' not recognised\n";
		    $ARGPROBS=1;
		}
	    }
	}
	elsif ($arg eq "-v") {
	    $opt{verbose} = 1;
	}
	elsif ($arg eq "-h" || $arg eq "-help") {
	    $HELP = 1;
	}
	else {
	    print "$arg not recognised\n";
	    $ARGPROBS=1;
	}
    }

    if ($HELP) {
	print $usage;
	exit 0;
    }

    if ($opt{inimg} eq "") {
	print "Need an input image\n";
	$ARGPROBS=1;
    }

    if (defined $opt{outname} eq "") {
	print "Need an output name\n";
	$ARGPROBS=1;
    }
    elsif ( -e $opt{outname} ) {
	print "$opt{outname} already exists\n";
	$ARGPROBS=1;
    }


    $opt{type} = $typenames{$opt{type}} if defined $typenames{$opt{type}};
    if ( ($opt{type} !~ /^\d+$/ || $opt{type} > 20) ) {
	# Regex doesn't allow <0
	print "Type must be in range [0:20] or from list (see help)\n";
	$ARGPROBS=1;
    }

    if ($ARGPROBS) {
	print "For help:\n$prog -h\n";
	exit 1;
    }
    return %opt;
}

sub getrawfile {
    my $inimg = $_[0];
    open FILE, "<", "$inimg" or die $!;
    binmode FILE;

    my $imgcontents;
    my $size=0;
    my $chunksize=200*1024;
    while ( ! eof(FILE) ) {
	my $read = read FILE, $imgcontents, $chunksize, $size;
	$size += $read;
    }
    if ($size < 1) {
	print "Couldn't read $inimg\n";
	exit 1;
    }
    close FILE;
    my $rawimg = {
	imgcontents => $imgcontents,
	imgsize     => $size
    };
    return $rawimg;
}


sub printBlock {
    my $blockinfo = $_[0];
    for my $key (keys %$blockinfo) {
	next if $key eq "imagecontents";
	print "$key $blockinfo->{$key}\n";
    }
}


sub fillBlockInfo {
    my ($inimg, $type, $desc) = @_;
    my $blockinfo = {
	type => $type,
	mime => "",
	desc => $desc,
	width     =>0,
	height    =>0,
	depth     =>0,
	palette   =>0,
	imagesize =>0
	};

    my $exifinfo = ImageInfo($inimg) or die $!;
    if ( !defined $exifinfo || !defined $exifinfo->{MIMEType} ) {
	print "Failed getting mime type for $inimg\n";
	exit 1;
    }

    my $mimetype=$exifinfo->{MIMEType};

    if ( ! defined $allowedmime{$mimetype} ) {
	print "$inimg has MIME Type '$exifinfo->{MIMEType}'\n";
	print (join(" ", "Allowed MIME types are",keys(%allowedmime))."\n");
	exit 1;
    }
    $blockinfo->{mime} = $mimetype;
    $blockinfo->{depth} =  $allowedmime{$mimetype}->{depth}($exifinfo);
    $blockinfo->{height} = $exifinfo->{ImageHeight};
    $blockinfo->{width} = $exifinfo->{ImageWidth};

    my $dataprob=0;
    for my $check  (qw(mime depth height width)) {
	if (! defined $blockinfo->{$check} ) {
	    print "Error determining $check.\n";
	}
    }
    if ($dataprob){
	exit 1;
    }

    $blockinfo->{mimelength}=length ($blockinfo->{mime});
    $blockinfo->{desclength}=length ($blockinfo->{desc});

    my $rawfile = getrawfile ($inimg);
    $blockinfo->{imagesize}=$rawfile->{imgsize};
    $blockinfo->{imagecontents}=$rawfile->{imgcontents};
    return $blockinfo;
}

sub packblock {
    my ($blockinfo) = $_[0];
    my $packformat = sprintf "(L[2]A[%d]LA[%d]L[5]a[%d])>",
        $blockinfo->{mimelength},
        $blockinfo->{desclength},
        $blockinfo->{imagesize};

    my $block = pack (
	$packformat,
	$blockinfo->{type},       #32bit
	$blockinfo->{mimelength}, #32bit
	$blockinfo->{mime},
	$blockinfo->{desclength}, #32bit
	$blockinfo->{desc},
	$blockinfo->{width},      #32bit
	$blockinfo->{height},     #32bit
	$blockinfo->{depth},      #32bit
	$blockinfo->{palette},    #32bit
	$blockinfo->{imagesize},  #32bit
	$blockinfo->{imagecontents}
    );
    return $block;
}


sub writeblock {
    my ($blockinfo, $outname, $writemode) = @_;
    my $block = packblock($blockinfo);
    my $output = "";
    if ( $writemode eq $wtag ) {
	$output = "METADATA_BLOCK_PICTURE=";
    }
    if ( $writemode eq $wblock64 || $writemode eq $wtag ) {
	$output .= encode_base64( $block, "" ) . "\n";
    }
    elsif ( $writemode eq $wblockraw ) {
	$output = $block;
    }

    open (OUT, ">", $outname) || die $!;
    binmode OUT or die $! if $writemode eq $wblockraw;
    if ( ! print OUT $output
	 ||
	 ! close OUT
	)
    {
	print "Error writing to $outname\n";
    }
}

sub testiconsmall {
    my ($blockinfo) = @_;
    my $okay =
	$blockinfo->{height} == 32 &&
	$blockinfo->{width} == 32 &&
	$blockinfo->{mime} eq "image/png"
	;
    if (!$okay) {
	die "FileIconSmall must be 32x32 png\n";
    }
}

sub getUsage {
    my $typelist = "";
    my @names = keys %typenames;
    @names = sort ({$typenames{$a}<=>$typenames{$b}} @names);
    for my $name (@names) {
	$typelist .= <<TYPELIST
	    $typenames{$name} - $name
TYPELIST
    }

    return <<USAGE;

$prog -i image -o outputfile [options]
    Create a FLAC metadata picture block for use in Ogg/Vorbis comments.

    -i image      : input image (png or jpeg supported)
    -o outputfile : output file name, may be as a tag file (default)
                    for vorbiscomment, the block (base64 encoded) or
                    the block (raw binary). See -writemode.
    -desc "Description" : The description string for the picture block
                    (default empty)
    -type N|name  : Image type (default 0) may be numerical or one of
                    the allowed names below. See
                    <http://flac.sourceforge.net/format.html#metadata_block_picture>
		    for the full descriptions
$typelist
    -write tag|block64|blockraw : Either write as a suitable tag for
                    vorbiscomment's -c option, the base 64 encoded
                    picture block only, or the block in raw format.
    -v            : verbose (reports block information)
    -h
    -help         : Usage information
    
USAGE
}
