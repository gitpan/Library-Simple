package Library::Simple;
use Library::Thesaurus;

require 5.005_62;
use strict;
use warnings;
use XML::DT;
use DB_File;
use Fcntl ;
use Data::Dumper ;
use CGI qw/:standard/;

require Exporter;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw( &mkdiglib &see_also);
our @EXPORT = qw( );
our $VERSION = '0.02';
our $marca = '===';

sub navigate {
  my ($self,%args) = @_;
  my @ids;
  my $html = "";

  my $sampleSize = $args{size} || 10;

  if (exists($args{p}) && $args{p} =~/!/) {
	$args{p}=$`;
	$args{t}=$';
  }

  if (exists($args{t}) && $args{t} eq "") {
    $args{t} = $self->{the}->top_name;
  }

  $html .= $self->{the}->navigate({expand => [ 'HAS','NT','INST' ]},%args);

  my @terms = (defined($args{t})?
	       $self->{the}->tc($args{t},'BT','POF','IOF'):
	       ($self->{the}->top_name));

  $html .= start_form('POST');
  $html .= "procurar ". textfield('p'). "em ";
  $html .= popup_menu('t', [ @terms ]);
  $html .= submit(" Procurar "), end_form;
  $html .= "<br><br>";

  if (defined($args{t})) {
    if (defined($args{p})) {
      @ids = (sort {$a <=> $b } ( $self->f4($args{p},$args{t}))) ;
    } else {
      @ids = (sort{$a <=> $b }( $self->f1($args{t})));
    }
  } else {
    if (defined($args{p})) {
      @ids = sort{$a <=> $b } ( $self->f3($args{p}));
    } else {
      #...
    }
  }

  my $total = scalar @ids;

  if ($total) {
    my ($low,$high);
    if (exists($args{page})) {
      ($low,$high) = ($args{page}*$sampleSize,
                      $args{page}*$sampleSize+9);
    } else {
      ($low,$high) = (0,9);
      $args{page} = 0;
    }
    $high = $total-1 if $high >= $total;

    # Print navigation bar
    if (defined($args{all}) && $args{all}) {
      $html.="<small>Ver as ";
      $html.="<a href=\"".url()."?".dump_url(%args,all=>0,page=>0);
      $html.="\">$sampleSize</a> primeiras entradas.";
      $html .= "</small><br><br>";
      $html .= $self->htmlofids(@ids);
    } else {
      $html.="<small>";
      $html .= "Entradas ".(1+$low)." a ".(1+$high)." de um total de $total.";
      if ($low != 0) {
	$html.="&nbsp;|&nbsp;";
	$html .= "<a href=\"".url()."?".dump_url(%args,all=>0,page=>$args{page}-1);
	$html .= "\">&lt;&lt;</a>";
      }
      if ($high < $total-1) {
	$html.="&nbsp;|&nbsp;";
	$html .= "<a href=\"".url()."?".dump_url(%args,all=>0,page=>$args{page}+1);
	$html .= "\">&gt;&gt;</a>";
      }
      $html.="&nbsp;|&nbsp;";
      $html.="<a href=\"".url()."?".dump_url(%args,all=>1)."\">all</a>";
      $html .= "</small><br><br>";
      $html .= $self->htmlofids(@ids[$low..$high]);
    }
  }
  $html;
}

sub mkdiglib{
  my $userconf = shift;
  my $i;

  ## First, create the directory (if it does not exists);
  mkdir $userconf->{name} unless -d $userconf->{name};

  ## Compute the thesaurus in storable format
  my $the=thesaurusLoad("$userconf->{thesaurus}");
  $the->storeOn("$userconf->{name}/thesaurus.store");

  my @a;
  my @regs = ();
  my $reftype;

  open(CATALOGS,">$userconf->{name}/catalogs.index");

  if ($reftype = ref($userconf->{catalog})) {
    ### THIS IS A MULTICATALOG
    my $catindex = 0;
    die ("Not an array of catalogs") unless $reftype eq "ARRAY";
    my @catalogs = @{$userconf->{catalog}};
    foreach my $catalog (@catalogs) {
      die "missing catalog filename" unless defined $catalog->{file};

      my @catalog_files = ();
      # check for the file name, or skip
      if (ref($catalog->{file}) eq "ARRAY") {
	@catalog_files = @{$catalog->{file}};
      } else {
	@catalog_files = ($catalog->{file});
      }
      for my $file (@catalog_files) {

	# check for the file type, or skip
	die "missing catalog type" unless defined $catalog->{type};
	my $type = $catalog->{type};

	print "Processing '$file'";
	my $count = 0;

	if (ref($type) eq "HASH") {
	  my $cid = 0;
	  # type is an hash of functions
	  my @entries = &{$type->{1}}($file);
	  for (@entries) {
	    print "."; $count++;
	    push @regs, [
			 "$catindex.$cid",
			 [&{$type->{2}}($_)],
			 boxing($userconf,&{$type->{3}}($_)),
			 &{$type->{4}}($_),
			];
	    $cid++;
	  }
	} elsif (ref($type) eq "ARRAY") {
	  #next, I dont know what to do with an array
	} else {
	  # type is an identifier
	}
	print "$count entries\n";
	print CATALOGS "$catindex:$file\n";
	$catindex++;
      }
    }
  } else {
    my @entries = &{$userconf->{catsyn}{1}}($userconf->{catalog});
    my $cid = 0;
    for (@entries) {
      push @regs, [
		   "0.$cid",
		   [&{$userconf->{catsyn}{2}}($_)],
		   boxing($userconf, &{$userconf->{catsyn}{3}}($_)),
		   &{$userconf->{catsyn}{4}}($_),
		  ];
      $cid++;
    }
    print CATALOGS "0:$userconf->{catalog}\n";
  }
  close CATALOGS;

  open(IDINCAT,">$userconf->{name}/entry-catalog.index");
  open(H1,">$userconf->{name}/relation.index");
  open(H2,">$userconf->{name}/text.index");
  open(LOG, ">$userconf->{name}/thesaurus.log");

  (unlink "$userconf->{name}/html.db"||die) if -f "$userconf->{name}/html.db";
  (unlink "$userconf->{name}/relations.db"|| die) if -f "$userconf->{name}/relations.db";

  my %h = ();
  my $hand1 = tie %h, "DB_File", "$userconf->{name}/html.db",
    O_RDWR|O_CREAT, 0664, $DB_BTREE or die $!;

  my %h2 = ();
  my $hand2 = tie %h2, "DB_File", "$userconf->{name}/relations.db",
    O_RDWR|O_CREAT, 0664, $DB_BTREE or die $!;

  print "Creating hashes";
  my %unknown;
  for(@regs) {
    $i++;
    print ".";
    print IDINCAT "$i:$_->[0]\n";
    my @rray = ();
    for my $_term_ (@{$_->[1]}) {
      push @{$unknown{$_term_}}, $_->[0] unless ($the->isdefined($_term_));
      push @rray, $the->translateTerm($_term_);
    }

    $h{$i}= $_->[2];
    print H1 "$i$marca", join(" / ", @rray),"\n";
    print H2 "$i$marca", $_->[3],"\n" ;

    for my $q ( @rray ) {
      $h2{$q} .= "$i|";
    }
  }
  close IDINCAT;
  print LOG "outros\n",
    join("\n",map{"# on registers ".join(",",@{$unknown{$_}})."\nNT\t$_"}sort keys %unknown),"\n";
  print "$i entries\n";

  close H1;
  close H2;

  open(H,">$userconf->{name}/relations.list");
  open(H1,">$userconf->{name}/relations.statistics");

  for(keys %h2){
    my  $howmany = $h2{$_} ;
    $howmany =~ s/\d//g;
    print H "$_\n";
    print H1 "$_$marca", length($howmany),"\n";
  }
  close H1;
  close H;

  close LOG;

  ## Compute sizes
  my $self = bless {
		    name => $userconf->{name},
		    the => thesaurusRetrieve("$userconf->{name}/thesaurus.store"),
		    db => \%h,
		    tt2 => \%h2,
		   };
  $the->setExternal("LEN");
  $the->describe("LEN","Number of documents: ");
  for my $term (keys %{$the->{defined}}) {
    my @ids = $self->f1($term);
    my $count = scalar @ids;
    $the->addRelation($term,"LEN",$count);
  }
  $the->storeOn("$userconf->{name}/thesaurus.store");

  undef $self;

  $hand1->sync(); 
  undef $hand1;
  untie %h;

  $hand2->sync();
  undef $hand2;
  untie %h2;

}

sub opendiglib{
  my $cf=shift;
  my %h;
  tie %h, "DB_File", "$cf->{name}/html.db", O_RDONLY, 0644, $DB_BTREE or die $!;
  my %h2;
  tie %h2, "DB_File", "$cf->{name}/relations.db", O_RDONLY, 0644, $DB_BTREE or die $!;
  return bless {name=> $cf->{name},
	 the => thesaurusRetrieve("$cf->{name}/thesaurus.store"),
	 db  => \%h,
	 tt2 => \%h2
	}
}

sub all {
  my $self = shift;
#  print header, Dumper($self);
  return (keys ( %{$self->{db}}));
}

sub f1{
  my ($self,$tt)=@_; 
  my @x = tt2ids($self, $self->{the}->tc($tt,"NT","HAS","INST") );
  return @x;
}

sub orf1{
  return tt2ids(@_);
}

sub andf1{
  my ($self,$tt1,$tt2)=@_; 
  my @r1 = f1($self,$tt1);
  my @r2 = f1($self,$tt2);
  inter(\@r1,\@r2);
}

sub f3{
  my ($self,$er)=@_;
  return grepcut1("$self->{name}/text.index", $er);
}

sub f4{
  my ($self,$er, $tt)=@_;
  my @r1 = f3($self,$er);
  my @r2 = f1($self,$tt);

  return inter(\@r1,\@r2);
}

sub oldinter{
 my ($l1,$l2)=@_;
 my %h = ();
 @h{@$l1} = @$l1;
 grep {defined ($_)} @h{@$l2};
}

sub union{      ##union of a list of lists
 my %h;
 for my $a (@_){
    @h{@$a} = @$a;
 }
 (keys %h);
}

sub inter{       ##intercption of a list of lists
 my %h;
 my $a = shift;
 @h{@$a} = @$a;
 my @r = keys %h;
 for $a (@_){
    @h{@r} = @r;
    @r = grep {defined ($_)} @h{@$a}; }
 @r;
}

sub tt2ids{
  my ($self,@tt)=@_;
  my @a=();
  my %a=();
  for my $tt(@tt){
     for(grepcut1("$self->{name}/relations.list",$tt)) {
	print "WARNING: \$_=$_\n" unless defined $self->{tt2}{$_};
        push(@a ,(split(/\|/,$self->{tt2}{$_})));
     }
  }
  @a{@a}=@a;
  (keys %a);
}

sub grepcut1{
  my ($f,$er)=@_; 
  open F, "$f" or die;
  my @r = ();
  while(<F>){ push(@r,$1) if (/$er/i && /^(.+?)($marca|\n)/); }
  close F;
  @r
}

sub htmlofids{
  my $self=shift;
  join("\n",
       ( map { exists($self->{db}{$_})?$self->{db}{$_}:"<!--\n.................$_ -->\n" 
	     } grep { defined($_) && $_ !~ /^(\s|\n|\t)*$/} @_));
}

sub dump_url {
   my %args = @_;
   return join("&",map { $args{$_}=~s/\s/+/g;"$_=$args{$_}"} keys %args);
}

sub boxing {
   my ($userconf, $title, $body, $url) = @_;
   my $return;

   if (defined($body)) {
   	if (defined($url) && $url !~ /^\s*$/) {
      		$title = "<a href=\"$url\">$title</a>";
   	}
   	$return = "<b>$title</b>";
   	$return.= "<div style=\"margin-left: 15px\"><small>$body</small></div>";
   } else {
	$return = $title;
   }

   $return = "<div style=\"margin: 10px; background-color:#dddddd ;border: solid thin; padding: 5px;\">$return</div>";

   $return =~ s!\^(.{1,90}?)\^!see_also($userconf, $1)!ge;

   return $return;
}

sub n {
  my $x = Library::Thesaurus::term_normalize(shift);
  $x =~ s/ /+/g;
  return $x;
}

sub see_also {
  my $conf = shift;
  my $term;
  my $url = "";
  if (ref($conf)) {
    $url = $conf->{navigate} || "";
    $term = shift;
  } else {
    $term = $conf;
  }

  my $string = shift || $term;
  my $query;

  if ($term =~ m/!/) {
    $query = "?t=".n($')."&p=".n($`);
    $string =~ s/^!//;
    $string =~ s/!$//;
  } else {
    $query = "?t=".n($term);
  }

  return "<a href=\"$url$query\">$string</a>";
}

1;
__END__

=head1 NAME

Library - Perl extension for Digital Library support

=head1 SYNOPSIS

  use Library;

  $a = mkdiglib($conf)

=head1 DESCRIPTION

Library::Simple uses Library::Thesaurus and a configuration file to
manage digital libraries in a simple way. For this purpose, we define
a digital library as a set of searchable catalogs and an ontology for
that subject. Library::Simple configuration file has a list of
catalogs with their respective parse information.

To this be possible, it should be some way to access any kind of
catalog: a plain text file, XML document, SQL database or anything
else. The only method possible is to define functions to convert these
implementation techniques into a mathematical definition. So, the user
should give four functions to this module to it be capable of use the
catalog. These functions are:

=over 4

=item split the catalog

Given a string (say, a catalog identifier) the function should return
a Perl array with all catalog entries. This array should be the same
everytime the function is called for the same catalog to maintain some
type of indexing. The function can use this string as a filename, a
SQL table identifier or anything else the function can understand.

=item terms for an entry

Given an entry with the format returned by the previous function, this
function should return a list of terms related to the object
catalogued by this entry. These terms will be used latter for
thesaurus integration.

=item html from the entry

Given an entry, return a piece of HTML code to be embebed when listing
records.

=item text from the entry

Given an entry, return the searchable text it includes.

=back

The following example shows a sample configuration file:

  $userconf = {
    catalog   => "/var/library/catalog.xml",
    thesaurus => "/var/library/thesaurus",
    navigate => "http://the.script.where.it/should/be/linked",
    name => 'libraryName',
    catsyn  => {
       1 => sub{ my $file=shift;
                 my $t=`cat $file`;
                 return ($t =~ m{(<entry.*?</entry>)}gs); },
       2 => sub{ my $f=shift;
                 my @r=();
                 while($f =~ m{<rel\s+tipo='(.*?)'>(.*?)</rel>}g)
                    { push @r, $2; }
                 @r; },
       3 => sub{ my $f=shift; &mp::cat::fichacat2html($f)},
       4 => sub{ my $f=shift;
                 $f =~ s{</?\w+}{ }g;
                 $f =~ s/(\s*[\n>"'])+\s*/,/g;
                 $f =~ s/\w+=//g;
                 $f =~ s/\s{2,}/ /g;
                 $f }  }  };

When using the C<mkdiglib> function with this configuration
information, the module will create a set of files with cached data
for quick response, inside a C<libraryName> directory. This function
returns a Library object.

The configuration file can refer to more than one catalog file. This
is done with the following syntax:


  $userconf = {
    thesaurus => "/var/library/thesaurus",
    name => 'libraryName',
    catalog   => [
      { file => "/var/library/catalog.xml",
        type => {
           1 => sub{ ... },
           2 => sub{ ... },
           3 => sub{ ... },
           4 => sub{ ... },
        } },
      { file => ["/var/library/data1.db", "/var/library/data2.db"],
        type => {
           1 => sub{ ... },
           2 => sub{ ... },
           3 => sub{ ... },
           4 => sub{ ... },
        } },    ] }


After creating the object, we can open it on another script with the
C<opendiglib> command wich receives the base name of the digital
library. The base name is the path where it was created concatenated
with the identifier used.

The most common way to use the digital library is to build a script
like:

  use Library::Simple;
  use CGI qw/:standard :cgi-bin/;

  my $library = "/var/library/libraryName";
  my %vars = Vars();

  print header;
  my $diglib = Library::Simple::opendiglib( { name => $library } );
  print $diglib->navigate(%vars);



=head1 AUTHOR

José João Almeida   <jj@di.uminho.pt>

Alberto Simões      <albie@alfarrabio.di.uminho.pt>

=head1 SEE ALSO

perl(1).

=cut

